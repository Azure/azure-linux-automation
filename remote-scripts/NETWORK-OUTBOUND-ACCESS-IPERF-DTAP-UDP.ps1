<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$testResult = ""
$result = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
    #Get deployment information
	$hs1Name = $isDeployed
	$testServiceData = Get-AzureService -ServiceName $hs1Name
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

	RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
	RemoteCopy -uploadTo $dtapServerIp -port $dtapServerSshport -files $currentTestData.files -username $user -password $password -upload
	$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo
	$suppressedOut = RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo
	try
	{
        #Start server...
		LogMsg "Startin iperf Server...on $dtapServerIp"
		$suppressedOut = RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "./start-server.py -i1 -p $dtapServerUDPport -u yes && mv Runtime.log start-server.py.log -f" -runAsSudo
		RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/start-server.py.log" -downloadTo $LogDir -port $dtapServerSshport -username $user -password $password
        #Verify, if server started...
		LogMsg "Verifying if server is started or not.."
		RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/isServerStarted.txt" -downloadTo $LogDir -port $dtapServerSshport -username $user -password $password
		$isServerStarted = Get-Content $LogDir\isServerStarted.txt
		if($isServerStarted -eq "yes")
		{
			LogMsg "iperf Server started successfully. Listening TCP port $hs1vm1tcpport..."
            #On confirmation, of server starting, let's start iperf client...
			LogMsg "Startin iperf client and trying to connect to port $dtapServerTcpport..."
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./start-client.py -c $dtapServerIp -i1 -p $dtapServerUDPport -t20 -u yes" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log start-client.py.log -f" -runAsSudo
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/start-client.py.log, /home/$user/iperf-client.txt" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -rf /home/$user/state.txt /home/$user/Summary.log" -runAsSudo
			$clientState = Get-Content $LogDir\state.txt
			$clientSummary = Get-Content $LogDir\Summary.log
			Remove-Item $LogDir\state.txt -Force
			Remove-Item $LogDir\Summary.log -Force

			if($clientState -eq "TestCompleted" -and $clientSummary -eq "PASS")
			{
                #Now we know that our client was connected. Let's go and check the server now...
				$suppressedOut = RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "./check-server.py && mv Runtime.log check-server.py.log -f" -runAsSudo
				RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/check-server.py.log, /home/$user/iperf-server.txt" -downloadTo $LogDir -port $dtapServerSshport -username $user -password $password
				RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo $LogDir -port $dtapServerSshport -username $user -password $password
				$serverState = Get-Content $LogDir\state.txt
				$serverSummary =  Get-Content $LogDir\Summary.log
				Remove-Item $LogDir\state.txt -Force
				Remove-Item $LogDir\Summary.log -Force
                #Verify client connections appeared on server...
				if($serverState -eq "TestCompleted" -and $serverSummary -eq "PASS")
				{
					$testResult = "PASS"
				}
				else
				{
					$testResult = "FAIL"
				}
                LogMsg "Test Finished..!"
                LogMsg "Test Result : $testResult"
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
		$metaData = "IP"
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
		$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
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