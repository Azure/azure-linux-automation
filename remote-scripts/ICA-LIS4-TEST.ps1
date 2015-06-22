Function CreateTestVMNode
{
	param(
            [string] $ServiceName,
			[string] $VIP,
			[string] $SSHPort,
			[string] $username,
			[string] $password,
			[string] $DIP,
			[string] $DNSUrl,
			[string] $logDir )


	$objNode = New-Object -TypeName PSObject
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name ServiceName -Value $ServiceName -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name VIP -Value $VIP -Force 
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name SSHPort -Value $SSHPort -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name username -Value $username -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name password -Value $password -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name DIP -Value $nodeDip -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name logDir -Value $LogDir -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name DNSURL -Value $DNSUrl -Force
	return $objNode
}
Function VerifyAttachedDisks ( $VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $attachedDataDisks = RetryOperation -operation { Get-AzureVM -ServiceName $VMObject.ServiceName | Get-AzureDataDisk } -description "Getting Attached disks"
        LogMsg "Verifying $($attachedDataDisks.Count) disks.."
        $fdiskBefore = "Disk /dev/sda`nDisk /dev/sdb"
        $fdiskAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "fdisk -l" -runAsSudo
        Set-Content -Value $fdiskAfter -Path "$($VMObject.LogDir)\DataDiskStatusAfterDeployingVM.txt"
        LogMsg "fdisk -l console output is saved to $($VMObject.LogDir)\DataDiskStatusAfterDeployingVM.txt"
        $DetectedDisksInVM = GetNewPhysicalDiskNames -FdiskOutputBeforeAddingDisk $fdiskBefore -FdiskOutputAfterAddingDisk $fdiskAfter
        LogMsg "Expected Disks : $($attachedDataDisks.Count)"
        LogMsg "Attached Disks : $($DetectedDisksInVM.Split("^").Count)"
        if ( $attachedDataDisks.Count -eq $DetectedDisksInVM.Split("^").Count )
        {
            LogMsg "All disks detected successfully"
            $ExitCode = "PASS"
        }
        else
        {
            LogErr "Failed to detect all disks. Further tests will be aborted."
            $ExitCode = "FAIL"
        }
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode, $DetectedDisksInVM
}

Function InstallLIS($VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LISExtractCommands = ($currentTestData.LISExtractCommand).Split("^")
        Set-Content -Value "**************modinfo hv_vmbus before installing LIS******************" -Path "$($VMObject.logDir)\modinfo_hv_vmbus_status.txt"
        $modinfo_hv_vmbus_before_installing_LIS = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "modinfo hv_vmbus" -runAsSudo
        Add-Content -Value $modinfo_hv_vmbus_before_installing_LIS -Path "$($VMObject.logDir)\modinfo_hv_vmbus_status.txt"
        foreach ( $LISExtractCommand in $LISExtractCommands )
        {
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command $LISExtractCommand -runAsSudo
        }
        $installLISConsoleOutput = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./install.sh" -runAsSudo -runMaxAllowedTime 1200
        Set-Content -Value $installLISConsoleOutput -Path "$($VMObject.logDir)\InstallLISConsoleOutput.txt"
        if($installLISConsoleOutput -imatch "is already installed")
        {
            LogMsg "Latest LIS version is already installed."
            $ExitCode = "PASS"
        }
        else
        {
            #Reboot VM..
            $RebootStatus = RetryOperation -operation { Get-AzureService -ServiceName $VMObject.ServiceName | Get-AzureVM | Restart-AzureVM } -description "Rebooting VM..."
            if ( $RebootStatus.OperationStatus -eq "Succeeded")
            { 
                if (( VerifyAllDeployments -servicesToVerify $VMObject.ServiceName ) -eq "True")
                {
                    if ( ( isAllSSHPortsEnabled -DeployedServices $VMObject.ServiceName ) -eq "True" )
                    {

                        #Verify LIS Version
                        Add-Content -Value "**************modinfo hv_vmbus after installing LIS******************" -Path "$($VMObject.logDir)\modinfo_hv_vmbus_status.txt"
                        $modinfo_hv_vmbus_after_installing_LIS = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "modinfo hv_vmbus" -runAsSudo
                        Add-Content -Value $modinfo_hv_vmbus_after_installing_LIS -Path "$($VMObject.logDir)\modinfo_hv_vmbus_status.txt"
                        if ( $modinfo_hv_vmbus_before_installing_LIS -ne $modinfo_hv_vmbus_after_installing_LIS )
                        {
                            LogMsg "New LIS version detected."
                            $ExitCode = "PASS"
                        }
                        else
                        {
                            LogErr "New LIS version NOT detected."
                            $ExitCode = "FAIL"
                        }
                    }
                    else
                    {
                        LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                        $ExitCode = "ABORTED"
                    }
                }
                else
                {
                    LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                    $ExitCode = "ABORTED"
                }
            }
            else
            {
                LogErr "Failed to reboot. Further Tests will be aborted."
                $ExitCode = "ABORTED"
            }
        }
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

Function AttachAnotherDataDisk($VMObject, $LUN, $DiskSizeInGB=10, $DiskHostCaching="ReadOnly", $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        if ($LUN -eq $null)
        {
            LogMsg "No specific LUN is provided. Detecting empty LUN.."
            $AttachedDisks = RetryOperation -operation { Get-AzureVM -ServiceName  $VMObject.ServiceName | Get-AzureDataDisk } -description "Getting data disks information..."
            $availableLuns = 0..31
            foreach ( $xLun in $availableLuns) 
            {
                $useThisLun = $true
                foreach ( $disk in $AttachedDisks )
                {
                    if ( $xLun -eq $disk.LUN )
                    {
                        LogMsg "LUN : $xLun is in use.."
                        $useThisLun=$false
                        break
                    }
                }
                if ( $useThisLun )
                {
                    $LUN = $xLun
                    break
                }
            }
        }
        $fdiskBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "fdisk -l" -runAsSudo
        $AddDiskStatus = RetryOperation -operation { Get-AzureVM -ServiceName  $VMObject.ServiceName | Add-AzureDataDisk -CreateNew -DiskSizeInGB $DiskSizeInGB -LUN $LUN -HostCaching $DiskHostCaching -DiskLabel "$($VMObject.ServiceName)-DataDisk-Lun-$LUN-HostCaching-$DiskHostCaching-$DiskSizeInGB`GB" | Update-AzureVM } -description "Attaching $($VMObject.ServiceName)-DataDisk-Lun-$LUN-HostCaching-$DiskHostCaching-$DiskSizeInGB`GB disk to LUN : $LUN..."
        $ExpectedDisks = (GetTotalPhysicalDisks -FdiskOutput $fdiskBefore)+1
        if ( $AddDiskStatus.OperationStatus -eq "Succeeded")
        {
            $maxTry = 10
            $DiskIsNotVisible = $true
            while ( $DiskIsNotVisible -and ( $maxTry -gt 0 ))
            {
                $maxTry -= 1
                WaitFor -seconds 30
                $fdiskAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "fdisk -l" -runAsSudo
                $ActualDisks = (GetTotalPhysicalDisks -FdiskOutput $fdiskAfter)
                if ( $ExpectedDisks -eq  $ActualDisks )
                {
                    $NewAttachedDiskName = GetNewPhysicalDiskNames -FdiskOutputBeforeAddingDisk $fdiskBefore -FdiskOutputAfterAddingDisk $fdiskAfter
                    LogMsg "Detected New Disk : $NewAttachedDiskName"
                    $ExitCode = "PASS"
                    $DiskIsNotVisible = $false
                }
                else
                {
                    LogErr "Failed to recognise the disk in VM. Further tests will be aborted."
                    $ExitCode = "FAIL"
                }
            }
        }
        else
        {
            LogErr "Failed to attach disk. Further tests will be aborted."
            $ExitCode = "FAIL"
        }
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"

    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode, $NewAttachedDiskName, $LUN
}

Function VerifyIO($VMObject, $NewAttachedDiskName, $PrevTestStatus, $metaData, $mountPoint="/mnt/datadisk", [switch]$SkipCreatePartition, [switch]$AlreadyMounted, [switch]$DoNotUnmount)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\VerifyIO-$($NewAttachedDiskName.Replace('/','')).txt"
        $partitionNumber=$null
        $dmesgBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg" -runAsSudo 
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
        if ($AlreadyMounted )
        {
            LogMsg "$NewAttachedDiskName is already mounted to $mountPoint"
        }
        else
        {
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mkdir -p $mountPoint" -runAsSudo 
            if ( $SkipCreatePartition )
            {
                $FormatDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mkfs.ext4 $NewAttachedDiskName" -runAsSudo -runMaxAllowedTime 2400
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mount -o nobarrier $NewAttachedDiskName $mountPoint" -runAsSudo 
            }
            else
            {
                $partitionNumber=1
                $PartitionDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $NewAttachedDiskName -create yes -forRaid no" -runAsSudo 
                $FormatDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mkfs.ext4 $NewAttachedDiskName$partitionNumber" -runAsSudo -runMaxAllowedTime 2400 
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mount -o nobarrier $NewAttachedDiskName$partitionNumber $mountPoint" -runAsSudo 
            }
        }
        Add-Content -Value $formatDiskOut -Path $LogPath -Force
        $ddOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dd if=/dev/zero bs=1024 count=1000000 of=$mountPoint/file_1GB" -runAsSudo 
        WaitFor -seconds 10
        Add-Content -Value $ddOut -Path $LogPath
        if ( $DoNotUnmount )
        {
            LogMsg "Keeping $NewAttachedDiskName$partitionNumber mounted to $mountPoint"
        }
        else
        {
            try
            {
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "umount $mountPoint" -runAsSudo 
            }
            catch
            {
                LogMsg "umount failed. Trying umount -l"
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "umount -l $mountPoint" -runAsSudo 
            }
        }
        $dmesgAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg" -runAsSudo
        $addedLines = $dmesgAfter.Replace($dmesgBefore,$null)
        LogMsg "Kernel Logs : $($addedLines.Replace('[32m','').Replace('[0m[33m','').Replace('[0m',''))" -LinuxConsoleOuput
        $ExitCode = "PASS"    
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

Function DetachDataDisk($VMObject, $LUN, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $fdiskBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "fdisk -l" -runAsSudo
        $RemoveDiskStatus = RetryOperation -operation { Get-AzureVM -ServiceName  $VMObject.ServiceName | Remove-AzureDataDisk -LUN $LUN | Update-AzureVM } -description "Removing data disk from LUN : $LUN..."
        $ExpectedDisks = (GetTotalPhysicalDisks -FdiskOutput $fdiskBefore)-1
        if ( $RemoveDiskStatus.OperationStatus -eq "Succeeded")
        {
            $DiskIsVisible = $true
            $maxTry = 10
            while ( $DiskIsVisible -and ( $maxTry -gt 0 ))
            {
                WaitFor -seconds 30
                $maxTry -= 1
                $fdiskAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "fdisk -l" -runAsSudo
                $ActualDisks = (GetTotalPhysicalDisks -FdiskOutput $fdiskAfter)
                if ( $ExpectedDisks -eq  $ActualDisks )
                {
                    $NewAttachedDiskName = GetNewPhysicalDiskNames -FdiskOutputBeforeAddingDisk $fdiskAfter -FdiskOutputAfterAddingDisk $fdiskBefore
                    LogMsg "Removed Disk : $NewAttachedDiskName"
                    $ExitCode = "PASS"
                    $DiskIsVisible = $false
                }
                else
                {
                    LogErr "Disk is still visible in VM."
                    $ExitCode = "FAIL"
                }
            }
        }
        else
        {
            LogErr "Failed to attach disk. Further tests will be aborted."
            $ExitCode = "FAIL"
        }
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"

    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

#If we have already coded RAID functinos, just copy and paste them here.

Function CreatePartitionOnDisk ($VMObject, $diskName, $isItForRaid, $LogFilePath)
{
    $diskShortName = $diskName.Replace("/dev/","")
    $lsblkBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "lsblk"
    Add-Content -Value $lsblkBefore -Path $LogFilePath -Force
    $PartitionDetected = $false
    foreach ( $line in $lsblkBefore.Split("`n"))
    {
        $line = $line.Trim().Replace("├","").Replace("─","").Replace("└","").Replace("Γ","").Replace("ö","").Replace("Ç","").Replace("  "," ").Replace("  "," ").Replace("  "," ")
        if (($line -imatch $diskShortName) -and ($line -imatch "part"))
        {
            $partitionName = $line.Split()[0]
            $Size = $line.Split()[3]
            $mountedTo = $line.Split()[6]
            $PartitionDetected = $true
        }
    }
    if ( $PartitionDetected )
    {
        LogMsg "Deleting partition $partitionName"
        if ($mountedTo -eq $null)
        {
            $deletePartition = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $diskName -delete yes" -runAsSudo 
        }
        else
        {
            LogMsg "$diskName is mounted to $mountedTo. Trying to unmount"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "umount $mountedTo" -runAsSudo 
            $deletePartition = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $diskName -delete yes" -runAsSudo 
        }
        Add-Content -Value $deletePartition -Path $LogFilePath -Force
    }
    LogMsg "Creating the partition on $diskName"
    $PartitionDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $diskName -create yes -forRaid $isItForRaid" -runAsSudo 
    Add-Content -Value $PartitionDiskOut -Path $LogFilePath -Force
    $lsblkAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "lsblk" 
    Add-Content -Value $lsblkAfter -Path $LogFilePath -Force
    $PartitionDetected = $false
    foreach ( $line in $lsblkAfter.Split("`n"))
    {
        $line = $line.Trim().Replace("├","").Replace("─","").Replace("└","").Replace("Γ","").Replace("ö","").Replace("Ç","").Replace("  "," ").Replace("  "," ").Replace("  "," ")
        if (($line -imatch $diskShortName) -and ($line -imatch "part"))
        {
            $partitionName = "/dev/$($line.Split()[0])"
            $Size = $line.Split()[3]
            $mountedTo = $line.Split()[6]
            $PartitionDetected = $true
        }
    }
    if ($PartitionDetected)
    {
        LogMsg "$partitionName created successfully."
    }
    else
    {
        LogErr "$partitionName not created."
    }
return $PartitionDetected, $partitionName
}

Function FormatPartition ($VMObject, $PartitionName, $FileSystem, $LogFilePath)
{
    LogMsg "Formatting $PartitionName with $FileSystem file system"
    $formatOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mkfs -t $FileSystem $PartitionName" -runAsSudo
    Add-Content -Value $formatOut -Path $LogFilePath -Force
    return $true
}

Function StopRaidArry($VMObject, $RaidName)
{
    #Verify if raid is active
    $df = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "df").Split("`n")
    LogMsg "unmounting $RaidName, if any."
    foreach ( $line in $df )
    {
        if ( $line -imatch $RaidName )
        {
            $ActiveArray = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[0]
            $MountDir = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[5]
            LogMsg "Found mounted array : $ActiveArray mounted to $MountDir"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "umount $MountDir" -runAsSudo
        }
    }
    $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
    foreach ( $line in $mdStat )
    {
        if ( $line -imatch "active" )
        {
            $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Split()[0]
            LogMsg "Found active arry : $ActiveArray"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
        }
    }
}

Function CreateRAIDOnDevices($VMObject, $NewAttachedDiskNames, $PrevTestStatus, $RaidName, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\CreateRaidOnDevices.txt"
        $mountPoint = "/mnt/RaidVolume"
        $dmesgBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg" -runAsSudo 
        $totalDisks = $NewAttachedDiskNames.Split("^").Count
        $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
        foreach ( $line in $mdStat )
        {
            if ( $line -imatch "active" )
            {
                $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Split()[0]
                LogMsg "Found active arry : $ActiveArray"
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
            }
        }

        $wipefs = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "wipefs -a $($NewAttachedDiskNames.Replace("^"," "))" -runAsSudo
        LogMsg $wipefs -LinuxConsoleOuput
        Add-Content -Value $wipefs -Path $LogPath -Force
        LogMsg "Creating raid of $totalDisks disks."
        LogMsg "Disks : $($NewAttachedDiskNames.Replace("^"," "))"
        $createRaidOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mdadm --create $RaidName --level 0 --raid-devices $totalDisks $($NewAttachedDiskNames.Replace("^"," "))" -runAsSudo 
        Add-Content -Value $createRaidOut -Path $LogPath -Force
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
        #$verifyRaid = VerifyIO -VMObject $VMObject -NewAttachedDiskName $RaidName -PrevTestStatus "PASS" -metaData "VerifyingIO on Raid Drive : $RaidName" -SkipCreatePartition
        $verifyRaid = "PASS"
        if ( $verifyRaid -eq "PASS" )
        {
            $StopRaidResult = StopRaidArry -VMObject $VMObject -RaidName $RaidName
            $ExitCode = "PASS"   
        }
        else
        {
            $ExitCode = "FAIL"    
        }
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

Function CreateRAIDOnPartitionsAlreadyFormatted($VMObject, $NewAttachedDiskNames, $PrevTestStatus, $RaidName, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\CreateRaidOnPartitionAlreadyFormattedDevices.txt"
        $mountPoint = "/mnt/RaidVolume"
        $RaidDisks = $NewAttachedDiskNames.Split("^")
        $wipefs = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "wipefs -a $($NewAttachedDiskNames.Replace("^"," "))" -runAsSudo
        LogMsg $wipefs -LinuxConsoleOuput
        Add-Content -Value $wipefs -Path $LogPath -Force
        $newPartitions += @()
        foreach ($disk in $RaidDisks)
        {
            $CreatePart = CreatePartitionOnDisk -VMObject $VMObject -diskName $disk -isItForRaid "yes" -LogFilePath $LogPath
            $newPartitions += "$($CreatePart[1])"
        }
        #Now Reboot the VM..
        $RebootStatus = RetryOperation -operation { Get-AzureService -ServiceName $VMObject.ServiceName | Get-AzureVM | Restart-AzureVM } -description "Rebooting VM..."
        if ( $RebootStatus.OperationStatus -eq "Succeeded")
        {
            if (( VerifyAllDeployments -servicesToVerify $VMObject.ServiceName ) -eq "True")
            {
                if ( ( isAllSSHPortsEnabled -DeployedServices $VMObject.ServiceName ) -eq "True" )
                {
                    $RaidPartitions = ""
                    $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
                    foreach ( $line in $mdStat )
                    {
                        if ( $line -imatch "active" )
                        {
                            $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Split()[0]
                            LogMsg "Found active arry : $ActiveArray"
                            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
                        }
                    }
                    foreach ($partitionName in $newPartitions )
                    {
                        #format all partitions..
                        $RaidPartitions = ""
                        $formatPart = FormatPartition -VMObject $VMObject -PartitionName $partitionName -FileSystem "ext4" -LogFilePath $LogPath
                        if ($formatPart)
                        {
                            $RaidPartitions += "$partitionName "
                        }
                        else
                        {
                            Throw "Aborting Test"
                    
                        }
                    }
                    $RaidPartitions = $RaidPartitions.Trim()
                    $dmesgBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg" -runAsSudo 
                    $totalDisks = $NewAttachedDiskNames.Split("^").Count
                    LogMsg "Creating raid of $totalDisks disks."
                    LogMsg "Disks : $RaidPartitions"
                    $createRaidOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./ManageRaid.sh -create yes -diskNames $($RaidPartitions.Replace(" ","^")) -totalDisks $totalDisks -RaidName $RaidName " -runAsSudo 
                    Add-Content -Value $createRaidOut -Path $LogPath -Force
                    #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
                    #$verifyRaid = VerifyIO -VMObject $VMObject -NewAttachedDiskName $RaidName -PrevTestStatus "PASS" -metaData "VerifyingIO on Raid Drive : $RaidName" -SkipCreatePartition
                    $verifyRaid = "PASS"
                    if ( $verifyRaid -eq "PASS" )
                    {
                        $StopRaidResult = StopRaidArry -VMObject $VMObject -RaidName $RaidName
                        $ExitCode = "PASS"   
                    }
                    else
                    {
                        $ExitCode = "FAIL"    
                    }
                }
                else
                {
                    LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                    $ExitCode = "ABORTED"
                }
            }
            else
            {
                LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                $ExitCode = "ABORTED"
            }
        }
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}
Function CreateRAIDOnPartitionsNotFormatted($VMObject, $NewAttachedDiskNames, $PrevTestStatus , $metaData, $RaidName, $RaidMountPoint, [switch]$DoNotStopRaid)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\CreateRaidOnNotFormattedPartition.txt"
        $RaidDisks = $NewAttachedDiskNames.Split("^")
        $wipefs = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "wipefs -a $($NewAttachedDiskNames.Replace("^"," "))" -runAsSudo
        LogMsg $wipefs -LinuxConsoleOuput
        Add-Content -Value $wipefs -Path $LogPath -Force
        $RaidPartitions = ""
        foreach ($disk in $RaidDisks)
        {
            $CreatePart = CreatePartitionOnDisk -VMObject $VMObject -diskName $disk -isItForRaid "yes" -LogFilePath $LogPath
            $RaidPartitions += "$($CreatePart[1]) "
        }
        $RaidPartitions = $RaidPartitions.Trim()
        #Now Reboot the VM..
        $RebootStatus = RetryOperation -operation { Get-AzureService -ServiceName $VMObject.ServiceName | Get-AzureVM | Restart-AzureVM } -description "Rebooting VM..."
        if ( $RebootStatus.OperationStatus -eq "Succeeded")
        {
            if (( VerifyAllDeployments -servicesToVerify $VMObject.ServiceName ) -eq "True")
            {
                if ( ( isAllSSHPortsEnabled -DeployedServices $VMObject.ServiceName ) -eq "True" )
                {
                    $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
                    foreach ( $line in $mdStat )
                    {
                        if ( $line -imatch "active" )
                        {
                            $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Split()[0]
                            LogMsg "Found active arry : $ActiveArray"
                            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
                        }
                    }
                    $dmesgBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg" -runAsSudo 
                    $totalDisks = $NewAttachedDiskNames.Split("^").Count
                    LogMsg "Creating raid of $totalDisks disks."
                    LogMsg "Disks : $RaidPartitions"
                    $createRaidOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./ManageRaid.sh -create yes -diskNames $($RaidPartitions.Replace(" ","^")) -totalDisks $totalDisks -RaidName $RaidName" -runAsSudo 
                    LogMsg $createRaidOut -LinuxConsoleOuput
                    Add-Content -Value $createRaidOut -Path $LogPath -Force
                    $formatRaid = FormatPartition -VMObject $VMObject -PartitionName $RaidName -FileSystem ext4 -LogFilePath "$LogDir\FormatRaid.txt"
                    LogMsg (Get-Content "$LogDir\FormatRaid.txt") -LinuxConsoleOuput
                    $Out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mkdir -p $RaidMountPoint" -runAsSudo 
                    $Out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "mount -o nobarrier $RaidName $RaidMountPoint" -runAsSudo 
                    #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
                    #$verifyRaid = VerifyIO -VMObject $VMObject -NewAttachedDiskName $RaidName -PrevTestStatus "PASS" -metaData "VerifyingIO on Raid Drive : $RaidName" -SkipCreatePartition
                    $ExitCode = "PASS"
                }
                else
                {
                    LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                    $ExitCode = "ABORTED"
                }
            }
            else
            {
                LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                $ExitCode = "ABORTED"
            }
        }
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode 
}

Function isLinuxProcessRunning ($VMObject, $ProcessName)
{
    LogMsg "Verifying if $ProcessName is running.."
    $psef = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "ps -ef"
    $foundProcesses = 0
    foreach ( $line in $psef.Split("`n"))
    {
        if (( $line -imatch $ProcessName) -and !( $line -imatch "--color=auto"))
        {
            $foundProcesses += 1
            $linuxUID = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[0]
            $linuxPID = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[1]
            $linuxPPID = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[2]
            $linuxC = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[3]
            $linuxSTIME = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[4]
            $linuxTTY = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[5]
            $linuxTIME = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[6]
            $linuxCMD = $line.Trim().Replace("$linuxUID","").Replace("$linuxPID","").Replace("$linuxPPID","").Replace("$linuxC","").Replace("$linuxSTIME","").Replace("$linuxTTY","").Replace("$linuxTIME","").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ")
            LogMsg "FOUND PROCESS : UID=$linuxUID, PID=$linuxPID, RUNNING TIME=$linuxTIME, COMMAND=$linuxCMD"
        }
    }
    return $foundProcesses
}
Function RunSysBench($VMObject, $PrevTestStatus, $TestDirectory, $SysbenchConfigObject, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\SysbenchLogs.txt"
        $SysbenchLogDir = "/home/$user/SysbenchLogs-$((Get-Date).Year)-$((Get-Date).Month)-$((Get-Date).Day)-$((Get-Date).Hour)-$((Get-Date).Minute)-$((Get-Date).Second)"
        #Prepare Sysbench files...
        
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cp -af sys-custom.sh $TestDirectory" -runAsSudo
        Set-Content -Value "#!/bin/bash" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
        Add-Content -Value "cd $TestDirectory" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
        Add-Content -Value "./sys-custom.sh -PrepareFiles yes -RunTest no -CleanUp no -CustomLogDir $SysbenchLogDir -fileSize $($SysbenchConfigObject.fileSize)" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
        RemoteCopy -uploadTo $VMObject.VIP -port $VMObject.SSHPort -files "$($VMObject.LogDir)\InvokeSys.sh" -username $VMObject.username -password $VMObject.password -upload
        Remove-Item -Path  "$($VMObject.LogDir)\InvokeSys.sh"
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "chmod +x *.sh" -runAsSudo
        LogMsg "SYSBECH COMMAND : ./sys-custom.sh -PrepareFiles yes -RunTest no -CleanUp no -CustomLogDir $SysbenchLogDir -fileSize $($SysbenchConfigObject.fileSize)" -Path "$($VMObject.LogDir)\InvokeSys.sh"
        $FilePrepare = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./InvokeSys.sh" -runAsSudo -RunInBackGround
        if ( ( isLinuxProcessRunning -VMObject $VMObject -ProcessName "sysbench --test" ) -eq 1)
        {
            $currentStatus = $null
            while (!( $currentStatus -imatch "SYSBENCH-FILE-PREPARE-FINISH" ))
            {
                $currentStatus = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat $SysbenchLogDir/CurrentSysbenchStatus.txt"
                if ( $currentStatus -imatch "SYSBENCH-FILE-PREPARE-PROGRESS")
                {
                    LogMsg "SYSBENCH-FILE-PREPARE-PROGRESS"
                    WaitFor -seconds 30
                }
            }
            LogMsg "Sysbebch files prepared successfully."
            RemoteCopy -downloadFrom $VMObject.VIP -port $VMObject.SSHPort -username $VMObject.username -password $VMObject.password -files "$SysbenchLogDir/iostat-sysbench-file-prepare.txt" -downloadTo $VMObject.LogDir -download
            #Run Tests..
            $SysBenchErrors = 0
            $SysBenchTests = 0
            $TotalSysBenchTests = (($SysbenchConfigObject.testModes).Split(",").Count)*(($SysbenchConfigObject.IOs).Split(",").Count)*(($SysbenchConfigObject.Threads).Split(",").Count)
            foreach ( $mode in ($SysbenchConfigObject.testModes).Split(","))
            {
                foreach ( $io in ($SysbenchConfigObject.IOs).Split(","))    
                {
                    foreach ( $thread in ($SysbenchConfigObject.Threads).Split(","))    
                    {
                        $SysBenchTests += 1
                        LogMsg "=-=-=-=-=-=-=-=-=-=SYSBENCH TEST START :[$SysBenchTests/$TotalSysBenchTests] MODE:$($mode.ToUpper()), IO:$($io)K, Threads:$thread, RunTime:$($SysbenchConfigObject.ioRuntime) SECONDS=-=-=-=-=-=-=-=-=-="
                        Set-Content -Value "#!/bin/bash" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
                        Add-Content -Value "cd $TestDirectory" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
                        Add-Content -Value "./sys-custom.sh -RunTest yes -fileSize $($SysbenchConfigObject.fileSize) -testIO $($io)K -testMode $mode -testThread $thread -CustomLogDir $SysbenchLogDir -ioRuntime $($SysbenchConfigObject.ioRuntime)" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
                        RemoteCopy -uploadTo $VMObject.VIP -port $VMObject.SSHPort -files "$($VMObject.LogDir)\InvokeSys.sh" -username $VMObject.username -password $VMObject.password -upload
                        Remove-Item -Path  "$($VMObject.LogDir)\InvokeSys.sh"
                        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "chmod +x *.sh" -runAsSudo
                        LogMsg "SYSBENCH COMMAND : ./sys-custom.sh -RunTest yes -fileSize $($SysbenchConfigObject.fileSize) -testIO $($io)K -testMode $mode -testThread $thread -CustomLogDir $SysbenchLogDir -ioRuntime $($SysbenchConfigObject.ioRuntime)" -Path "$($VMObject.LogDir)\InvokeSys.sh"
                        $RunSysbenchOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./InvokeSys.sh" -runAsSudo -RunInBackGround
                        if ( ( isLinuxProcessRunning -VMObject $VMObject -ProcessName "sysbench --test" ) -eq 1)
                        {
                            LogMsg "Test sterted for mode : $mode, IO size : $($io)K, Total Threads : $thread, Run Time : $($SysbenchConfigObject.ioRuntime) seconds."
                            $currentStatus = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat $SysbenchLogDir/CurrentSysbenchStatus.txt"
                            while ( $currentStatus -imatch "SYSBENCH-TEST-RUNNING" )
                            {
                                $currentStatus = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "cat $SysbenchLogDir/CurrentSysbenchStatus.txt"
                                if ( $currentStatus -imatch "SYSBENCH-TEST-RUNNING")
                                {
                                    LogMsg "Test Running for mode : $mode, IO size : $($io)K, Total Threads : $thread, Run Time : $($SysbenchConfigObject.ioRuntime) seconds."
                                    WaitFor -seconds 30
                                }
                            }
                            if ( $currentStatus -imatch "SYSBENCH-TEST-FINISHED" )
                            {
                                LogMsg "Test finished for mode : $mode, IO size : $($io)K, Total Threads : $thread, Run Time : $($SysbenchConfigObject.ioRuntime) seconds."
                                RemoteCopy -downloadFrom $VMObject.VIP -port $VMObject.SSHPort -username $VMObject.username -password $VMObject.password -files "$SysbenchLogDir/iostat-sysbench-$mode-$($io)K-$thread.txt" -downloadTo $VMObject.LogDir -download
                            }
                            else
                            {
                                LogErr "Unknown sysbench error"
                                $SysBenchErrors += 1
                            }
                        }
                        else
                        {
                            LogErr "sysbench process not detected."
                            $ExitCode = "FAIL"
                            $SysBenchErrors += 1
                        }
                        LogMsg "=-=-=-=-=-=-=-=-=-=SYSBENCH TEST END:[$SysBenchTests/$TotalSysBenchTests] MODE:$($mode.ToUpper()), IO:$($io)K, Threads:$thread, RunTime:$($SysbenchConfigObject.ioRuntime) SECONDS=-=-=-=-=-=-=-=-=-="
                    }
                }
            }
            LogMsg "$($SysBenchTests - $SysBenchErrors) out of $TotalSysBenchTests sysbench tests completed."
            RemoteCopy -downloadFrom $VMObject.VIP -port $VMObject.SSHPort -username $VMObject.username -password $VMObject.password -files "$SysbenchLogDir/sysbench.log.txt" -downloadTo $VMObject.LogDir -download
            #Do Cleanup..
            LogMsg "Starting sysbench clenup.."
            Set-Content -Value "#!/bin/bash" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
            Add-Content -Value "cd $TestDirectory" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
            Add-Content -Value "./sys-custom.sh -CleanUp yes -CustomLogDir $SysbenchLogDir -fileSize $($SysbenchConfigObject.fileSize)" -Path "$($VMObject.LogDir)\InvokeSys.sh" -Force
            RemoteCopy -uploadTo $VMObject.VIP -port $VMObject.SSHPort -files "$($VMObject.LogDir)\InvokeSys.sh" -username $VMObject.username -password $VMObject.password -upload
            Remove-Item -Path  "$($VMObject.LogDir)\InvokeSys.sh"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "chmod +x *.sh" -runAsSudo
            $RunSysbenchCleanup = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./InvokeSys.sh" -runAsSudo
            LogMsg "sysbench clenup completed.."
            LogMsg "Compressing sysbench logs and downloading.."
            LogMsg "SYSBENCH COMMAND : ./sys-custom.sh -CleanUp yes -CustomLogDir $SysbenchLogDir -fileSize $($SysbenchConfigObject.fileSize) -testIO $io -testMode $mode -testThread $thread -CustomLogDir $SysbenchLogDir" -Path "$($VMObject.LogDir)\InvokeSys.sh"
            $SysbenchLogTarBall = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "tar -cvzf SysBenchLogs.tar.gz $SysbenchLogDir/*.txt"
            RemoteCopy -downloadFrom $VMObject.VIP -port $VMObject.SSHPort -files "SysBenchLogs.tar.gz" -username $VMObject.username -password $VMObject.password -download -downloadTo $LogDir
            LogMsg "$($SysBenchTests - $SysBenchErrors) out of $SysBenchTests sysbench tests completed successfully."
            if ( $SysBenchErrors -eq 0 )
            {
                $ExitCode = "PASS"
            }
            else
            {
                LogErr "$SysBenchErrors out of $TotalSysBenchTests sysbench tests failed."
                $ExitCode = "FAIL"
            }
        }
        else
        {
            LogErr "FAILED TO PREPARE FILES FOR SYSBENCH. ABORTING TEST. $SysBenchErrors out of $TotalSysBenchTests sysbench tests aborted."
            $ExitCode = "ABORTED"
        }
        
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
        $ExitCode = "ABORTED"
    }

return $ExitCode
}
Function UpgradeKernel($VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting Test : $metaData"
        $dmesgBeforeUpgrade = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg"
        Set-Content -Value $dmesgBeforeUpgrade -Path "$($VMObject.LogDir)\dmesgBeforeKernelUpgrade.txt"
        $unameBeforeUpgrade = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "uname -r"
        $dmesgBeforeUpgrade = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg"
        $UpdateConsole = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "./packageInstaller.sh -update yes" -runAsSudo
        Set-Content -Value $UpdateConsole -Path "$($VMObject.LogDir)\UpdateConsoleOutput.txt"
        $dmesgafterUpgrade = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "dmesg"
        $unameAfterUpgrade = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "uname -r"
        Set-Content -Value $dmesgAfterUpgrade -Path "$($VMObject.LogDir)\dmesgAfterKernelUpgrade.txt"
        if ( $unameBeforeUpgrade -eq $unameAfterUpgrade )
        {
            LogMsg "No update available for Kernel version : $unameBeforeUpgrade."
            $ExitCode = "PASS"
        }
        else
        {
            LogMsg "Kernel upgraded from : $unameBeforeUpgrade to $unameAfterUpgrade."
            $ExitCode = "PASS"
        }
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}
Function VerifyRaidDiskFunctional($VMObject, $PrevTestStatus, $metaData, $RaidName, $RaidMountPoint)
{
#We don't need to write separate code here, just use VerifyIO function with Raid Mount directory.
    if ( $PrevTestStatus -eq "PASS" )
    {
        $ExitCode = VerifyIO -VMObject $VMObject -NewAttachedDiskName $RaidName -PrevTestStatus $PrevTestStatus -metaData $metaData -mountPoint $RaidMountPoint -AlreadyMounted
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

Function UninstallLIS($VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting test : $metaData"
        $rpmqa = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "rpm -qa"
        $modulesRemoved = 0
        foreach ( $module in $rpmqa.Split("`n"))
        {
            if ( $module -imatch "microsoft-hyper")
            {
                LogMsg "Removing $module.."
                $modureRemoved = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "rpm -e $module" -runAsSudo -runMaxAllowedTime 1200
                $modulesRemoved += 1
                LogMsg "Removed $module.."
            }
        }

        if($modulesRemoved -gt 0)
        {
            #Reboot VM..
            $RebootStatus = RetryOperation -operation { Get-AzureService -ServiceName $VMObject.ServiceName | Get-AzureVM | Restart-AzureVM } -description "Rebooting VM..."
            if ( $RebootStatus.OperationStatus -eq "Succeeded")
            { 
                if (( VerifyAllDeployments -servicesToVerify $VMObject.ServiceName ) -eq "True")
                {
                    if ( ( isAllSSHPortsEnabled -DeployedServices $VMObject.ServiceName ) -eq "True" )
                    {

                        #Verify LIS Version
                        $rpmqa = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "rpm -qa"
                        $modulesDetected = 0
                        foreach ( $module in $rpmqa.Split("`n"))
                        {
                            if ( $module -imatch "microsoft-hyper")
                            {
                                LogErr "Detected $module.."
                                $modulesDetected += 1
                            }
                        }
                        if ( $modulesDetected -eq 0 )
                        {
                            LogMsg "$modulesRemoved HyperV modules removed."
                            $ExitCode = "PASS"
                        }
                        else
                        {
                            LogErr "Hyper V modules still visible in VM"
                            $ExitCode = "FAIL"
                        }
                    }
                    else
                    {
                        LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                        $ExitCode = "ABORTED"
                    }
                }
                else
                {
                    LogErr "VM is not accessible after reboot. Further Tests will be aborted."
                    $ExitCode = "ABORTED"
                }
            }
            else
            {
                LogErr "Failed to reboot. Further Tests will be aborted."
                $ExitCode = "ABORTED"
            }
        }
        else
        {
            #Nothing removed
        }
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}
Function ReinstallLIS($VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        $UninstallLIS = UninstallLIS -VMObject $VMObject -PrevTestStatus "PASS" -metaData "Uninstalling LIS."
        $ExitCode = InstallLIS -VMObject $VMObject -PrevTestStatus $UninstallLIS -metaData "Reinstalling LIS"
    }
    elseif ( $PrevTestStatus -eq "FAIL" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous failed test"
    }
    elseif ( $PrevTestStatus -eq  "ABORTED" )
    {
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

Function PreareVMForLIS4Test ($VMObject, $DetectedDistro)
{
    #This test needs sysbench, sysstat and mdadm packages to work correctly.
    if ( $DetectedDistro -imatch "CENTOS" )
    {
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "yum install --nogpgcheck -y ./epel-release-7-5.noarch.rpm " -runAsSudo
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "yum install --nogpgcheck -y sysstat" -runAsSudo
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "yum install --nogpgcheck -y mdadm" -runAsSudo
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "yum install --nogpgcheck -y sysbench" -runAsSudo
    }
    if ( $DetectedDistro -imatch "UBUNTU" )
    {
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "apt-get install --force-yes -y sysstat" -runAsSudo
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "apt-get install --force-yes -y mdadm" -runAsSudo
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "apt-get install --force-yes -y sysbench" -runAsSudo
    }
}
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
    #Get VMs deployed in the service..
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
    $VMObject = CreateTestVMNode -ServiceName $isDeployed -VIP $hs1VIP -SSHPort $hs1vm1sshport -username $user -password $password -DNSUrl $hs1ServiceUrl -logDir $LogDir
    $DetectedDistro = DetectLinuxDistro -VIP $hs1VIP -SSHport $hs1vm1sshport -testVMUser $user -testVMPassword $password
    RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
    $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.VIP -port $VMObject.SSHPort -command "chmod +x *.sh" -runAsSudo
    
    PreareVMForLIS4Test -VMObject $VMObject -DetectedDistro $DetectedDistro
    
    $testResult = "PASS"
	foreach ($TestID in $SubtestValues) 
	{
		try
		{
            #Make $testResult = $Null
            $PrevTestResult = $testResult
            $testResult = $null
            switch ($TestID.Trim())
            {
             "manual" #Do manual work if necessory.
                {
                    LogMsg "Manual override started.."
                    $ManualWork = $null
                    While ( !$ManualWork )
                    {
                        $ManualWork = Read-Host -Prompt "Please tell, what you are trying to do in one line"
                    }
                    $metaData = $ManualWork
                    LogMsg "Please complete your manual work."
                    LogMsg "ssh $user@$hs1ServiceUrl -p $hs1vm1sshport"
                    $isManaulWorkDone = $null
                    While ( !( $isManaulWorkDone -eq "YES" ) -and !( $isManaulWorkDone -eq "NO" ) )
                    {
                        $isManaulWorkDone = Read-Host -Prompt "Did you finished your work? [YES/NO]"
                    }
                    if ( $isManaulWorkDone -eq "YES" )
                    {
                        $ProceedForAutomation = $null
                        While ( !( $ProceedForAutomation -eq "YES" ) -and !( $ProceedForAutomation -eq "NO" ) )
                        {
                            $ProceedForAutomation = Read-Host -Prompt "Can Automation proceed? [YES/NO]"
                        }
                        if ( $ProceedForAutomation -eq "YES")
                        {
                            $testResult = "PASS"
                        }
                        else
                        {
                            $StopAutomationReason = $null
                            While ( !$StopAutomationReason )
                            {
                                $StopAutomationReason = Read-Host -Prompt "Please tell, why automation should stop in one line."
                            }
                            $testResult = "FAIL"
                        }
                    }
                    else
                    {
                        $manualWorkNotDoneReason = $null
                        While ( !$manualWorkNotDoneReason )
                        {
                            $manualWorkNotDoneReason = Read-Host -Prompt "Please tell, why manual work is not completed in one line."
                        }
                        $testResult = "ABORTED"
                    }
                }
             "TestID1" #Deploy and Verify attached disks.
                {
                    $metaData = "Deploy and Verify attached disks"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $VerifyPreAttachedDisksResult = VerifyAttachedDisks -VMObject $VMObject -PrevTestStatus "PASS" -metaData $metaData
                    $testResult = $VerifyPreAttachedDisksResult[0]
                    $PreAttachedDisks = $VerifyPreAttachedDisksResult[1]
                }
            "TestID2" #Install LIS4
                {
                    $metaData = "Pass1 - Install LIS4"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    if ( $DetectedDistro -imatch "CENTOS" )
                    {
                        $testResult = InstallLIS -VMObject $VMObject -PrevTestStatus $PrevTestResult  -metaData $metaData
                    }
                    else
                    {
                        LogMsg "Skipping LIS installation for $DetectedDistro"
                        $testResult = "PASS"
                    }
                }
            "TestID3" #Attach another data disk 
                {
                    $metaData = "Pass1 - Attach another data disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $AttachAnotherDiskResult = AttachAnotherDataDisk -VMObject $VMObject -DiskSizeInGB $currentTestData.dataDiskConfig.DiskSizeInGB -DiskHostCaching $currentTestData.dataDiskConfig.HostCaching -PrevTestStatus $PrevTestResult -metaData $metaData
                    $testResult = $AttachAnotherDiskResult[0]
                    $diskAttachedToLun = $AttachAnotherDiskResult[2]
                    $newAttachedDiskName = $AttachAnotherDiskResult[1]

                }
            "TestID4" #Verify single data disk IO functional
                {
                    $metaData = "Pass1 - Verify IO on single disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = VerifyIO -PrevTestStatus $PrevTestResult  -VMObject $VMObject -DiskMountPoint "/mnt/datadisk" -NewAttachedDiskName $newAttachedDiskName -metaData $metaData
                }
            "TestID5" #Detach data disk
                {
                    $metaData = "Pass1 - Detach data disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = DetachDataDisk -VMObject $VMObject -LUN $diskAttachedToLun -PrevTestStatus $PrevTestResult -metaData $metaData
                }
            "TestID6" #Create RAID on devices
                {
                    $metaData = "Pass1 - Create Raid on Devices"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $RaidName = "/dev/md3"
                    $VerifyPreAttachedDisksResult = VerifyAttachedDisks -VMObject $VMObject -PrevTestStatus "PASS" -metaData $metaData
                    $PreAttachedDisks = $VerifyPreAttachedDisksResult[1]
                    $testResult = CreateRAIDOnDevices -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $VerifyPreAttachedDisksResult[0] -RaidName $RaidName -metaData $metaData
                }
            "TestID7" #Create RAID on partitions already formatted 
                {
                    $metaData = "Pass1 - Create Raid partition on prev.formatted disks"
                    $RaidName = "/dev/md2"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = CreateRAIDOnPartitionsAlreadyFormatted -VMObject $VMObject -PrevTestStatus $PrevTestResult -NewAttachedDiskNames $PreAttachedDisks -RaidName $RaidName -metaData $metaData
                }
            "TestID8" #Create RAID on partitions previously not formatted
                {
                    $metaData = "Pass1 - Create Raid partition on prev.NOT formatted disks"
                    $RaidName = "/dev/md1"
                    $RaidMountPoint = "/mnt/RaidVolume"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $RaidResult = CreateRAIDOnPartitionsNotFormatted -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $PrevTestResult -RaidName $RaidName -RaidMountPoint $RaidMountPoint -metaData $metaData -DoNotStopRaid
                    $testResult = $RaidResult
                }
            "TestID9" #Run sysbench IO test on RAID volume
                {
                    $metaData = "Pass1 - Sysbench"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = RunSysBench -VMObject $VMObject -PrevTestStatus $PrevTestResult -TestDirectory $RaidMountPoint -SysbenchConfigObject $currentTestData.sysbenchConfig -metaData $metaData
                    if ( $PrevTestResult -ne "ABORTED" )
                    {
                        $out = StopRaidArry -VMObject $VMObject -RaidName $RaidName
                    }
                }
            "TestID10" # Upgrade kernel
                {
                    $metaData = "Pass1 - Upgrade kernel"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = UpgradeKernel -VMObject $VMObject -PrevTestStatus $PrevTestResult -metaData $metaData
                }
            "TestID11" # Verify RAID/disks functional
                {
                    $RaidName = "/dev/md1"
                    $RaidMountPoint = "/mnt/RaidVolume"
                    $metaData = "Pass1 - Verify Raid After Kernel Upgrade"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = VerifyRaidDiskFunctional -VMObject $VMObject -PrevTestStatus $PrevTestResult -RaidName $RaidName -RaidMountPoint $RaidMountPoint -metaData $metaData
                }
            "TestID12" # Re-install LIS4
                {
                    $metaData = "Pass1 - Re-install LIS"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    if ( $DetectedDistro -imatch "CENTOS" )
                    {
                        $testResult = ReinstallLIS -VMObject $VMObject -PrevTestStatus $PrevTestResult -metaData $metaData
                    }
                    else
                    {
                        $testResult = "PASS"
                    }
                }
            "TestID13" #Attach another data disk 
                {
                    $metaData = "Pass2 - Attach another data disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $AttachAnotherDiskResult = AttachAnotherDataDisk -VMObject $VMObject -DiskSizeInGB $currentTestData.dataDiskConfig.DiskSizeInGB -DiskHostCaching $currentTestData.dataDiskConfig.HostCaching -PrevTestStatus $PrevTestResult -metaData $metaData
                    $testResult = $AttachAnotherDiskResult[0]
                    $diskAttachedToLun = $AttachAnotherDiskResult[2]
                    $newAttachedDiskName = $AttachAnotherDiskResult[1]

                }
            "TestID14" #Verify single data disk IO functional
                {
                    $metaData = "Pass2 - Verify IO on single disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = VerifyIO -PrevTestStatus $PrevTestResult  -VMObject $VMObject -DiskMountPoint "/mnt/datadisk" -NewAttachedDiskName $newAttachedDiskName -metaData $metaData
                }
            "TestID15" #Detach data disk
                {
                    $metaData = "Pass2 - Detach data disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = DetachDataDisk -VMObject $VMObject -LUN $diskAttachedToLun -PrevTestStatus $PrevTestResult -metaData $metaData
                }
            "TestID16" #Create RAID on devices
                {
                    $metaData = "Pass2 - Create Raid on Devices"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $RaidName = "/dev/md3"
                    $VerifyPreAttachedDisksResult = VerifyAttachedDisks -VMObject $VMObject -PrevTestStatus "PASS" -metaData $metaData
                    $PreAttachedDisks = $VerifyPreAttachedDisksResult[1]
                    $testResult = CreateRAIDOnDevices -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $VerifyPreAttachedDisksResult[0] -RaidName $RaidName -metaData $metaData
                }
            "TestID17" #Create RAID on partitions already formatted 
                {
                    $metaData = "Pass2 - Create Raid partition on prev.formatted disks"
                    $RaidName = "/dev/md2"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = CreateRAIDOnPartitionsAlreadyFormatted -VMObject $VMObject -PrevTestStatus $PrevTestResult -NewAttachedDiskNames $PreAttachedDisks -RaidName $RaidName -metaData $metaData
                }
            "TestID18" #Create RAID on partitions previously not formatted
                {
                    $metaData = "Pass2 - Create Raid partition on prev.NOT formatted disks"
                    $RaidName = "/dev/md1"
                    $RaidMountPoint = "/mnt/RaidVolume"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $RaidResult = CreateRAIDOnPartitionsNotFormatted -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $PrevTestResult -RaidName $RaidName -RaidMountPoint $RaidMountPoint -metaData $metaData -DoNotStopRaid
                    $testResult = $RaidResult
                }
            "TestID19" #Run sysbench IO test on RAID volume
                {
                    $metaData = "Pass2 - Sysbench"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = RunSysBench -VMObject $VMObject -PrevTestStatus $PrevTestResult -TestDirectory $RaidMountPoint -SysbenchConfigObject $currentTestData.sysbenchConfig -metaData $metaData
                    if ( $PrevTestResult -ne "ABORTED" )
                    {
                        $out = StopRaidArry -VMObject $VMObject -RaidName $RaidName
                    }
                }            
            "TestID20" # Re-install LIS4
                {
                    $metaData = "Pass2 - Re-install LIS"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    if ( $DetectedDistro -imatch "CENTOS" )
                    {
                        $testResult = ReinstallLIS -VMObject $VMObject -PrevTestStatus $PrevTestResult -metaData $metaData
                    }
                    else
                    {
                        $testResult = "PASS"
                    }
                }
            "TestID21" #Attach another data disk 
                {
                    $metaData = "Pass3 - Attach another data disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $AttachAnotherDiskResult = AttachAnotherDataDisk -VMObject $VMObject -DiskSizeInGB $currentTestData.dataDiskConfig.DiskSizeInGB -DiskHostCaching $currentTestData.dataDiskConfig.HostCaching -PrevTestStatus $PrevTestResult -metaData $metaData
                    $testResult = $AttachAnotherDiskResult[0]
                    $diskAttachedToLun = $AttachAnotherDiskResult[2]
                    $newAttachedDiskName = $AttachAnotherDiskResult[1]

                }
            "TestID22" #Verify single data disk IO functional
                {
                    $metaData = "Pass3 - Verify IO on single disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = VerifyIO -PrevTestStatus $PrevTestResult  -VMObject $VMObject -DiskMountPoint "/mnt/datadisk" -NewAttachedDiskName $newAttachedDiskName -metaData $metaData
                }
            "TestID23" #Detach data disk
                {
                    $metaData = "Pass3 - Detach data disk"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = DetachDataDisk -VMObject $VMObject -LUN $diskAttachedToLun -PrevTestStatus $PrevTestResult -metaData $metaData
                }
            "TestID24" #Create RAID on devices
                {
                    $metaData = "Pass3 - Create Raid on Devices"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $RaidName = "/dev/md3"
                    $VerifyPreAttachedDisksResult = VerifyAttachedDisks -VMObject $VMObject -PrevTestStatus "PASS" -metaData $metaData
                    $PreAttachedDisks = $VerifyPreAttachedDisksResult[1]
                    $testResult = CreateRAIDOnDevices -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $VerifyPreAttachedDisksResult[0] -RaidName $RaidName -metaData $metaData
                }
            "TestID25" #Create RAID on partitions already formatted 
                {
                    $metaData = "Pass3 - Create Raid partition on prev.formatted disks"
                    $RaidName = "/dev/md2"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = CreateRAIDOnPartitionsAlreadyFormatted -VMObject $VMObject -PrevTestStatus $PrevTestResult -NewAttachedDiskNames $PreAttachedDisks -RaidName $RaidName -metaData $metaData
                }
            "TestID26" #Create RAID on partitions previously not formatted
                {
                    $metaData = "Pass3 - Create Raid partition on prev.NOT formatted disks"
                    $RaidName = "/dev/md1"
                    $RaidMountPoint = "/mnt/RaidVolume"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $RaidResult = CreateRAIDOnPartitionsNotFormatted -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $PrevTestResult -RaidName $RaidName -RaidMountPoint $RaidMountPoint -metaData $metaData -DoNotStopRaid
                    $testResult = $RaidResult
                }
            "TestID27" #Run sysbench IO test on RAID volume
                {
                    $metaData = "Pass3 - Sysbench"
                    mkdir "$LogDir\$metaData" -Force | Out-Null
                    $VMObject.LogDir = "$LogDir\$metaData"
                    $testResult = RunSysBench -VMObject $VMObject -PrevTestStatus $PrevTestResult -TestDirectory $RaidMountPoint -SysbenchConfigObject $currentTestData.sysbenchConfig -metaData $metaData
                    if ( $PrevTestResult -ne "ABORTED" )
                    {
                        $out = StopRaidArry -VMObject $VMObject -RaidName $RaidName
                    }
                }
            }
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
			$resultSummary +=  CreateResultSummary -testResult $testResult -metaData "$TestID : $metaData" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
		}   
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
return $result,$resultSummary