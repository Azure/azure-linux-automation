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
#region EXTRACT ALL INFORMATION ABOUT DEPLOYED VMs
	$SSHDetails = Get-SSHDetailofVMs -DeployedServices $isDeployed
#endregion
#region CONFIGURE VNET VMS AND MAKE THEM READY FOR VNET TEST EXECUTION...
	try
	{
        # NO PRECONFIGURATION NEEDED FOR THIS TEST.
        #$tmp = ConfigureVNETVMs -SSHDetails $SSHDetails
		$isAllConfigured = "True"
	}
	catch
	{
		$isAllConfigured = "False"
		$ErrorMessage =  $_.Exception.Message
		LogErr "EXCEPTION : $ErrorMessage"   
	}
#endregion

#region TEST EXECUTION
	if ($isAllConfigured -eq "True")
	{
		try
		{
            $randomFileName = [System.IO.Path]::GetRandomFileName()
            $randomFilePath = "$LogDir\$randomFileName"
            Set-Content -Value "Temporary random file." -Path $randomFilePath | Out-Null
            UploadFilesToAllDeployedVMs -SSHDetails $SSHDetails -files $randomFilePath
            Remove-Item $randomFilePath | Out-Null
			$testResultBeforeReboot = VerifyDIPafterInitialDeployment -DeployedServices $isDeployed
# Now Reboot all the deployments..
			if ($testResultBeforeReboot -eq "True")
			{
				$isRestarted = RestartAllDeployments -DeployedServices $isDeployed
				if ($isRestarted -eq "True")
				{
					$testResultAfterReboot = VerifyDIPafterInitialDeployment -DeployedServices $isDeployed
					if($testResultAfterReboot -eq "True")
					{
						LogMsg "ALL VMs have correct DIPs."
						$testResult = "PASS"
					}
					else
					{
						LogMsg "Test FAILED after VM reboot."
						$testResult = "FAIL"
					}
				}
				else
				{
					LogErr "Unable to restart VMs."
					$testResult = "FAIL"
				}
			}
			else
			{
				LogMsg "VMs does not have valid DIPs before reboot. Stopping the test."
				$testResult = "FAIL"
			}
		}
		catch
		{
			$ErrorMessage =  $_.Exception.Message
			LogErr "EXCEPTION : $ErrorMessage"   
		}
		Finally
		{
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
		LogErr "Test Aborted due to VNET Configuration Failure.."
		$testResult = "Aborted"
		$resultArr += $testResult
	}
#endregion

}
else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#region Clenup the DNS server.
#   THIS TEST DOESN'T REQUIRE DNS SERVER CLEANUP
#endregion

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result
