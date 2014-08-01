<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
Import-Module .\TestLibs\parser.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig

if($isDeployed)
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
    $prevSyncOffset = "NotInitialized"
    $isPrevSynced = $false
    $FirstChek = $true
    $ShowSyncDetails = $true
    
    $NTPtestCurrentTime = Get-Date
    
    $maxDeviationFromZeroAllowed = 2
    $syncChangeFromSyncToUnsync = 0
    $syncChangeFromUnsyncToSync = 0
    $TotalOffsetChanges = 0
    $CpuUsageCommand = "top -bn2"

    try
    {
	    #Detect Linux Distro..
        $DetectedDistro = DetectLinuxDistro -VIP $hs1VIP -SSHport $hs1vm1sshport -testVMUser $user -testVMPassword $password
        switch ( $detectedDistro )
        {
            #TO BE UPDATED FOR EACH DISTRO..
            "UBUNTU"
            {
                $ntpdcOutputCommand = "ntpdc -p"
                $ntpdcServiceName = "ntp"
            }
            "SLES"
            {
                $ntpdcOutputCommand = "ntpdc -p"
                $ntpdcServiceName = "ntp"
            }
            "SUSE"
            {
                $ntpdcOutputCommand = "ntpdc -p"
                $ntpdcServiceName = "ntp"
            }
            "CENTOS"
            {
                $ntpdcOutputCommand = "ntpdc -p"
                $ntpdcServiceName = "ntp"
            }
            "ORACLELINUX"
            {
                $ntpdcOutputCommand = "ntpdc -p"
                $ntpdcServiceName = "ntp"
            }
            "REDHAT"
            {
                $ntpdcOutputCommand = "ntpdc -p"
                $ntpdcServiceName = "ntp"
            }
            "UNKNOWN"
            {
                Throw "UNKNOWN LINUX DISTRO."
            }

        }
        RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
        Function ConfigureNTPService ($xmlConfigFile, $IP, $sshPort, $user, $password, $DetectedDistro)
        {
            $out = RunLinuxCmd -username $user -password $password -ip $IP -port $sshPort -command "chmod +x *.py" -runAsSudo
            LogMsg "Operation : Configure NTP : STARTED."
            $out = RunLinuxCmd -username $user -password $password -ip $IP -port $sshPort -command "./ConfigureNTP.py -d $detectedDistro" -runAsSudo
            LogMsg "Operation : Configure NTP : FINISHED."
        }
        ConfigureNTPService -IP $hs1VIP -sshPort $hs1vm1sshport -user $user -password $password -DetectedDistro $DetectedDistro
        Function MakeNumberPositive ($NumericValue)
        {
            if($NumericValue -lt 0)
            {
                $NumericValue = $NumericValue * -1
            }
            return $NumericValue
        }
        $isAllConfigured = $true
        $NTPtestStartTime  = Get-Date
        $NTPtestEndTime  = $NTPtestStartTime.AddMinutes(2880)
        LogMsg "Checking NTP SYNC status."
        While($NTPtestEndTime -gt $NTPtestCurrentTime)
        {
    
            $NTPtestCurrentTime = Get-Date
            
            $saveY = [console]::CursorTop
            $saveX = [console]::CursorLeft  
            Function CheckNtpdOutput ([string]$detectedDistro)
            {
                $saveY = [console]::CursorTop
                $saveX = [console]::CursorLeft  
                $ntpdcOutput = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -runAsSudo -command $ntpdcOutputCommand -NoLogsPlease $true -ignoreLinuxExitCode
                [console]::setcursorposition($saveX,$saveY)
                return $ntpdcOutput
            }
            $ntpdcOutput =  CheckNtpdOutput -detectedDistro $DetectedDistro
            $synchedLine =  $ntpdcOutput.split("`n") -imatch "\*"
            if ($synchedLine)
            {
                $FirstChek = $true
                $SplittedSynchedLine = $synchedLine.Split("")
                $isPrevSynced = $true
                $newSplittedLine = @()
                foreach ($newLine in $SplittedSynchedLine)
                { 
                    if ($newLine)
                    {
                        $newSplittedLine += $newLine
                    } 
                }
                $SyncedWithServer =  $newSplittedLine[0].Replace("*","")
                $SynchedWithIP = $newSplittedLine[1]
                $CurrentSyncOffset = $newSplittedLine[($newSplittedLine.Length - 2)]
                if($ShowSyncDetails)
                {
                    LogMsg "VM is in sync with ntp server URL : $SyncedWithServer, IP : $SynchedWithIP, Offset : $CurrentSyncOffset"
                    $ShowSyncDetails = $false
                }
                if($isPrevUnsynced)
                {
                    LogMsg "VM NTP sync change detected from UNSYNCED --> SYNCED"
                    $syncChangeFromUnsyncToSync += 1
                    $isPrevUnsynced = $false
                    $ShowSyncDetails = $true
                }
                if($prevSyncOffset -ne $CurrentSyncOffset)
                {
                    #$cpuLoad = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -runAsSudo -command $CpuUsageCommand -NoLogsPlease $true
                    LogMsg "Offset change detected from: $prevSyncOffset to $CurrentSyncOffset."
                    $type = ($($prevSyncOffset.GetType().Name))
                    Write-Host $type
                    if (($prevSyncOffset -ne "NotInitialized") -and ($prevSyncOffset -ne "UnSynced"))
                    {
                        $diffInOffset = ($prevSyncOffset - $CurrentSyncOffset)
                        $diffInOffset = MakeNumberPositive -NumericValue $diffInOffset
                        LogMsg "Differnce in offset : $diffInOffset"
                    }
                    else
                    {
                        $diffInOffset = $CurrentSyncOffset
                    }
                    if ($diffInOffset -lt $maxDiffInOffset)
                    {
                        $maxDiffInOffset = $diffInOffset
                    }
                    $TotalOffsetChanges += 1
                    $prevSyncOffset = $CurrentSyncOffset
                    Write-Host "Checking for next offset change.."
                    Write-Progress -Id 2469 -Activity "Waiting for next offset change.." -Status "Current Offset : $CurrentSyncOffset" -SecondsRemaining ($NTPtestEndTime - $NTPtestCurrentTime).TotalSeconds -Completed
                }
                else
                {
                    Write-Progress -Id 2469 -Activity "Waiting for next offset change.." -Status "Current Offset : $CurrentSyncOffset" -SecondsRemaining ($NTPtestEndTime - $NTPtestCurrentTime).TotalSeconds
                }
            }
            else
            {
                if($isPrevSynced)
                {
                    LogMsg "VM NTP sync change detected from SYNCED --> UNSYNCED"
                    $syncChangeFromSyncToUnsync += 1
                    $isPrevSynced = $false
                    $prevSyncOffset = "UnSynced"
                }
                else
                {
                    if($FirstChek)
                    {
                        LogMsg "VM is not in sync with any NTP server."
                        LogMsg "Waiting for VM to Sync with NTP server.."
                        $FirstChek = $false
                    }
                    else
                    {
                        Write-Progress -Id 2469 -Activity "Waiting for VM to Sync with NTP server.." -Status "VM is not in sync with any NTP server." -SecondsRemaining ($NTPtestEndTime - $NTPtestCurrentTime).TotalSeconds
                    }
                    $isPrevUnsynced = $true
                }
            }
            Sleep -Seconds 1
        }
        LogMsg "UnSync to Sync : $syncChangeFromUnsyncToSync"
        LogMsg "Sync to UnSync : $syncChangeFromSyncToUnsync"
        LogMsg "Total offset Changes : $TotalOffsetChanges"
         
        $testResult = "PASS"
	    #---------------------
    }
    catch
    {
        $ErrorMessage =  $_.Exception.Message
        LogMsg "EXCEPTION : $ErrorMessage"   
    }
    Finally
    {
        $metaData = $mode 
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
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result