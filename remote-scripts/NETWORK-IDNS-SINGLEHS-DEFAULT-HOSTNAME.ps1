<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
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

	$vm1 = CreateIdnsNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -logDir $LogDir -nodeDip $hs1vm1IP -nodeUrl $hs1ServiceUrl -nodeDefaultHostname $hs1vm1Hostname
	$vm2 = CreateIdnsNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -user $user -password $password -logDir $LogDir -nodeDip $hs1vm2IP -nodeUrl $hs1ServiceUrl -nodeDefaultHostname $hs1vm2Hostname

	try
	{
		RemoteCopy -upload -uploadTo $vm1.ip -port $vm1.SShport -username $vm1.user -password $vm1.password -files $currentTestData.files 
		RemoteCopy -upload -uploadTo $vm2.ip -port $vm2.SShport -username $vm2.user -password $vm2.password -files $currentTestData.files

		$nslookupResult = DoNslookupTest -vm1 $vm1 -vm2 $vm2
		$digResult = DoDigTest -vm1 $vm1 -vm2 $vm2

		if (($nslookupResult -eq "PASS") -and ($digResult -eq "FAIL"))
		{
			$testResult = "PASS"
		}
		else
		{
			$testResult = "FAIL"
		}
    	LogMsg "NSLOOKUP RESULT : $nslookupResult. DIG RESULT : $digResult"
		Write-Host "Hum angrejo ke jamane ke jailer hai.. HAHA"
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = "$Value : $mode"
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