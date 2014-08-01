<#-------------Create Deployment Start------------------#>

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if (!$isDeployed)
{
	exit
}

<#-------------End ------------------#>

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

#$hs1vm2 = $testVMsinService[1]
#$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
$dtapServerTcpport = "750"
$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
$dtapServerUdpport = "990"
$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
$dtapServerSshport = "22"
$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP

<#------------End-----------------------#>

<#------------PUSH all files in all VMs-----------------#>
try
{

	RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
	RemoteCopy -uploadTo $dtapServerIp -port $dtapServerSshport -files $currentTestData.files -username $user -password $password -upload
	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
	RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "chmod +x *" -runAsSudo
	<#------------End-----------------#>

	<#---------------------start the test now-------------------#>

# Roles :
# #      iperf server : Dtap Server
# #      Details - IP : $dtapServerIP, sshport : $dtapServerSshport, tcp port : $dtapServerTcpport
#
# #      iperf client : VM1
# #      Details - VIP : $hs1VIP, sshport : $hs1vm1sshport, tcp port : $hs1vm1tcpport

#>>>Start server...

	LogMsg "Startin iperf Server...on $dtapServerIp"
	RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "./start-server.py -i1 -p $dtapServerTcpport && mv Runtime.log start-server.py.log -f" -runAsSudo
	RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/start-server.py.log" -downloadTo $LogDir -port $dtapServerSshport -username $user -password $password
#Get-Content $LogDir\start-server.py.log | Set-Content $($currentTestData.testName).log -PassThru
#>>>Verify, if server started...
	LogMsg "Verifying if server is started or not.."
	RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/isServerStarted.txt" -downloadTo .\temp -port $dtapServerSshport -username $user -password $password
	$isServerStarted = Get-Content .\temp\isServerStarted.txt

	if($isServerStarted -eq "yes")
	{
		LogMsg "iperf Server started successfully. Listening TCP port $hs1vm1tcpport..."
#>>>On confirmation, of server starting, let's start iperf client...
		LogMsg "Startin iperf client and trying to connect to port $dtapServerTcpport..."
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./start-client.py -c $dtapServerIp -i1 -p $dtapServerTcpport -t20" -runAsSudo
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log start-client.py.log -f" -runAsSudo
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
			RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "./check-server.py && mv Runtime.log check-server.py.log -f" -runAsSudo
			RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/check-server.py.log, /home/$user/iperf-server.txt" -downloadTo $LogDir -port $dtapServerSshport -username $user -password $password
			RemoteCopy -download -downloadFrom $dtapServerIp -files "/home/$user/state.txt, /home/$user/Summary.log" -downloadTo .\temp -port $dtapServerSshport -username $user -password $password
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

