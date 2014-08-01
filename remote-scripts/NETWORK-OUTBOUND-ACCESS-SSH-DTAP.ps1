Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
$sshpassword = $password.Replace("`"", "`'")
Write-Host $sshpassword
if ($isDeployed)
{
	try
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

#$hs1vm2 = $testVMsinService[1]
#$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
		$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
		$dtapServerTcpport = "750"
		$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
		$dtapServerUdpport = "990"
		$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
		$dtapServerSshport = "22"
#$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP

#Install Paramiko package
		LogMsg "Installing Paramiko packege.."
		RemoteCopy -upload -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password
		$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "rm -rf *.log" -runAsSudo
		$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "chmod +x *.py" -runAsSudo
#$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "echo InstallStarted > Runtime.log" -runAsSudo
		$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "./installParamiko.py" -runAsSudo
#$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "echo InstallFinished >> Runtime.log"
		$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "mv Runtime.log installParamiko.log -f" -runAsSudo
		RemoteCopy -download -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "/home/$user/installParamiko.log" -downloadTo $LogDir
		$isParamiko = GetStringMatchCount -logFile "$LogDir\installParamiko.log" -str "running install_egg_info"
#$isParamiko = 1
		if ($isParamiko -gt 1)
		{
			LogMsg "Paramiko module installed successfully."
#$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "echo TestStarted > ssh.log" -runAsSudo

			LogMsg "Executing ./ssh.py -s $dtapServerIp -u $user -p $sshpassword -P $dtapServerSshport -c ifconfig"
			$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "./sshTest.py -s $dtapServerIp -u $user -p $sshpassword -P $dtapServerSshport -c hostname" -runAsSudo
			$suppressedOut = RunLinuxCmd -ip $hs1VIP -port $hs1vm1sshport -username $user -password $password -command "mv Runtime.log sshTest.log -f"

			RemoteCopy -download -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "/home/$user/sshTest.log" -downloadTo $LogDir
			$isSShSuccess = GetStringMatchCount -logFile "$LogDir\sshTest.log" -str "ubuntu"
			if($isSShSuccess -eq 1)
			{
				LogMsg "SSH Successful"
				$testResult = "Pass"
			}
			else
			{
				LogMsg "SSH FAILED."
				$testResult = "FAIL"
			}

		} 
		else
		{
			LogMsg "Paramiko installation failed."
			$testResult = "Aborted"
		}
	}
	catch{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"
	}

	Finally{

		if (!$testResult){
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
