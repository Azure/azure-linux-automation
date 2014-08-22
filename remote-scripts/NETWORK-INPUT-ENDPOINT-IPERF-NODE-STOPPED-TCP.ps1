<#-------------Create Deployment Start------------------#>
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

	$hs1vm1 = $testVMsinService
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint

	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")

	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$dtapServerTcpport = "750"
	$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
	$dtapServerUdpport = "990"
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
	$dtapServerSshport = "22"

	$server = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport  -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport  -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

	foreach ($mode in $currentTestData.TestMode.Split(","))
	{
        $testResult = ""
		try
		{
			mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null

			$server.cmd ="./start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"

			if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
			{
				$client.cmd ="./start-client.py -c $hs1VIP -p $hs1vm1tcpport -t10"
			}

			if(($mode -eq "URL") -or ($mode -eq "Hostname"))
			{
				$client.cmd ="./start-client.py -c $hs1ServiceUrl -p $hs1vm1tcpport -t10"
			}
			$server.logDir = "$LogDir\$mode"
			$client.logDir = "$LogDir\$mode"

			RemoteCopy -uploadTo $server.ip -port $server.sshPort -files $server.files -username $server.user -password $server.password -upload
			RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload

			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *.py && rm -rf *.txt *.log" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "chmod +x *.py && rm -rf *.txt *.log" -runAsSudo

			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo TestStarted > iperf-client.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "echo TestStarted > iperf-server.txt" -runAsSudo

			$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo ClientStarted1 >> iperf-client.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "echo ServerStarted1 >> iperf-server.txt" -runAsSudo

			StartIperfServer $server
			$isServerStarted = IsIperfServerStarted $server 
			if($isServerStarted -eq $true)
			{
				LogMsg "iperf Server started successfully. Listening TCP port $($client.tcpPort) ..."
#>>>On confirmation, of server starting, let's start iperf client...
				StartIperfClient $client
                $suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo ClientStopped1 >> iperf-client.txt" -runAsSudo
				$isClientStarted = IsIperfClientStarted $client -beginningText ClientStarted1 -endText ClientStopped1

				if($isClientStarted -eq $true)
				{
					$serverState = IsIperfServerRunning $server
                   
					if($serverState -eq $true)
					{
						LogMsg "Stopping Server.."
						$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "./stop-server.py" -runAsSudo
						$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "echo ServerStopped1 >> iperf-server.txt" -runAsSudo
						LogMsg "Stopping Client.."
						$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "./stop-client.py" -runAsSudo
						

#Step 2. Do not start iperf server and start the client..
						LogMsg "Starting the client without starting the server.."
						$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo ClientStarted2 >> iperf-client.txt" -runAsSudo

						StartIperfClient $client
						$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "./stop-client.py" -runAsSudo
						$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo ClientStopped2 >> iperf-client.txt" -runAsSudo
						$isClientStarted = IsIperfClientStarted $client -beginningText ClientStarted2 -endText ClientStopped2
                        Write-Host "isClientConnected : $isClientStarted"
						if($isClientStarted -eq $false)
						{
							LogMsg "Client Not connected to server."
							LogMsg "Starting the Server again.."
                            
							$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "echo ServerStarted3 >> iperf-server.txt" -runAsSudo
							StartIperfServer $server
							$isServerStarted = IsIperfServerStarted $server
							if($isServerStarted -eq $true)
							{
								LogMsg "iperf Server started successfully. Listening TCP port $($client.tcpPort) ..."
#>>>On confirmation, of server starting, let's start iperf client...
								$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo ClientStarted3 >> iperf-client.txt" -runAsSudo
								StartIperfClient $client
                                $suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo ClientStopped3 >> iperf-client.txt" -runAsSudo
								$isClientStarted = IsIperfClientStarted $client -beginningText ClientStarted3 -endText ClientStopped3
								if($isClientStarted -eq $true)
								{
									$serverState = IsIperfServerRunning $server
									$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "./stop-server.py" -runAsSudo
									$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "echo ServerStopped3 >> iperf-server.txt" -runAsSudo

									if($serverState -eq $true)
									{
										LogMsg "Server was successfully connected to client.."
										$suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "echo TestCompleted >> iperf-client.txt" -runAsSudo
										$suppressedOut = $suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "echo TestCompleted >> iperf-server.txt" -runAsSudo

										$testResult = "PASS"
#GetStringMatchObject -logFile "$($client.Logdir)\iperf-client"
									}
									else
									{
										LogMsg "Failures Detected in on Server."
										$testResult = "FAIL"
									}
								}
								else
								{
									LogMsg "Client failed to connect.."
									$testResult = "FAIL"
								}
							}
							else
							{
								LogMsg "Server Failed to start."
								$testResult = "FAIL"
							}

						}
						else
						{
							LogMsg "Client connected to server without starting the server."
							$testResult = "FAIL"
						}
					}
					else
					{
						LogMsg "Test Finished..!"
						$testResult = "FAIL"
					}
				}
				else
				{
					LogMsg "Failured detected in client connection."
					LogMsg "Test Finished..!"
					$testResult = "FAIL"
				}
			}
			else
			{
				LogMsg "Unable to start iperf-server. Aborting test."
				$testResult = "Aborted"
			}

		}
		catch
		{
			$ErrorMessage =  $_.Exception.Message
			LogMsg "EXCEPTION : $ErrorMessage"   
		}
		Finally
		{
			$metaData = $mode 
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
