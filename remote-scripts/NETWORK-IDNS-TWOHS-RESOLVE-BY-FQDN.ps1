<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
#$isDeployed = "ICA-IEndpointTwoHS-SLES12B9-7-10-9-49-41^ICA-IEndpointTwoHS-SLES12B9-7-10-9-51-15"
if($isDeployed)
{
	$hsNames = $isDeployed
	$hsNames = $hsNames.Split("^")
	$hs1Name = $hsNames[0]
	$hs2Name = $hsNames[1]

	$testService1Data = Get-AzureService -ServiceName $hs1Name
	$testService2Data =  Get-AzureService -ServiceName $hs2Name
    #Get VMs deployed in the service..
	$hs1vm1 = $testService1Data | Get-AzureVM
	$hs2vm1 = $testService2Data | Get-AzureVM
	$hs1vm1IP = $hs1vm1.IPaddress
	$hs2vm1IP = $hs2vm1.IPaddress
	$hs1vm1Hostname = $hs1vm1.InstanceName
	$hs2vm1Hostname = $hs2vm1.InstanceName
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
	$hs2vm1Endpoints = $hs2vm1 | Get-AzureEndpoint

	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs2VIP = $hs2vm1Endpoints[0].Vip

	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")

	$hs2ServiceUrl = $hs2vm1.DNSName
	$hs2ServiceUrl = $hs2ServiceUrl.Replace("http://","")
	$hs2ServiceUrl = $hs2ServiceUrl.Replace("/","")
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
	$hs2vm1sshport = GetPort -Endpoints $hs2vm1Endpoints -usage ssh	

	$vm1 = CreateIdnsNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -logDir $LogDir -nodeDip $hs1vm1IP -nodeUrl $hs1ServiceUrl -nodeDefaultHostname $hs1vm1Hostname
	$vm2 = CreateIdnsNode -nodeIp $hs2VIP -nodeSshPort $hs2vm1sshport -user $user -password $password -logDir $LogDir -nodeDip $hs2vm1IP -nodeUrl $hs2ServiceUrl -nodeDefaultHostname $hs2vm1Hostname

	try
	{
		RemoteCopy -upload -uploadTo $vm1.ip -port $vm1.SShport -username $vm1.user -password $vm1.password -files $currentTestData.files
		RemoteCopy -upload -uploadTo $vm2.ip -port $vm2.SShport -username $vm2.user -password $vm2.password -files $currentTestData.files
		$suppressedOut = RunLinuxCmd -username $vm1.user -password $vm1.password -ip $vm1.Ip -port $vm1.SshPort -command "chmod +x *" -runAsSudo
        if(!$vm1.fqdn -and !$vm2.fqdn)
        {
            $vm1.fqdn =  RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "hostname --fqdn"
            $vm2.fqdn =  RunLinuxCmd -username $user -password $password -ip $hs2VIP -port $hs2vm1sshport -command "hostname --fqdn"
        }

		$vm1.hostname = $vm1.fqdn
		$vm2.hostname = $vm2.fqdn

        #Start the NSLOOKup test..
        $nslookupResult = DoNslookupTest -vm1 $vm1 -vm2 $vm2
        #Start Dig test..
        $digResult = DoDigTest -vm1 $vm1 -vm2 $vm2

		LogMsg "NSLOOKUP : $nslookupResult. DIG : $digResult"

		if(($nslookupResult -imatch "PASS") -and ($digResult -imatch "PASS"))
		{
			$testResult = "PASS"
			LogMsg "NSLOOKUP : PASS. DIG : PASS. Expected behavior."
		}
		else
		{
			$testResult = "FAIL"
			if($nslookupResult -imatch "FAIL")
			{
				LogErr "NSLOOKUP didn't resolved VM DIP using VM fqdn. This is unexpected behaviour."
			}
			if($digResult -imatch "FAIL")
			{
				LogErr "DIG didn't resolved VM DIP using VM fqdn. This is unexpected behaviour."
			}
            LogMsg "Test Result : FAIL"

		}
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
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed
#Return the result and summery to the test suite script..
return $result
#$resultSummary
