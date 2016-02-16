<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$setupType = $currentTestData.setupType
$MaxNic = $xmlConfig.config.Azure.Deployment.$setupType.MaxNic
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{

	try
	{
		$hs1VIP = $AllVMData.PublicIP
		$hs1vm1sshport = $AllVMData.SSHPort
		$hs1ServiceUrl = $AllVMData.URL
		$hs1vm1Dip = $AllVMData.InternalIP

#		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
#		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo

		LogMsg "Executing : $($currentTestData.testScript)"
		$Output = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /proc/net/dev | grep eth[0-9] | wc -l"
		LogMsg	"Expected NIC number is: $MaxNic"
		LogMsg	"Actual NIC number is: $Output"
		if($Output -eq $MaxNic)
		{
			$testResult = 'PASS'
		}
		else
		{
			$testResult = 'FAIL'
		}
		LogMsg "Test result : $testResult"
		LogMsg "Test Completed"

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
#$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
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
