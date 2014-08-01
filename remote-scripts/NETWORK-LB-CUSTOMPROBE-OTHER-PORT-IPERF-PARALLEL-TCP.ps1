Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$result = ""
$testResult = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{


	$hs1Name = $isDeployed
	$testServiceData = Get-AzureService -ServiceName $hs1Name

#Get VMs deployed in the service..
	$testVMsinService = $testServiceData | Get-AzureVM

	$hs1vm1 = $testVMsinService[0]
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint

	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
	$hs1vm1IP = $hs1vm1.IpAddress
	$hs1vm1Hostname = $hs1vm1.InstanceName

	$hs1vm2 = $testVMsinService[1]
	$hs1vm2IP = $hs1vm2.IpAddress
	$hs1vm2Hostname = $hs1vm2.InstanceName

	$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
	$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh
	$hs1vm1ProbePort = GetProbePort -Endpoints $hs1vm1Endpoints -usage TCPtest
	$hs1vm2ProbePort = GetProbePort -Endpoints $hs1vm2Endpoints -usage TCPtest

	$dtapServerTcpport = "750"
	$dtapServerUdpport = "990"
	$dtapServerSshport = "22"
#$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP

	$cmd1="./start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"
	$cmd2="./start-server.py -p $hs1vm2tcpport && mv Runtime.log start-server.py.log -f"
	$cmd3=""

	$server1 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm1.IpAddress
	$server2 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeTcpPort $hs1vm2tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm2.IpAddress
	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd3 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$resultArr = @()


	foreach ($Value in $SubtestValues) 
	{
		mkdir $LogDir\$Value -ErrorAction SilentlyContinue | out-null
		foreach ($mode in $currentTestData.TestMode.Split(",")) 
		{
			mkdir $LogDir\$Value\$mode -ErrorAction SilentlyContinue | out-null
			try
			{
				$testResult = ""
				LogMsg "Starting test for $Value parallel connections in $mode mode.."
				if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
				{#.........................................................................Client command will decided according to TestMode....
					$cmd3="./start-client.py -c $hs1VIP -p $hs1vm1tcpport -t20 -P$Value" 
				}
				if(($mode -eq "URL") -or ($mode -eq "Hostname"))
				{
					$cmd3="./start-client.py -c $hs1ServiceUrl -p $hs1vm1tcpport -t20 -P$Value"
				}
				mkdir $LogDir\$Value\$mode\Server1 -ErrorAction SilentlyContinue | out-null
				mkdir $LogDir\$Value\$mode\Server2 -ErrorAction SilentlyContinue | out-null
				$server1.logDir = $LogDir + "\$Value\$mode" + "\Server1"
				$server2.logDir = $LogDir + "\$Value\$mode" + "\Server2"
				$client.logDir = $LogDir + "\$Value\$mode"
				$client.cmd = $cmd3

				Function UploadFiles()
				{
					RemoteCopy -uploadTo $server1.ip -port $server1.sshPort -files $server1.files -username $server1.user -password $server1.password -upload
					RemoteCopy -uploadTo $server2.Ip -port $server2.sshPort -files $server2.files -username $server2.user -password $server2.password -upload
					RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload

					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "chmod +x *" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "chmod +x *" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *" -runAsSudo
				}

				UploadFiles

				$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "rm -rf *.txt *.log" -runAsSudo
				$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "rm -rf *.txt *.log" -runAsSudo
				$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-server.txt" -runAsSudo
				$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-server.txt" -runAsSudo

#Step 1.1: Start Iperf Server on both VMs
				$stopWatch = SetStopWatch

				$BothServersStared = GetStopWatchElapasedTime $stopWatch "ss"
				StartIperfServer $server1
				StartIperfServer $server2
				$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-probe.txt" -runAsSudo
				$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-probe.txt" -runAsSudo

				$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "./start-server.py -p $hs1vm1tcpport  && mv Runtime.log start-server.py.log -f" -runAsSudo
				$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "./start-server.py -p $hs1vm1tcpport  && mv Runtime.log start-server.py.log -f" -runAsSudo


				$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "./start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt" -runAsSudo
				$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "./start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt" -runAsSudo

				WaitFor -seconds 15


				$isServerStarted = IsIperfServerStarted $server1
				$isServerStarted = IsIperfServerStarted $server2
				WaitFor -seconds 30
				if(($isServerStarted -eq $true) -and ($isServerStarted -eq $true)) 
				{
					LogMsg "Iperf Server1 and Server2 started successfully. Listening TCP port $($client.tcpPort) ..."
#>>>On confirmation, of server starting, let's start iperf client...
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshport -command "rm -rf *.txt *.log" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshport -command "echo Test Started > iperf-client.txt" -runAsSudo
					StartIperfClient $client
					$isClientStarted = IsIperfClientStarted $client
					$ClientStopped = GetStopWatchElapasedTime $stopWatch "ss"
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo TestComplete >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo TestComplete >> iperf-server.txt" -runAsSudo

#Add stop iperf server commands to stop the iperf server [server started for probe probe port]. Currently, frequency is getting recorded as 6-7 seconds which is wrong.

					if($isClientStarted -eq $true)
					{
#region Test Analysis
						$server1State = IsIperfServerRunning $server1
						$server2State = IsIperfServerRunning $server2
						if(($server1State -eq $true) -and ($server2State -eq $true))
						{
							LogMsg "Test Finished..!"
							$testResult = "PASS"
						} else {
							LogMsg "Test Finished..!"
							$testResult = "FAIL"
						}
						$clientLog= $client.LogDir + "\iperf-client.txt"
						$isClientConnected = AnalyseIperfClientConnectivity -logFile $clientLog -beg "Test Started" -end "TestComplete"
						$clientConnCount = GetParallelConnectionCount -logFile $clientLog -beg "Test Started" -end "TestComplete"
						$server1CpConnCount = 0
						$server2CpConnCount = 0
						If ($isClientConnected) 
						{
							$testResult = "PASS"
							$server1Log= $server1.LogDir + "\iperf-server.txt"
							$server2Log= $server2.LogDir + "\iperf-server.txt"
							$isServerConnected1 = AnalyseIperfServerConnectivity $server1Log "Test Started" "TestComplete"
							$isServerConnected2 = AnalyseIperfServerConnectivity $server2Log "Test Started" "TestComplete"
							If (($isServerConnected1) -and ($isServerConnected2))
							{
								$testResult = "PASS"

								$connectStr1="$($server1.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
								$connectStr2="$($server2.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"

								$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Test Started" -end "TestComplete" -str $connectStr1
								$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Test Started" -end "TestComplete" -str $connectStr2
#Verify Custom Probe Messages on both server, Custom Probe Messages must not be obsreved on LB Port

								If (!( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Test Started" -end "TestComplete") -and !(IsCustomProbeMsgsPresent -logFile $server2Log -beg "Test Started" -end "TestComplete")) 
								{
									LogMsg "No CustomProbe Messages Observed on both Server on LB Port"
									$testResult = "PASS"
									LogMsg "Server1 Parallel Connection Count is $server1ConnCount"
									LogMsg "Server2 Parallel Connection Count is $server2ConnCount"
									$diff = [Math]::Abs($server1ConnCount - $server2ConnCount)
									If ((($diff/$Value)*100) -lt 20) 
									{
										$testResult = "PASS"
										LogMsg "Connection Counts are distributed evenly in both Servers"
										LogMsg "Diff between server1 and server2 is $diff"
#$server1Dt= GetTotalDataTransfer -logFile $server1Log -beg "Test Started" -end "TestComplete"
#$server2Dt= GetTotalDataTransfer -logFile $server2Log -beg "Test Started" -end "TestComplete"
#$clientDt= GetTotalDataTransfer -logFile $clientLog -beg "Test Started" -end "TestComplete"
#LogMsg "Server1 Total Data Transfer is $server1Dt"
#LogMsg "Server2 Total Data Transfer is $server2Dt"
#LogMsg "Client Total Data Transfer is $clientDt"
#$totalServerDt = ([int]($server1Dt.Split("K")[0]) + [int]($server2Dt.Split("K")[0]))
#LogMsg "All Servers Total Data Transfer is $totalServerDt"
#If (([int]($clientDt.Split("K")[0])) -eq [int]($totalServerDt)) {
#    $testResult = "PASS"
#    LogMsg "Total DataTransfer is equal on both Server and Client"
#    #Analyse CustomProbe on Other CP Port
	if ($testResult -eq "PASS")
	{
		RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-probe.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
		RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-probe.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
		$server1CpLog= $server1.LogDir + "\iperf-probe.txt"
		$server2CpLog= $server2.LogDir + "\iperf-probe.txt"
		If (( IsCustomProbeMsgsPresent -logFile $server1CpLog) -and (IsCustomProbeMsgsPresent -logFile $server2CpLog))
		{
			$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1CpLog
			$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2CpLog
			LogMsg "$server1CpConnCount Custom Probe Messages observed on Server1 on CPPort"
			LogMsg "$server2CpConnCount Custom Probe Messages observed on Server2 on CPPort"
			$lap=($ClientStopped - $BothServersStarted)
			$cpFrequency=$lap/$server1CpConnCount
			LogMsg "$server1CpConnCount Custom Probe Messages in $lap seconds observed on Server1.Frequency=$cpFrequency"
			$cpFrequency=$lap/$server2CpConnCount
			LogMsg "$server2CpConnCount Custom Probe Messages in $lap seconds observed on Server2.Frequency=$cpFrequency"
			$testResult = "PASS"
		}
		else 
		{
			if (!( IsCustomProbeMsgsPresent -logFile $server1Log) ) 
			{
				LogErr "NO Custom Probe Messages observed on Server1 on CP Port"
				$testResult = "FAIL"
			}
			if (!(IsCustomProbeMsgsPresent -logFile $server2Log))
			{
				LogErr "NO Custom Probe Messages observed on Server2  on CP Port"
				$testResult = "FAIL"
			} 
		}
#CP Port Analysis Finished
	} else {
		$testResult = "FAIL"
		LogErr "Total DataTransfer is NOT equal on both Server and Client"
	}


} else {
	$testResult = "FAIL"
	LogErr "Connection Counts are not distributed correctly"
	LogErr "Diff between server1 and server2 is $diff"
}
} else {
	if ((IsCustomProbeMsgsPresent -logFile $server1Log -beg "Test Started" -end "TestComplete") ) {
		$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1Log -beg "Test Started" -end "TestComplete"
		LogErr "$server1CpConnCount Custom Probe Messages observed on Server1"
		$testResult = "FAIL"
	}
	if ((IsCustomProbeMsgsPresent -logFile $server2Log -beg "Test Started" -end "TestComplete")) {
		$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Test Started" -end "TestComplete"
		LogErr "$server2CpConnCount Custom Probe Messages observed on Server2"
		$testResult = "FAIL"
	} 
}


}
else
{
	$testResult = "FAIL"
	LogErr "Server is not Connected to Client"
}
} 
else
{
	$testResult = "FAIL"
	LogErr "Client is not Connected to Client"
}
#endregion
} 
else 
{
	LogErr "Failured detected in client connection."
	RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
	LogMsg "Test Finished..!"
	$testResult = "FAIL"
}
}
else
{
	LogMsg "Unable to start iperf-server. Aborting test."
	RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
	RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-server.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
	$testResult = "Aborted"
}
LogMsg "Test Finished for Parallel Connections $Value, result is $testResult"
}
catch
{
	$ErrorMessage =  $_.Exception.Message
	LogErr "EXCEPTION : $ErrorMessage"   
}
Finally
{
	$metaData = "$Value : $mode" 
	if (!$testResult)
	{
		$testResult = "Aborted"
	}
	$resultArr += $testResult
	$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
}   

}
}
}
else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}
$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result,$resultSummary
