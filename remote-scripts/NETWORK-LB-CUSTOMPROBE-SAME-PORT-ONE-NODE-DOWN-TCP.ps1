Import-Module .\TestLibs\RDFELibs.psm1 -Force

$result = ""
$testResult = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
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

	$hs1vm2 = $testVMsinService[1]
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
	$wait=45
	$cmd1="./start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"
	$cmd2="./start-server.py -p $hs1vm2tcpport && mv Runtime.log start-server.py.log -f"
	$cmd3="./start-client.py -c $hs1VIP -p $hs1vm1tcpport -t20 -P$Value"
	$Value = 2
	$server1 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm1.IpAddress
	$server2 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeTcpPort $hs1vm2tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodeDip $hs1vm2.IpAddress
	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd3 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$resultArr = @()
	$result = "", ""
	foreach ($mode in $currentTestData.TestMode.Split(",")) 
	{
		try
		{
			LogMsg "Test Started in $mode mode.."

			mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
			mkdir $LogDir\$mode\Server1 -ErrorAction SilentlyContinue | out-null
			mkdir $LogDir\$mode\Server2 -ErrorAction SilentlyContinue | out-null
			if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
			{#.........................................................................Client command will decided according to TestMode....
				$cmd3="./start-client.py -c $hs1VIP -p $hs1vm1tcpport -t10 -P2" 
			}
			if(($mode -eq "URL") -or ($mode -eq "Hostname"))
			{
				$cmd3="./start-client.py -c $hs1ServiceUrl -p $hs1vm1tcpport -t10 -P2"
			}
			$server1.logDir = $LogDir + "\$mode" + "\Server1"
			$server2.logDir = $LogDir + "\$mode" + "\Server2"
			$client.logDir = $LogDir + "\$mode"
			$client.cmd = $cmd3
			RemoteCopy -uploadTo $server1.ip -port $server1.sshPort -files $server1.files -username $server1.user -password $server1.password -upload
			RemoteCopy -uploadTo $server2.Ip -port $server2.sshPort -files $server2.files -username $server2.user -password $server2.password -upload
			RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload

			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "chmod +x *" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "chmod +x *" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "rm -rf *.txt *.log" -runAsSudo

			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Test Started > iperf-server.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo Test Started > iperf-server.txt" -runAsSudo

#Step 1.1: Start Iperf Server on both VMs
			$stopWatch = SetStopWatch
			$lapTestStarted = GetStopWatchElapasedTime $stopWatch "ss"
			StartIperfServer $server1
			StartIperfServer $server2

			$isServer1Started = IsIperfServerStarted $server1
			$isServer2Started = IsIperfServerStarted $server2
			LogMsg "Waiting for $wait sec to let both servers start"
			sleep ($wait)
			if(($isServer1Started -eq $true) -and ($isServer2Started -eq $true)) 
			{
				LogMsg "Iperf Server1 and Server2 started successfully. Listening TCP port $($client.tcpPort) ..."
#Step 1.2: Start Iperf Client on Listening VM
				$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshport -command "echo Test Started > iperf-client.txt" -runAsSudo
				StartIperfClient $client
				$isClientStarted = IsIperfClientStarted $client

				if($isClientStarted -eq $true)
				{
#Step 2: Stop Iperf client
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "./stop-client.py" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Stopped 1 >> iperf-client.txt" -runAsSudo

#Step3 : Stop Iperf Server on VM1
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "./stop-server.py" -runAsSudo
					$lapServer1Stopped1=GetStopWatchElapasedTime $stopWatch "ss"
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Server1 Stopped 1 >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "echo Server1 Stopped 1 >> iperf-server.txt" -runAsSudo

#Step4 : Wait for $wait sec and then Start Iperf Client Again
					WaitFor -seconds $wait
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Started 1 >> iperf-client.txt" -runAsSudo
					StartIperfClient $client

#Step5 :  Stop Iperf Client Again 
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "./stop-client.py" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Stopped 2 >> iperf-client.txt" -runAsSudo

#Step6 : Start Iperf Server on VM1 
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshport -command "echo Server1 Started 2 >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo Server1 Started 2 >> iperf-server.txt" -runAsSudo
					StartIperfServer $server1
					$lapServer1Started2=GetStopWatchElapasedTime $stopWatch "ss"					
#Step7 : Wait for $wait sec and then Start Iperf Client Again
					sleep ($wait)
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo Client Started 2 >> iperf-client.txt" -runAsSudo
					StartIperfClient $client
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
# Step8 : Finish Tests, Echoing Bookmarks for Parsing
					$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshport -command "echo TestComplete >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "echo TestComplete >> iperf-server.txt" -runAsSudo
					$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo AllTestComplete >> iperf-client.txt" -runAsSudo
					$lapTestCompleted=GetStopWatchElapasedTime $stopWatch "ss"
# Copy All Logs
					RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
					RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-server.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
					RemoteCopy -download -downloadFrom $client.ip -files "/home/$user/start-client.py.log, /home/$user/iperf-client.txt" -downloadTo $client.LogDir -port $client.sshPort -username $client.user -password $client.password

					$clientLog= $client.LogDir + "\iperf-client.txt"
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
						$isServerConnected1 = AnalyseIperfServerConnectivity -logFile $server1Log -beg "Test Started" -end "Server1 Stopped 1"
						$isServerConnected2 = AnalyseIperfServerConnectivity -logFile $server2Log -beg "Test Started" -end "Server1 Stopped 1"
						If (($isServerConnected1) -and ($isServerConnected2))
						{
							$testResult = "PASS"
							$connectStr1="$($server1.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
							$connectStr2="$($server2.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
#Get Number of connected streams for test step 1 between test started and Server1 stopped
							$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Test Started" -end "Server1 Stopped 1" -str $connectStr1
							$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Test Started" -end "Server1 Stopped 1" -str $connectStr2
#Verify Custom Probe Messages on both server

							If (( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Test Started" -end "Server1 Stopped 1") -and (IsCustomProbeMsgsPresent -logFile $server2Log -beg "Test Started" -end "Server1 Stopped 1")) 
							{
								$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1Log -beg "Test Started" -end "Server1 Stopped 1"
								$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Test Started" -end "Server1 Stopped 1"
								$lap=($lapServer1Stopped1 - $lapTestStarted)
								$cpFrequency=$lap/$server1CpConnCount
								LogMsg "$server1CpConnCount Custom Probe Messages in $lap seconds observed on Server1 before stopping Server1.Frequency=$cpFrequency"
								$cpFrequency=$lap/$server2CpConnCount
								LogMsg "$server2CpConnCount Custom Probe Messages in $lap seconds observed on Server2 before stopping Server1.Frequency=$cpFrequency"
								$testResult = "PASS"
								LogMsg "Server1 Parallel Connection Count before stopping Server1 is $server1ConnCount"
								LogMsg "Server2 Parallel Connection Count before stopping Server1 is $server2ConnCount"
								$diff = [Math]::Abs($server1ConnCount - $server2ConnCount)
								If ((($diff/$Value)*100) -lt 20)
								{
									$testResult = "PASS"
									LogMsg "Connection Counts are distributed evenly in both Servers before stopping Server1"
									LogMsg "Diff between server1 and server2 Connection Counts is $diff"
#Till Now verification of connectivity, Custom Probe and connection distribution is verified
#Start Verification of connectivity from Server1 is stopped and Server1 is started back again
									$isServerConnected1 = AnalyseIperfServerConnectivity -logFile $server1Log -beg "Server1 Stopped 1" -end "Server1 Started 2"
									If ($isServerConnected1 -eq $true) 
									{
										LogErr "Iperf server on Server1 is stopped in this state, hence connections should not be observed"
										$testResult= "FAIL"
									}
									else 
									{
										LogMsg "Iperf server on Server1 is stopped in this state, hence no connections Observed"
										$testResult= "PASS"
#Get Number of connected streams for test step 1 between test started and Server1 stopped
										$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Server1 Stopped 1" -end "Server1 Started 2" -str $connectStr1
										$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Server1 Stopped 1" -end "Server1 Started 2" -str $connectStr2
										If ($server1ConnCount -ne 0)
										{
											LogErr "Iperf server on Server1 is stopped in this state, hence connections should not be observed"
											$testResult= "FAIL"
										}
										else 
										{
											LogMsg "Iperf server on Server1 is stopped in this state, hence no connections streams Observed"
											$testResult= "PASS"
#Verify CustomProbe Messages test step 1 between Server1 stopped and Server Started on Server1
											If (( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Server1 Stopped 1" -end "Server1 Started 2")) 
											{
												LogErr "Iperf server on Server1 is stopped in this state, hence no custom Probe should be observed as CP and LB port are same"
												$testResult= "FAIL"
											}
											else 
											{
												LogMsg "Iperf server on Server1 is stopped in this state, hence no custom probe messages Observed"
												$testResult= "PASS"
#Verify Connectivity on Server2 , server2 should be connected to all the streams from Client between Server1 stopped and Server Started on Server1
												if ($server2ConnCount -ne $Value)
												{
													LogErr "Iperf Server on Server2 is running, and these connection streams are observed $server2ConnCount instead of $Value"
													$testResult= "FAIL"
												}
												else
												{
													LogMsg "Iperf Server on Server2 is running, and as expected $server2ConnCount connection streams are observed"
													$testResult = "PASS"
#Verify CustomProbe Messages on server2 between Server1 stopped and Server Started on Server1
													If (!( IsCustomProbeMsgsPresent -logFile $server2Log -beg "Server1 Stopped 1" -end "Server1 Started 2")) 
													{
														LogErr "No Custom Probe Messages observed on Server2 between Server1 stopped and Server1 started again"
														LogErr "Iperf server on Server2 is running,  custom Probe should be observed as CP and LB port are same"
														$testResult= "FAIL"
													}
													else 
													{
														$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Server1 Stopped 1" -end "Server1 Started 2"
														$lap = ($lapServer1Started2-$lapServer1Stopped1)
														$cpFrequency=$lap/$server2CpConnCount
														LogMsg "Iperf server on Server2 is running, $server2CpConnCount CustomProbe messages in $lap seconds observed. Frequency=$cpFrequency"
														$testResult= "PASS"
#Test Analysis for Server1 stopped and Server1 started again is completed
#Start Test Analysis between Server1 started second time and Test Completed <FINAL Analysis>
														$isServerConnected1 = AnalyseIperfServerConnectivity -logFile $server1Log -beg "Server1 Started 2" -end "TestComplete"
														$isServerConnected2 = AnalyseIperfServerConnectivity -logFile $server2Log -beg "Server1 Started 2" -end "TestComplete"
														If (($isServerConnected1) -and ($isServerConnected2))
														{
															$testResult = "PASS"

															$connectStr1="$($server1.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
															$connectStr2="$($server2.DIP)\sport\s\d*\sconnected with $($client.ip)\sport\s\d"
#Get Number of connected streams for test step 1 between test started and Server1 stopped
															$server1ConnCount = GetStringMatchCount -logFile $server1Log -beg "Server1 Started 2" -end "TestComplete" -str $connectStr1
															$server2ConnCount = GetStringMatchCount -logFile $server2Log -beg "Server1 Started 2" -end "TestComplete" -str $connectStr2
#Verify Custom Probe Messages on both server

															If (( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Server1 Started 2" -end "TestComplete") -and (IsCustomProbeMsgsPresent -logFile $server2Log -beg "Server1 Started 2" -end "TestComplete")) 
															{
																$server1CpConnCount= GetCustomProbeMsgsCount -logFile $server1Log -beg "Server1 Started 2" -end "TestComplete"
																$server2CpConnCount= GetCustomProbeMsgsCount -logFile $server2Log -beg "Server1 Started 2" -end "TestComplete"
																$lap = ($lapTestCompleted -$lapServer1Started2)
																$cpFrequency=$lap/$server1CpConnCount
																LogMsg "$server1CpConnCount Custom Probe Messages in $lap seconds observed on Server1 after Starting back Server1.Frequency=$cpFrequency"
																$cpFrequency=$lap/$server2CpConnCount
																LogMsg "$server2CpConnCount Custom Probe Messages in $lap seconds observed on Server2 after Starting back Server1.Frequency=$cpFrequency"
																$testResult = "PASS"
																LogMsg "Server1 Parallel Connection Count after Starting back Server1 is $server1ConnCount"
																LogMsg "Server2 Parallel Connection Count after Starting back Server1 is $server2ConnCount"
																$diff = [Math]::Abs($server1ConnCount - $server2ConnCount)
																If ((($diff/2)*100) -lt 20)
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
																	} else
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
																if (!( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Server1 Started 2" -end "TestComplete") ) 
																{
																	LogErr "NO Custom Probe Messages observed on Server1 after Starting back Server1"
																	$testResult = "FAIL"
																}
																if (!(IsCustomProbeMsgsPresent -logFile $server2Log -beg "Server1 Started 2" -end "TestComplete"))
																{
																	LogErr "NO Custom Probe Messages observed on Server2 after Starting back Server1"
																	$testResult = "FAIL"
																} 
															}
#Test Analysis Finished
														}
														else
														{
															$testResult = "FAIL"
															LogErr "Server is not Connected to Client after Starting Server1 again"
														}
													}
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
								if (!( IsCustomProbeMsgsPresent -logFile $server1Log -beg "Test Started" -end "TestComplete") )
								{
									LogErr "NO Custom Probe Messages observed on Server1"
									$testResult = "FAIL"
								}
								if (!(IsCustomProbeMsgsPresent -logFile $server2Log -beg "Test Started" -end "TestComplete")) 
								{
									LogErr "NO Custom Probe Messages observed on Server2"
									$testResult = "FAIL"
								} 
							}							
						}
						else
						{
							$testResult = "FAIL"
							LogErr "Server is not Connected to Client before Stopping Server1"
						}
					}
					else
					{
						$testResult = "FAIL"
						LogErr "Client is not Connected to Server"
					}

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
				LogErr "Unable to start iperf-server. Aborting test."
				RemoteCopy -download -downloadFrom $server1.ip -files "/home/$user/iperf-server.txt" -downloadTo $server1.LogDir -port $server1.sshPort -username $server1.user -password $server1.password
				RemoteCopy -download -downloadFrom $server2.ip -files "/home/$user/iperf-server.txt" -downloadTo $server2.LogDir -port $server2.sshPort -username $server2.user -password $server2.password
				$testResult = "Aborted"
			}
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
