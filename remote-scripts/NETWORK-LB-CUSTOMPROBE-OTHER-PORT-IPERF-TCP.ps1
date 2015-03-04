Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$fileUploaded = $false
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
	$hsNames = $isDeployed.Split("^")
	$hs1Name = $hsNames[0]
	$hs2Name = $hsNames[1]
	$testServiceData = Get-AzureService -ServiceName $hs1Name
	$dtapServiceData = Get-AzureService -ServiceName $hs2Name
	#Extract Test VM Data
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
	$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
	$hs1vm2IP = $hs1vm2.IpAddress
	$hs1vm2Hostname = $hs1vm2.InstanceName
	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
	$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh
	$hs1vm1ProbePort = GetProbePort -Endpoints $hs1vm1Endpoints -usage TCPtest
	$hs1vm2ProbePort = GetProbePort -Endpoints $hs1vm2Endpoints -usage TCPtest
	#Extract DTAP VM data
   	$dtapServer = $dtapServiceData | Get-AzureVM
	$dtapServerEndpoints = $dtapServer | Get-AzureEndpoint
	$dtapServerIp = $dtapServerEndpoints[0].Vip
	$dtapServerUrl = $dtapServer.DNSName
	$dtapServerUrl = $dtapServerUrl.Replace("http://","")
	$dtapServerUrl = $dtapServerUrl.Replace("/","")
	$dtapServerTcpport = GetPort -Endpoints $dtapServerEndpoints -usage tcp
	$dtapServerUdpport = GetPort -Endpoints $dtapServerEndpoints -usage udp
	$dtapServerSshport = GetPort -Endpoints $dtapServerEndpoints -usage ssh	
	LogMsg "Test Machine 1 : $hs1VIP : $hs1vm1sshport"
	LogMsg "Test Machine 2 : $hs1VIP : $hs1vm2sshport"
	LogMsg "DTAP Machine : $dtapServerIp : $hs1vm1sshport"
	$iperfTimeoutSeconds = $currentTestData.iperfTimeoutSeconds

	$cmd1="python start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"
	$cmd2="python start-server.py -p $hs1vm2tcpport && mv Runtime.log start-server.py.log -f"
	$cmd3=""
	$cmd11="python start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt"
	$cmd22="python start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt"
	
	$server1 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm1.IpAddress
	$server2 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeTcpPort $hs1vm2tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm2.IpAddress
	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd3 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$resultArr = @()


	foreach ($mode in $currentTestData.TestMode.Split(",")) 
	{
		mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
		try
		{
			$testResult = $null
			LogMsg "Starting test in $mode mode.."
			if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
			{#.........................................................................Client command will decided according to TestMode....
				$cmd3="python start-client.py -c $hs1VIP -p $hs1vm1tcpport -t$iperfTimeoutSeconds -P2" 
			}
			if(($mode -eq "URL") -or ($mode -eq "Hostname"))
			{
				$cmd3="python start-client.py -c $hs1ServiceUrl -p $hs1vm1tcpport -t$iperfTimeoutSeconds -P2"
			}
			mkdir $LogDir\$mode\Server1 -ErrorAction SilentlyContinue | out-null
			mkdir $LogDir\$mode\Server2 -ErrorAction SilentlyContinue | out-null
			$server1.logDir = $LogDir + "\$mode" + "\Server1"
			$server2.logDir = $LogDir + "\$mode" + "\Server2"
			$client.logDir = $LogDir + "\$mode"
			$client.cmd = $cmd3

			Function UploadFiles()
			{
				RemoteCopy -uploadTo $server1.ip -port $server1.sshPort -files $server1.files -username $server1.user -password $server1.password -upload
				RemoteCopy -uploadTo $server2.Ip -port $server2.sshPort -files $server2.files -username $server2.user -password $server2.password -upload
				RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload
				$out = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "chmod +x *.py" -runAsSudo
				$out = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "chmod +x *.py" -runAsSudo
				$out = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *.py" -runAsSudo
				$fileUploaded = $true
			}
			if (!$fileUploaded)
			{
				$fileUploaded =  UploadFiles
			}
			
			#Remove all prev. log files..
			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-server.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-server.txt" -runAsSudo

			$BothServersStared = GetStopWatchElapasedTime $stopWatch "ss"
			
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-probe.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-probe.txt" -runAsSudo

			#$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "python start-server.py -p $hs1vm1tcpport  && mv Runtime.log start-server.py.log -f" -runAsSudo
			#$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "python start-server.py -p $hs1vm1tcpport  && mv Runtime.log start-server.py.log -f" -runAsSudo
			$server1.cmd = $cmd1
			$server2.cmd = $cmd2
			StartIperfServer $server1
			StartIperfServer $server2
			
			#$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "python start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt" -runAsSudo
			#$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "python start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt" -runAsSudo
			$server1.cmd = $cmd11
			$server2.cmd = $cmd22
			StartIperfServer $server1
			StartIperfServer $server2
			WaitFor -seconds 15

			$isServerStarted1 = IsIperfServerStarted $server1
			$isServerStarted2 = IsIperfServerStarted $server2
			
			#WaitFor -seconds 30
			if(($isServerStarted1 -eq $true) -and ($isServerStarted2 -eq $true)) 
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
				if($isClientStarted -eq $true)
				{
#region Test Analysis
					LogMsg "Client Verification : level1 : Client Connected to Server."
					$server1State = IsIperfServerRunning $server1
					$server2State = IsIperfServerRunning $server2
					if(($server1State -eq $true) -and ($server2State -eq $true))
					{
						LogMsg "Server Verification : level1 : Server Connected to Client."
						$testResult = "PASS"
						$clientLog= $client.LogDir + "\iperf-client.txt"
						$isClientConnected = AnalyseIperfClientConnectivity -logFile $clientLog -beg "Test Started" -end "TestComplete"
						$clientConnCount = GetParallelConnectionCount -logFile $clientLog -beg "Test Started" -end "TestComplete"
						$server1CpConnCount = 0
						$server2CpConnCount = 0
						If ($isClientConnected) 
						{
							LogMsg "Client Verification : level2 : iperf-client.txt is error free."
							$server1Log= $server1.LogDir + "\iperf-server.txt"
							$server2Log= $server2.LogDir + "\iperf-server.txt"
							$isServerConnected1 = AnalyseIperfServerConnectivity $server1Log "Test Started" "TestComplete"
							$isServerConnected2 = AnalyseIperfServerConnectivity $server2Log "Test Started" "TestComplete"
							If (($isServerConnected1) -and ($isServerConnected2))
							{
								LogMsg "Server Verification : level2 : iperf-server.txt is error free."
								$connectStr1="$($server1.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
								$connectStr2="$($server2.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"

								$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Test Started" -end "TestComplete" -str $connectStr1
								$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Test Started" -end "TestComplete" -str $connectStr2
	#Verify Custom Probe Messages on both server, Custom Probe Messages must not be obsreved on LB Port
								$CPmessagesOnLBPortServer1 = IsCustomProbeMsgsPresent -logFile $server1Log -beg "Test Started" -end "TestComplete"
								$CPmessagesOnLBPortServer2 = IsCustomProbeMsgsPresent -logFile $server2Log -beg "Test Started" -end "TestComplete"
								If (!$CPmessagesOnLBPortServer1 -and !$CPmessagesOnLBPortServer2) 
								{
									$testResult = "PASS"
									LogMsg "Server Verification : level3 : Custom Probe messages are not present on server1 and server2 Load Balanced Port."
									LogMsg "Server1 Parallel Connection Count is $server1ConnCount"
									LogMsg "Server2 Parallel Connection Count is $server2ConnCount"
									$diff = [Math]::Abs($server1ConnCount - $server2ConnCount)
									If ((($diff/2)*100) -lt 20) 
									{
										$testResult = "PASS"
										LogMsg "Server Verification : level4 : Connection Counts are distributed evenly in both Servers."
										LogMsg "Diff between server1 and server2 is $diff"
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
								#Calculate Custome probe message count.
											$lap=($ClientStopped - $BothServersStarted)
											$cpFrequency1=$lap/$server1CpConnCount
											LogMsg "$server1CpConnCount Custom Probe Messages in $lap seconds observed on Server1.Frequency=$cpFrequency1"
											$cpFrequency2=$lap/$server2CpConnCount
											LogMsg "$server2CpConnCount Custom Probe Messages in $lap seconds observed on Server2.Frequency=$cpFrequency2"
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
									} 

									 
									else 
									{
										$testResult = "FAIL"
										LogErr "Connection Counts are not distributed correctly"
										LogErr "Diff between server1 and server2 is $diff"
									}
								}
								else 
								{
									$testResult = "FAIL"
									LogErr "Server Verification : level3 : Custom Probe messages are present on Load Balanced Port."
									if ($CPmessagesOnLBPortServer1)
									{
										$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1Log -beg "Test Started" -end "TestComplete"
										LogErr "$server1CpConnCount Custom Probe Messages observed on Server1"
									}
									if ($CPmessagesOnLBPortServer2) 
									{
										$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Test Started" -end "TestComplete"
										LogErr "$server2CpConnCount Custom Probe Messages observed on Server2"
									}
									
								}
							}
							else
							{
								$testResult = "FAIL"
								LogMsg "Server Verification : level2 : iperf-server.txt is not error free."
							}
						} 
						else
						{
							$testResult = "FAIL"
							LogMsg "Client Verification : level2 : iperf-client.txt is not error free."
						}
					} 
					else 
					{
						if(!$server1State)
						{
						LogErr "Server1 not connected to client."
						}
						if(!$server2State)
						{
						LogErr "Server2 not connected to client."
						}
						$testResult = "FAIL"
						LogErr "Server Verification : level1 : Server not connected to client."
					}
#endregion
				} 
				else 
				{
					LogErr "Client Verification 1 : level1 : Client not connected to Server."
					RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
					LogMsg "Test Finished..!"
					$testResult = "FAIL"
				}
			}
			else
			{
				if(!$isServerStarted1)
				{
					LogErr "Unable to start iperf-server on server 1."
				}
				if(!$isServerStarted2)
				{
					LogErr "Unable to start iperf-server on server 2."
				}
				LogErr "Aborting test."
				RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
				RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-server.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
				$testResult = "Aborted"
			}
			LogMsg "$($currentTestData.testName) : $mode : $testResult"
		}
		catch
		{
			$ErrorMessage =  $_.Exception.Message
			LogErr "EXCEPTION : $ErrorMessage"   
		}
		Finally
		{
			$metaData = "$mode" 
			if (!$testResult)
			{
				$testResult = "Aborted"
			}
			$resultArr += $testResult
			$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
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
