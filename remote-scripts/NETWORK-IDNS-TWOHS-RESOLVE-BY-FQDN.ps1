Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
	$hs1VIP = $allVMData[0].PublicIP
	$hs1ServiceUrl = $allVMData[0].URL
	$hs1vm1IP = $allVMData[0].InternalIP
	$hs1vm1Hostname = $allVMData[0].RoleName
	$hs1vm1sshport = $allVMData[0].SSHPort
	$hs1vm1tcpport = $allVMData[0].TCPtestPort
	$hs1vm1udpport = $allVMData[0].UDPtestPort

	$hs2VIP = $allVMData[1].PublicIP
	$hs2ServiceUrl = $allVMData[1].URL
	$hs2vm1IP = $allVMData[1].InternalIP
	$hs2vm1Hostname = $allVMData[1].RoleName
	$hs2vm1sshport = $allVMData[1].SSHPort
	$hs2vm1tcpport = $allVMData[1].TCPtestPort
	$hs2vm1udpport = $allVMData[1].UDPtestPort	

	$vm1 = CreateIdnsNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -logDir $LogDir -nodeDip $hs1vm1IP -nodeUrl $hs1ServiceUrl -nodeDefaultHostname $hs1vm1Hostname
	$vm2 = CreateIdnsNode -nodeIp $hs2VIP -nodeSshPort $hs2vm1sshport -user $user -password $password -logDir $LogDir -nodeDip $hs2vm1IP -nodeUrl $hs2ServiceUrl -nodeDefaultHostname $hs2vm1Hostname

	try
	{
		RemoteCopy -upload -uploadTo $vm1.ip -port $vm1.SShport -username $vm1.user -password $vm1.password -files $currentTestData.files
		RemoteCopy -upload -uploadTo $vm2.ip -port $vm2.SShport -username $vm2.user -password $vm2.password -files $currentTestData.files
		$suppressedOut = RunLinuxCmd -username $vm1.user -password $vm1.password -ip $vm1.Ip -port $vm1.SshPort -command "chmod +x *" -runAsSudo
		if(!$vm1.fqdn -and !$vm2.fqdn)
		{
			$vm1.fqdn =  RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "hostname --fqdn" -runAsSudo
			$vm2.fqdn =  RunLinuxCmd -username $user -password $password -ip $hs2VIP -port $hs2vm1sshport -command "hostname --fqdn" -runAsSudo
		}

		$vm1.hostname = $vm1.fqdn
		$vm2.hostname = $vm2.fqdn

		#Start the NSLOOKup test..
		$nslookupResult = DoNslookupTest -vm1 $vm1 -vm2 $vm2
		#Start Dig test..
		$digResult = DoDigTest -vm1 $vm1 -vm2 $vm2

		LogMsg "NSLOOKUP : $nslookupResult. DIG : $digResult"

		if(($nslookupResult -imatch "FAIL") -and ($digResult -imatch "FAIL"))
		{
			$testResult = "PASS"
			LogMsg "NSLOOKUP : FAIL. DIG : FAIL. Expected behavior."
		}
		else
		{
			$testResult = "FAIL"
			if($nslookupResult -imatch "PASS")
			{
				LogErr "NSLOOKUP resolved VM DIP using VM fqdn. This is unexpected behaviour."
			}
			if($digResult -imatch "PASS")
			{
				LogErr "DIG resolved VM DIP using VM fqdn. This is unexpected behaviour."
			}
			LogMsg "Test Result : FAIL"

		}
		LogMsg "$($currentTestData.testName) : $testResult"
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = ""
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
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed
#Return the result and summery to the test suite script..
return $result
#$resultSummary
