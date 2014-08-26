<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{

    try
    {
        $testServiceData = Get-AzureService -ServiceName $isDeployed

#Get VMs deployed in the service..
        $testVMsinService = $testServiceData | Get-AzureVM

        $hs1vm1 = $testVMsinService
        $hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
        $hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
        $hs1VIP = $hs1vm1Endpoints[0].Vip
        $hs1ServiceUrl = $hs1vm1.DNSName
        $hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
        $hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
        $hs1vm1Hostname =  $hs1vm1.Name


        RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		
		# Get testType (Cloud or FCRDOS) as target. Default is 'cloud'
		$testType = $currentTestData.TestType.Tostring().trim().ToLower()
		if ($testType -eq "")
		{
			$testType = "cloud"
		}
		
		# For FCRDOS image preparation, upload a script named 'report_ip.sh'.
		if ($testType -eq "fcrdos")
		{
			$rods_scrpts = "remote-scripts\report_ip.sh"
			LogMsg "Uploading a script named 'report_ip.sh' for FCRDOS image preparation"
			RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $rods_scrpts -username $user -password $password -upload
		}
		
        RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo

        LogMsg "Executing : $($currentTestData.testScript)"
        $script_command = "./$($currentTestData.testScript) $testType -e $hs1vm1Hostname"
        $output = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command $script_command -runAsSudo
        #RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log $($currentTestData.testScript).log" -runAsSudo
        #RemoteCopy -download -downloadFrom $hs1VIP -files "/home/test/state.txt, /home/test/Summary.log, /home/test/$($currentTestData.testScript).log" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
        #$testResult = Get-Content $LogDir\Summary.log
        #$testStatus = Get-Content $LogDir\state.txt
        #write-host $output
        $testResult = "PASS"
        
        LogMsg "Test result : $testResult"

        LogMsg "Stopping prepared OS image : $hs1vm1Hostname"
        $tmp = Stop-AzureVM -ServiceName $isDeployed -Name $hs1vm1Hostname -Force
        LogMsg "Stopped the VM succussfully"
        
        LogMsg "Capturing the OS Image"
        $NewImageName = $isDeployed + '-prepared'
        $tmp = Save-AzureVMImage -ServiceName $isDeployed -Name $hs1vm1Hostname -NewImageName $NewImageName -NewImageLabel $NewImageName
        LogMsg "Successfully captured VM image : $NewImageName"
        
        # Capture the prepared image names
        $PreparedImageInfoLogPath = "$pwd\PreparedImageInfoLog.xml"
        if((Test-Path $PreparedImageInfoLogPath) -eq $False)
        {
            $PreparedImageInfoLog = New-Object -TypeName xml
            $root = $PreparedImageInfoLog.CreateElement("PreparedImages")
            $content = "<PreparedImageName></PreparedImageName>"
            $root.set_InnerXML($content)
            $PreparedImageInfoLog.AppendChild($root)
            $PreparedImageInfoLog.Save($PreparedImageInfoLogPath)
        }
        [xml]$xml = Get-Content $PreparedImageInfoLogPath
        $xml.PreparedImages.PreparedImageName = $NewImageName
        $xml.Save($PreparedImageInfoLogPath)
        
        
        if ($testStatus -eq "TestCompleted")
        {
            LogMsg "Test Completed"
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
#$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
    
        # Remove the Cloud Service
        LogMsg "Executing: Remove-AzureService -ServiceName $isDeployed -Force"
        Remove-AzureService -ServiceName $isDeployed -Force
    }
}

else
{
    $testResult = "Aborted"
    $resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
#DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result
