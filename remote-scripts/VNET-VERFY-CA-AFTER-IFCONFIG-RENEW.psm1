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
                UploadFilesToAllDeployedVMs -SSHDetails $SSHDetails  -files ".\remote-scripts\temp.txt"
                $testResult = VerifyDNSServerInResolvConf -DeployedServices $isDeployed -dnsServerIP '192.168.3.120'
                if ($testResult -eq "True")
                {
                    $testResult = "PASS"
                }
                else
                {
                    $testResult = "FAIL"
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
        LogErr "Test Aborted due to Configuration Failure.."
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
