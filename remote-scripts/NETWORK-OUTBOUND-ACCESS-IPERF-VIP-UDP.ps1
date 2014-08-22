<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$testResult = ""
$result = ""
$resultArr = @()


	<#-------------Create Deployment Start------------------#>

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{

		<#-------------Get VMs and details ------------------#>

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
		$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
		$hs1vm2udpport = GetPort -Endpoints $hs1vm2Endpoints -usage udp
		$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
		$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh


		<#------------End-----------------------#>

##################################################################
##################################################################
##################################################################
##################################################################
##################################################################

		<#------------PUSH all files in all VMs-----------------#>

		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		RemoteCopy -uploadTo $hs1VIP -port $hs1vm2sshport -files $currentTestData.files -username $user -password $password -upload

		<#------------End-----------------#>

##################################################################
##################################################################
##################################################################
##################################################################
##################################################################

		<#---------------------start the test now-------------------#>

# Roles :
# #      iperf server : VM1
# #      Details - VIP : $hs1VIP, sshport : $hs1vm1sshport, tcp port : $hs1vm1tcpport
#
# #      iperf client : VM2
# #      Details - VIP : $hs1VIP, sshport : $hs1vm2sshport, tcp port : $hs1vm2tcpport

#>>>Start server...
		$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./start-server.py -i1 -p $hs1vm1udpport -u yes" -runAsSudo

#>>>Verify, if server started...
		RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/isServerStarted.txt" -downloadTo .\temp -port $hs1vm1sshport -username $user -password $password
		$isServerStarted = Get-Content .\temp\isServerStarted.txt

		if($isServerStarted -eq "yes")
		{

#>>>On confirmation, of server starting, let's start iperf client...
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "./start-client.py -c $($hs1vm1.IpAddress) -i1 -p $hs1vm1udpport -t10 -u yes" -runAsSudo

#>>>Verify client...
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo .\temp -port $hs1vm2sshport -username $user -password $password
			$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "rm -rf /home/$user/state.txt /home/$user/Summary.log" -runAsSudo
			$clientState = Get-Content .\temp\state.txt
			$clientSummary = Get-Content .\temp\Summary.log

#>>>Remove Temporary files..
			Remove-Item .\temp\state.txt -Force
			Remove-Item .\temp\Summary.log -Force

			if($clientState -eq "TestCompleted" -and $clientSummary -eq "PASS")
			{

#>>>Now we know that our client was connected. Let's go and check the server now...
				$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./check-server.py" -runAsSudo
				RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo .\temp -port $hs1vm1sshport -username $user -password $password
				$serverState = Get-Content .\temp\state.txt
				$serverSummary =  Get-Content .\temp\Summary.log

#>>>Remove Temporary files..
				Remove-Item .\temp\state.txt -Force
				Remove-Item .\temp\Summary.log -Force
#>>>Verify client connections appeared on server...
				if($serverState -eq "TestCompleted" -and $serverSummary -eq "PASS")
				{
					Write-Host "Test Finished..!"
					$testStatus = "PASS"
				}
				else
				{
					Write-Host "Test Finished..!"
					$testStatus = "FAIL"
				}


			}
			else
			{
				Write-Host "Failured detected in client connection."
				Write-Host "Test Finished..!"
				$testStatus = "FAIL"

			}
		}

		else
		{
			Write-Host "Unable to start iperf-server. Aborting test."
			$testStatus = "Aborted"
		}
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"
	}

	Finally
	{
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
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
return $result





