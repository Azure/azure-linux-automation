


<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$resultArr = @()
$testResult = ""
$result = ""
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
#$isDeployed = "ICA-IEndpointSingleHS-Ubuntu1204W205-6-7-16-23-16"
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
	$hs1vm1IP = $hs1vm1.IpAddress
	$hs1vm1Hostname = $hs1vm1.InstanceName

	$hs1vm2 = $testVMsinService[1]
	$hs1vm2IP = $hs1vm2.IpAddress
	$hs1vm2Hostname = $hs1vm2.InstanceName

	$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
	$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
	$hs1vm2udpport = GetPort -Endpoints $hs1vm2Endpoints -usage udp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
	$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh

	<#------------PUSH all files in all VMs-----------------#>
	foreach ($mode in $currentTestData.TestMode.Split(","))
	{ 

		try
		{
			RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
			RemoteCopy -uploadTo $hs1VIP -port $hs1vm2sshport -files $currentTestData.files -username $user -password $password -upload
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "chmod +x * && rm -rf *.log *.txt*" -runAsSudo
#>>>Start server...
			LogMsg "Starting the test in $mode mode.."
			mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
			LogMsg "Starting iperf Server..."
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./start-server.py -i1 -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f" -runAsSudo
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/start-server.py.log" -downloadTo $LogDir\$mode  -port $hs1vm1sshport -username $user -password $password
#Get-Content $LogDir\start-server.py.log | Set-Content $($currentTestData.testName).log -PassThru
#>>>Verify, if server started...
			LogMsg "Verifying if server is started or not.."
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/isServerStarted.txt" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
			$isServerStarted = Get-Content $LogDir\isServerStarted.txt

			if($isServerStarted -eq "yes")
			{
				LogMsg "iperf Server started successfully. Listening TCP port $hs1vm1tcpport..."
#>>>On confirmation, of server starting, let's start iperf client...
				LogMsg "Startin iperf client and trying to connect to port $hs1vm1tcpport..."
				if(($mode -eq "IP") -or ($mode -eq "VIP")){
					$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "./start-client.py -c $hs1vm1IP -i1 -p $hs1vm1tcpport -t10" -runAsSudo
				}
				if(($mode -eq "URL") -or ($mode -eq "Hostname")){
					$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "./start-client.py -c $hs1vm1Hostname -i1 -p $hs1vm1tcpport -t10" -runAsSudo
				}
				$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "mv Runtime.log start-client.py.log -f" -runAsSudo
				RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/start-client.py.log, /home/$user/iperf-client.txt" -downloadTo $LogDir\$mode  -port $hs1vm2sshport -username $user -password $password
#Get-Content $LogDir\start-client.py.log | Set-Content $($currentTestData.testName).log -PassThru

#>>>Verify client...
				RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo $LogDir -port $hs1vm2sshport -username $user -password $password
				$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "rm -rf /home/$user/state.txt /home/$user/Summary.log" -runAsSudo
				$clientState = Get-Content $LogDir\state.txt
				$clientSummary = Get-Content $LogDir\Summary.log

#>>>Remove Temporary files..
				Remove-Item $LogDir\state.txt -Force
				Remove-Item $LogDir\Summary.log -Force

				if($clientState -eq "TestCompleted" -and $clientSummary -eq "PASS")
				{

#>>>Now we know that our client was connected. Let's go and check the server now...
					$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./check-server.py && mv Runtime.log check-server.py.log -f" -runAsSudo
					RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/check-server.py.log, /home/$user/iperf-server.txt" -downloadTo $LogDir\$mode  -port $hs1vm1sshport -username $user -password $password
					RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
					$serverState = Get-Content $LogDir\state.txt
					$serverSummary =  Get-Content $LogDir\Summary.log

#>>>Remove Temporary files..
					Remove-Item $LogDir\state.txt -Force
					Remove-Item $LogDir\Summary.log -Force
#>>>Verify client connections appeared on server...
					if($serverState -eq "TestCompleted" -and $serverSummary -eq "PASS")
					{
						LogMsg "Test Finished..!"
						$testResult = "PASS"
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
                LogMsg "$mode : $testResult"
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
