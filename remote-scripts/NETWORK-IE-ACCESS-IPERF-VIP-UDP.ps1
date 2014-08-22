
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig

LogMsg "Skipping Deployment..."

if ($isDeployed -eq "False")
{
	exit
}

<#-------------End ------------------#>

##################################################################
##################################################################
##################################################################
##################################################################
##################################################################

<#-------------Get VMs and details ------------------#>

$hs1Name = Get-Content .\temp\DeployedServicesFile.txt
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
try
{


	RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
	RemoteCopy -uploadTo $hs1VIP -port $hs1vm2sshport -files $currentTestData.files -username $user -password $password -upload
	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "chmod +x *" -runAsSudo
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

	LogMsg "Startin iperf Server..."
	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "./start-server.py -i1 -p $hs1vm2udpport -u yes && mv Runtime.log start-server.py.log" -runAsSudo
	RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/start-server.py.log" -downloadTo $LogDir -port $hs1vm2sshport -username $user -password $password
#Get-Content $LogDir\start-server.py.log | Set-Content $($currentTestData.testName).log -PassThru
#>>>Verify, if server started...
	LogMsg "Verifying if server is started or not.."
	RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/isServerStarted.txt" -downloadTo .\temp -port $hs1vm2sshport -username $user -password $password
	$isServerStarted = Get-Content .\temp\isServerStarted.txt

	if($isServerStarted -eq "yes")
	{
		LogMsg "iperf Server started successfully. Listening TCP port $hs1vm2tcpport..."
#>>>On confirmation, of server starting, let's start iperf client...
		LogMsg "Startin iperf client and trying to connect to port $hs1vm2tcpport..."
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./start-client.py -c $($hs1vm2.IpAddress) -i1 -p $hs1vm2udpport -t10 -u yes" -runAsSudo
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log start-client.py.log" -runAsSudo
		RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/start-client.py.log, /home/$user/iperf-client.txt" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
#Get-Content $LogDir\start-client.py.log | Set-Content $($currentTestData.testName).log -PassThru

#>>>Verify client...
		RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo .\temp -port $hs1vm1sshport -username $user -password $password
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -rf /home/$user/state.txt /home/$user/Summary.log" -runAsSudo
		$clientState = Get-Content .\temp\state.txt
		$clientSummary = Get-Content .\temp\Summary.log

#>>>Remove Temporary files..
		Remove-Item .\temp\state.txt -Force
		Remove-Item .\temp\Summary.log -Force

		if($clientState -eq "TestCompleted" -and $clientSummary -eq "PASS")
		{

#>>>Now we know that our client was connected. Let's go and check the server now...
			RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "./check-server.py && mv Runtime.log check-server.py.log" -runAsSudo
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/check-server.py.log, /home/$user/iperf-server.txt" -downloadTo $LogDir -port $hs1vm2sshport -username $user -password $password
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo .\temp -port $hs1vm2sshport -username $user -password $password
			$serverState = Get-Content .\temp\state.txt
			$serverSummary =  Get-Content .\temp\Summary.log

#>>>Remove Temporary files..
			Remove-Item .\temp\state.txt -Force
			Remove-Item .\temp\Summary.log -Force
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
	}

	else
	{
		LogMsg "Unable to start iperf-server. Aborting test."
		$testResult = "Aborted"
	}

	<#----------------End-------------------------#>

##################################################################
##################################################################
##################################################################
##################################################################
##################################################################

	<#--------------Test Clean up-----------------#>
	if($testResult -eq "PASS")
	{
#Remove the deployments...
		LogMsg "Skipping Cleanup..."
		Return $testResult
	}
	else
	{
#preserve the deployments...
		Return $testResult
# while preserving the setup, we can add all the test case information in the Deployment Description. Not yet tried. But it's possible!
	}

}

Catch 
{
	$ErrorMessage =  $_.Exception.Message
	LogMsg "EXCEPTION : $ErrorMessage"
}

