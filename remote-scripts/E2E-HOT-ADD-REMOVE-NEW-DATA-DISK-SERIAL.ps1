<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

#Define Lun arrays according to VM size.
$ExtraSmallVMLUNs = 0
$SmallVMLUNs = 0..1
$MediumVMLUNs = 0..3
$LargeVMLUNs = 0..7
$ExtraLargeVMLUNs= 0..15

foreach ($newSetupType in $currentTestData.SubtestValues.split(","))
{
    #Deploy A new VM..
    LogMsg "Test started for : $newSetupType."
    $isDeployed = DeployVMS -setupType $newSetupType -Distro $Distro -xmlConfig $xmlConfig
    <#
    Use following deployment for debuggging purpose. You need to comment out upper line in this case.
    #>
    #$isDeployed = "ICA-ExtraSmallVM-Suse12PL-8-7-0-18-33" #Debug Code                

    #Start Test if Deployment is successfull.
    if ($isDeployed)
    {
#region COLLECTE DEPLOYED VM DATA
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
#endregion

        mkdir "$LogDir\$newSetupType"
        $testVMObject = CreateHotAddRemoveDataDiskNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -ServiceName $isDeployed -logDir "$LogDir\$newSetupType"
        
        <#This script doesn't need any file to upload, however, we need to upload at least one file to New deployment in order to cache the key to our server. 
        RemoteCypy function is written to cache the server key. So that RunLinuxCmd function can work well..#>
        RemoteCopy -uploadTo $testVMObject.ip -port $testVMObject.sshPort -files $currentTestData.files -username $testVMObject.user -password $testVMObject.password -upload
        
        switch ($hs1vm1.InstanceSize)
        {
            "ExtraSmall"
            {
                $testLUNs = $ExtraSmallVMLUNs
            }
            "Small"
            {
                $testLUNs = $SmallVMLUNs
            }
            "Medium"
            {
                $testLUNs = $MediumVMLUNs
            }
            "Large"
            {
                $testLUNs = $LargeVMLUNs
            }
            "ExtraLarge"
            {
                $testLUNs = $ExtraLargeVMLUNs
            }
        }

#region HOT ADD / REMOVE DISKS..
        $testTasks = ("Add","Remove")

        $HotAddDiskCommand = "DoHotAddNewDataDiskTest -testVMObject `$testVMObject -diskSizeInGB `$diskSize"
        $HotRemoveDiskCommand = "DoHotRemoveDataDiskTest -testVMObject `$testVMObject"

        foreach ($newTask in $testTasks)
        {
            if ($newTask -eq "Remove")
            {
                [Array]::Reverse($testLUNs)
            }
            foreach ($newLUN in $testLUNs)
            {
                try
                {
                    
                    $testVMObject.Lun = $newLUN
                    $testResult = ""
                    if ($newTask -eq "Add")
                    {
                        $testCommand = $HotAddDiskCommand
                        $metaData = "$newSetupType : Add : LUN$newLUN : $diskSize.0GB"
                        $diskSize = (($newLUN + 1)*10)
                    }
                    elseif ($newTask -eq "Remove")
                    {
                        $testCommand = $HotRemoveDiskCommand
                        $metaData = "$newSetupType : Remove : LUN$newLUN"
                    }

                    #Execute Test Here
                    $testResult = Invoke-Expression $testCommand
                    #$testResult = "PASS"
                }
                catch
                {
                    $ErrorMessage =  $_.Exception.Message
                    LogMsg "EXCEPTION : $ErrorMessage"   
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
        }
#endregion
        $result = GetFinalResultHeader -resultarr $resultArr   
        DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed
         
        foreach ($disk in $testVMObject.AttachedDisks)
        {
            $ret = RetryOperation -operation {Remove-AzureDisk -DiskName $disk -DeleteVHD} -description "Deleting disk $disk.."
            
            if($ret -and ($ret.OperationStatus -eq "Succeeded"))
            {
                LogMsg "Deleted disk $disk"
            }
            else
            {
                LogMsg "Delete disk $disk unsuccessful.. Please delete the disk manually."
            }
        }
    }

    else
    {
        $testResult = "Aborted"
        $resultArr += $testResult
        $resultSummary +=  CreateResultSummary -testResult $testResult -metaData "" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
    }
}

$result = GetFinalResultHeader -resultarr $resultArr

#Return the result and summery to the test suite script..
return $result, $resultSummary 