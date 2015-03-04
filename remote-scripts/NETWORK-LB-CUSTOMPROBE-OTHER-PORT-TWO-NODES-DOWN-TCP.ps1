Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
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

	$wait=45
	$Value = 2
	$cmd1="python start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"
	$cmd2="python start-server.py -p $hs1vm2tcpport && mv Runtime.log start-server.py.log -f"
	$cmd3=""
	$cmd11="python start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt"
	$cmd22="python start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt"
	
	$server1 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm1.IpAddress
	$server2 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeTcpPort $hs1vm2tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm2.IpAddress
	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd3 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$resultArr = @()

#endregion

	foreach ($mode in $currentTestData.TestMode.Split(","))
	{
		mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
		try
		{
			$testResult = $null
			if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
			{
				$client.cmd = "python start-client.py -c $hs1VIP -p $hs1vm1tcpport -t$iperfTimeoutSeconds -P$Value"
			}

			if(($mode -eq "URL") -or ($mode -eq "Hostname"))
			{
				$client.cmd = "python start-client.py -c $hs1ServiceUrl -p $hs1vm1tcpport -t$iperfTimeoutSeconds -P$Value"
			}
#region Upload all Files in Test VMs

			mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
			mkdir $LogDir\$mode\Server1 -ErrorAction SilentlyContinue | out-null
			mkdir $LogDir\$mode\Server2 -ErrorAction SilentlyContinue | out-null
			$server1.logDir = $LogDir + "\$mode" + "\Server1"
			$server2.logDir = $LogDir + "\$mode" + "\Server2"
			$client.logDir = $LogDir + "\$mode"
			$client.cmd = "python start-client.py -c $hs1VIP -p $hs1vm1tcpport -t10 -P$Value"
			LogMsg "Test Started for Parallel Connections $Value"
			RemoteCopy -uploadTo $server1.ip -port $server1.sshPort -files $server1.files -username $server1.user -password $server1.password -upload
			RemoteCopy -uploadTo $server2.Ip -port $server2.sshPort -files $server2.files -username $server2.user -password $server2.password -upload
			RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload

			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "chmod +x *" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "chmod +x *" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "rm -rf *.txt *.log" -runAsSudo

			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-server.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-server.txt" -runAsSudo
#endregion


#Step 1.1: Start Iperf Server on both VMs
			$stopWatch = SetStopWatch
			$BothServersStarted_1 = GetStopWatchElapasedTime $stopWatch "ss"
			$server1.cmd = $cmd1
			$server2.cmd = $cmd2
			StartIperfServer $server1
			StartIperfServer $server2
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-probe.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-probe.txt" -runAsSudo
			#$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "python start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt" -runAsSudo
			#$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "python start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt" -runAsSudo
			
			$server1.cmd = $cmd11
			$server2.cmd = $cmd22
			StartIperfServer $server1
			StartIperfServer $server2
			
			$isServerStarted = IsIperfServerStarted $server1
			$isServerStarted = IsIperfServerStarted $server2
			sleep($wait)
			if(($isServerStarted -eq $true) -and ($isServerStarted -eq $true))
			{
				LogMsg "Iperf Server1 and Server2 started successfully. Listening TCP port $($client.tcpPort) ..."
#Step1.2: Start Iperf Client on Listening VM
				$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshport -command "echo Test Started > iperf-client.txt" -runAsSudo
				StartIperfClient $client
				$ClientStopped_1 = GetStopWatchElapasedTime $stopWatch "ss"
				$isClientStarted = IsIperfClientStarted $client

				if($isClientStarted -eq $true) 
				{
#region Test Case steps Execution
#Step 2: Stop Iperf client
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "python stop-client.py" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Stopped 1 >> iperf-client.txt" -runAsSudo

#Step 3 : Stop Iperf Server on VM1
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "python stop-server.py" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Both Servers Stopped 1 >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Both Servers Stopped 1 >> iperf-probe.txt" -runAsSudo
#Start iperf Server on Custom Probe Again, as stopping Iperfserver in above command have stopped all iperf server processes
#$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "python start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt" -runAsSudo

#Step 4 : Stop Iperf Server on VM2
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "python stop-server.py" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "echo Both Servers Stopped 1 >> iperf-server.txt" -runAsSudo			
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "echo Both Servers Stopped 1 >> iperf-probe.txt" -runAsSudo
#Start iperf Server on Custom Probe Again, as stopping Iperfserver in above command have stopped all iperf server processes
#$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "python start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt" -runAsSudo
					$BothServersStopped_1 = GetStopWatchElapasedTime $stopWatch "ss"

#Step 5 : Wait for 30 sec and then Start Iperf Client Again
					sleep($wait)
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Started 1 >> iperf-client.txt" -runAsSudo
					StartIperfClient $client

#Step 6: Stop Iperf client Again
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "python stop-client.py" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Stopped 2 >> iperf-client.txt" -runAsSudo
					$BothServersStarted_2 = GetStopWatchElapasedTime $stopWatch "ss"
#Step5 : Start Iperf Server on VM1 Again
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Both Servers Started 2 >> iperf-server.txt" -runAsSudo
					$server1.cmd = $cmd1
					StartIperfServer $server1
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Both Servers Started 2 >> iperf-probe.txt" -runAsSudo
#Start iperf Server on Custom Probe Again, as starting Iperfserver in above command have stopped all iperf server processes
					#$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "python start-server-without-stopping.py -p $hs1vm1ProbePort -log iperf-probe.txt" -runAsSudo
					$server1.cmd = $cmd11
					StartIperfServer $server1
#Step5 : Start Iperf Server on VM2 Again
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "echo Both Servers Started 2 >> iperf-server.txt" -runAsSudo
					$server2.cmd = $cmd2
					StartIperfServer $server2
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "echo Both Servers Started 2 >> iperf-probe.txt" -runAsSudo
#Start iperf Server on Custom Probe Again, as stopping Iperfserver in above command have stopped all iperf server processes
					#$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "python start-server-without-stopping.py -p $hs1vm2ProbePort -log iperf-probe.txt" -runAsSudo
					$server2.cmd = $cmd22
					StartIperfServer $server2
					
#Step6 : Wait for 30 sec and then Start Iperf Client Again
					sleep($wait)
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Started 2 >> iperf-client.txt" -runAsSudo
					StartIperfClient $client
					$ClientStopped_2 = GetStopWatchElapasedTime $stopWatch "ss"

					$isClientStarted = IsIperfClientStarted $client

					$server1State = IsIperfServerRunning $server1
					$server2State = IsIperfServerRunning $server2
					if(($server1State -eq $true) -and ($server2State -eq $true)) 
					{
						LogMsg "Both Servers Started"
						$testResult = "PASS"
					} 
					else
					{
						LogErr "Server Start Failed Server1 state is $server1State and Server2 state is $server2State"
						$testResult = "FAIL"
					}

# Step7 : Finish Tests, Echoing Bookmarks for Parsing
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo TestComplete >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo TestComplete >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo TestComplete >> iperf-probe.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo TestComplete >> iperf-probe.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo AllTestComplete >> iperf-client.txt" -runAsSudo
					$BothServersStopped_2 = GetStopWatchElapasedTime $stopWatch "ss"
# Copy All Logs
					RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
					RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-server.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
					RemoteCopy -download -downloadFrom $client.ip -files "/home/$user/start-client.py.log, /home/$user/iperf-client.txt" -downloadTo $client.LogDir -port $client.sshPort -username $client.user -password $client.password
#endregion
					$clientLog= $client.LogDir + "\iperf-client.txt"				
#region Test Analysis
#Test Analysis Begins
#Verify connectivity between client started and stopped first time
					$isClientConnected = AnalyseIperfClientConnectivity -logFile $clientLog -beg "Test Started" -end "Client Stopped 1"
					$clientConnCount = GetParallelConnectionCount -logFile $clientLog -beg "Test Started" -end "Client Stopped 1"
					$server1CpConnCount = 0
					$server2CpConnCount = 0
					If ($isClientConnected)
					{
						$testResult = "PASS"
						$server1Log= $server1.LogDir + "\iperf-server.txt"
						$server2Log= $server2.LogDir + "\iperf-server.txt"
						$isServerConnected1 = AnalyseIperfServerConnectivity -logFile $server1Log -beg "Test Started" -end "Both Servers Stopped 1"
						$isServerConnected2 = AnalyseIperfServerConnectivity -logFile $server2Log -beg "Test Started" -end "Both Servers Stopped 1"
						If (($isServerConnected1) -and ($isServerConnected2))
						{
							$testResult = "PASS"

							$connectStr1="$($server1.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
							$connectStr2="$($server2.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
#Get Number of connected streams for test step 1 between test started and Server1 stopped
							$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Test Started" -end "Both Servers Stopped 1" -str $connectStr1
							$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Test Started" -end "Both Servers Stopped 1" -str $connectStr2
#Verify Custom Probe Messages on both servers on  LB Port before both Servers are stopped, Custom Probe Messages must not be observed on LB Port
							If (!( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Test Started" -end "Both Servers Stopped 1") -and !(IsCustomProbeMsgsPresent -logFile $server2Log -beg "Test Started" -end "Both Servers Stopped 1"))
							{
								LogMsg "No CustomProbe Messages Observed on both Server on LB Port before Stopping both Server,CP and LB Port are different, hence no custom Probe should be observed on LB port"
								$testResult = "PASS"
								LogMsg "Server1 Parallel Connection Count before stopping Server1 is $server1ConnCount"
								LogMsg "Server2 Parallel Connection Count before stopping Server2 is $server2ConnCount"
								$diff = [Math]::Abs($server1ConnCount - $server2ConnCount)
								If ((($diff/$Value)*100) -lt 20)
								{
									$testResult = "PASS"
									LogMsg "Connection Counts are distributed evenly in both Servers before stopping Server1"
									LogMsg "Diff between server1 and server2 Connection Counts is $diff"
#Till Now verification of connectivity, Custom Probe and connection distribution is verified

#Start Verification of connectivity from Server1 and Server2 is stopped and both Servers are started back again
									$isServerConnected1 = AnalyseIperfServerConnectivity -logFile $server1Log -beg "Both Servers Stopped 1" -end "Both Servers Started 2"
									$isServerConnected2 = AnalyseIperfServerConnectivity -logFile $server2Log -beg "Both Servers Stopped 1" -end "Both Servers Started 2"
									If (($isServerConnected1 -eq $true) -and ($isServerConnected1 -eq $true))
									{
										LogMsg "Iperf server on Server1 is stopped in this state, hence connections should not be observed"
										LogMsg "Iperf server on Server2 is stopped in this state, hence connections should not be observed"
										$testResult= "FAIL"
									}
									else 
									{
										LogMsg "Iperf server on Server1 is stopped in this state, hence no connections Observed"
										LogMsg "Iperf server on Server2 is stopped in this state, hence no connections Observed"
										$testResult= "PASS"
#Get Number of connected streams for test step 1 between both Servers Stopped and started back
										$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Both Servers Stopped 1" -end "Both Servers Started 2" -str $connectStr1
										$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Both Servers Stopped 1" -end "Both Servers Started 2" -str $connectStr2
										If (($server1ConnCount -ne 0) -and ($server2ConnCount -ne 0))
										{
											LogMsg "Iperf server on Both Server are in stopped state, hence connections streams should not be observed"
											$testResult= "FAIL"
										}
										else 
										{
											LogMsg "Iperf server on Both Servers are in stopped state, hence no connection streams Observed"
											$testResult= "PASS"
#Verify CustomProbe Messages test step 1 between Server stopped on both Server1 and Server2 and started back again
											If (( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Both Servers Stopped 1" -end "Both Servers Started 2") -and ( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Both Servers Stopped 1" -end "Both Servers Started 2"))
											{
												LogMsg "Iperf server on Both Servers are in stopped state, CP and LB Port are different, hence no custom Probe should be observed on LB port"
												$testResult= "FAIL"
											}
											else 
											{
												LogMsg "Iperf server on Both Servers are in stopped state, CP and LB Port are different,hence no custom probe messages Observed on LB Port"
												$testResult= "PASS"
#Verify Connectivity on Both Servers after starting them again , server2 should be connected to all the streams from Client
#Start Test Analysis between both Servers started second time and Test Completed
												$isServerConnected1 = AnalyseIperfServerConnectivity -logFile $server1Log -beg "Both Servers Started 2" -end "TestComplete"
												$isServerConnected2 = AnalyseIperfServerConnectivity -logFile $server2Log -beg "Both Servers Started 2" -end "TestComplete"
												If (($isServerConnected1) -and ($isServerConnected2))
												{
													LogMSg "Both Servers are Connected to Client after starting Server1 and Server2 "
													$testResult = "PASS"		
													$connectStr1="$($server1.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
													$connectStr2="$($server2.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
#Get Number of connected streams for test step 1 between both Servers started second time and Test Completed
													$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Both Servers Started 2" -end "TestComplete" -str $connectStr1
													$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Both Servers Started 2" -end "TestComplete" -str $connectStr2
#Verify Custom Probe Messages on both server between both Servers started second time and Test Completed				
													If (!( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Both Servers Started 2" -end "TestComplete") -and !(IsCustomProbeMsgsPresent -logFile $server2Log -beg "Both Servers Started 2" -end "TestComplete")) 
													{
														LogMsg "No CustomProbe Messages Observed on both Server on LB Port after Starting both Server,CP and LB Port are different, hence no custom Probe should be observed on LB port"
														$testResult = "PASS"
														LogMsg "Server1 Parallel Connection Count after Starting back Server1 is $server1ConnCount"
														LogMsg "Server2 Parallel Connection Count after Starting back Server2 is $server2ConnCount"
														$diff = [Math]::Abs($server1ConnCount - $server2ConnCount)
														If ((($diff/$Value)*100) -lt 20)
														{
															$testResult = "PASS"
															LogMsg "Connection Counts are distributed evenly in both Servers after Starting back Server1"
															LogMsg "Diff between server1 and server2 Connection Counts is $diff after Starting back Server1"
#Analysis Total DataTransfer on both server and Client
															$server1Dt= GetTotalDataTransfer -logFile $server1Log -beg "Test Started" -end "TestComplete"
															LogMsg "Server1 Total Data Transfer is $server1Dt"
															$server2Dt= GetTotalDataTransfer -logFile $server2Log -beg "Test Started" -end "TestComplete"
															LogMsg "Server2 Total Data Transfer is $server2Dt"
															$clientDt= GetTotalDataTransfer -logFile $clientLog -beg "Test Started" -end "AllTestComplete"

															LogMsg "Client Total Data Transfer is $clientDt"
															$totalServerDt = ([int]($server1Dt.Split("K")[0]) + [int]($server2Dt.Split("K")[0]))
															LogMsg "All Servers Total Data Transfer is $totalServerDt"
															If (([int]($clientDt.Split("K")[0])) -eq [int]($totalServerDt))
															{
																$testResult = "PASS"
																LogMsg "Total DataTransfer is equal on both Server and Client"
#Analyse CustomProbe on Other CP Port
																RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-probe.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
																RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-probe.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
																$server1CpLog= $server1.LogDir + "\iperf-probe.txt"
																$server2CpLog= $server2.LogDir + "\iperf-probe.txt"
#Analyse CustomProbe on Other CP Port between "test started" and "server 1 stopped 1"
																If ( (IsCustomProbeMsgsPresent -logFile $server1CpLog -beg "Test Started" -end "Both Servers Stopped 1") `
																		-and (IsCustomProbeMsgsPresent -logFile $server2CpLog -beg "Test Started" -end "Both Servers Stopped 1") `
																		-and ( IsCustomProbeMsgsPresent -logFile $server1CpLog -beg "Both Servers Started 2" -end "TestComplete") `
																		-and  ( IsCustomProbeMsgsPresent -logFile $server2CpLog -beg "Both Servers Started 2" -end "TestComplete") `
																   )
																{
																	$server1CpConnCountBeforeStop= GetCustomProbeMsgsCount -logFile $server1CpLog  -beg "Test Started" -end "Both Servers Stopped 1"
																	$server2CpConnCountBeforeStop= GetCustomProbeMsgsCount -logFile $server2CpLog  -beg "Test Started" -end "Both Servers Stopped 1"
																	$server1CpConnCountAfterStop= GetCustomProbeMsgsCount -logFile $server1CpLog  -beg "Both Servers Started 2" -end "TestComplete"
																	$server2CpConnCountAfterStop= GetCustomProbeMsgsCount -logFile $server2CpLog -beg "Both Servers Started 2" -end "TestComplete"

																	$lap = ($BothServersStopped_1 - $BothServersStarted_1)
																	$cpFrequency=$lap/$server1CpConnCountBeforeStop
																	LogMsg "$server1CpConnCountBeforeStop Custom Probe Messages in $lap seconds observed on Server1 before stopping Server1.Frequency=$cpFrequency"
																	$cpFrequency=$lap/$server2CpConnCountBeforeStop
																	LogMsg "$server2CpConnCountBeforeStop Custom Probe Messages in $lap seconds observed on Server2 before stopping back Server1.Frequency=$cpFrequency"

																	$lap = ($BothServersStopped_1 - $BothServersStarted_1)
																	$cpFrequency=$lap/$server1CpConnCountAfterStop
																	LogMsg "$server1CpConnCountAfterStop Custom Probe Messages in $lap seconds observed on Server1 after Starting back Server1.Frequency=$cpFrequency"
																	$cpFrequency=$lap/$server2CpConnCount
																	LogMsg "$server2CpConnCountAfterStop Custom Probe Messages in $lap seconds observed on Server2 after Starting back Server1.Frequency=$cpFrequency"

																	$testResult = "PASS"
																}	
																else 
																{
																	if (!( IsCustomProbeMsgsPresent -logFile $server1CpLog) ) 
																	{
																		LogErr "NO Custom Probe Messages observed on Server1 on CP Port"
																		$testResult = "FAIL"
																	}
																	if (!(IsCustomProbeMsgsPresent -logFile $server2CpLog))
																	{
																		LogErr "NO Custom Probe Messages observed on Server2  on CP Port"
																		$testResult = "FAIL"
																	} 
																}
#Analysis CustomProbe on Other CP Port Finished
															}
															else 
															{
																$testResult = "FAIL"
																LogErr "Total DataTransfer is NOT equal on both Server and Client"
															}
														}
														else 
														{
															$testResult = "FAIL"
															LogErr "Connection Counts are not distributed correctly after Starting back Server1"
															LogErr "Diff between server1 and server2 is $diff after Starting back Server1"
														}
													}
													else 
													{
														if (( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Both Servers Started 2" -end "TestComplete") ) 
														{
															$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1Log -beg "Both Servers Started 2" -end "TestComplete"
															LogErr "$server1CpConnCount Custom Probe Messages observed on Server1 after Starting back Server1"
															$testResult = "FAIL"
														}
														if ((IsCustomProbeMsgsPresent -logFile $server2Log -beg "Both Servers Started 2" -end "TestComplete"))
														{
															$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Both Servers Started 2" -end "TestComplete"
															LogErr "$server2CpConnCount Custom Probe Messages observed on Server2 after Starting back Server2"
															$testResult = "FAIL"
														} 
													}
#Test Analysis Finished
												}
												else
												{
													$testResult = "FAIL"
													LogErr "Server is not Connected to Client after Starting both Server1 and Server2 again"
												}
											}
										}

									}
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
								if (( IsCustomProbeMsgsPresent -logFile $server1CpLog -beg "Test Started" -end "Both Servers Stopped 1") )
								{
									$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1Log -beg "Test Started" -end "Both Servers Stopped 1"
									LogErr "$server1CpConnCount Custom Probe Messages observed on Server1 before both Servers are stopped"
									$testResult = "FAIL"
								}
								if (!(IsCustomProbeMsgsPresent -logFile $server2CpLog -beg "Test Started" -end "Both Servers Stopped 1")) {
									$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Test Started" -end "Both Servers Stopped 1"
									LogErr "$server2CpConnCount Custom Probe Messages observed on Server2 before both Servers are stopped"
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
						LogErr "Client is not Connected to Server"
					}
#endregion		
				} 
				else 
				{
					LogErr "Failured detected in client connection at the start of test"
					RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
					LogMsg "Test Finished..!"
					$testResult = "FAIL"
				}

			} 
			else	
			{
				LogErr "Unable to start iperf-server. Aborting test."
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
