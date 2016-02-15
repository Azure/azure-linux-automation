Function CreateTestVMNode
{
	param(
            [string] $ServiceName,
            [string] $RoleName,
			[string] $PublicIP,
			[string] $SSHPort,
			[string] $username,
			[string] $password,
			[string] $InternalIP,
			[string] $URL,
			[string] $logDir )


	$objNode = New-Object -TypeName PSObject
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name ServiceName -Value $ServiceName -Force
    Add-Member -InputObject $objNode -MemberType NoteProperty -Name RoleName -Value $RoleName -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name PublicIP -Value $PublicIP -Force 
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name SSHPort -Value $SSHPort -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name username -Value $username -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name password -Value $password -Force
	Add-Member -InputObject $objNode -MemberType NoteProperty -Name InternalIP -Value $nodeInternalIP -Force
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
        $fdiskAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "$fdisk -l" -runAsSudo
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

Function GetKernelLogs ($VMObject)
{
    $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "dmesg > dmesg.txt" -runAsSudo
    RemoteCopy -downloadFrom $VMObject.PublicIP -port $VMObject.SSHPort -files "dmesg.txt" -username $VMObject.username -password $VMObject.password -download -downloadTo $VMObject.LogDir
    $dmesg = Get-Content -Path "$($VMObject.LogDir)\dmesg.txt"
    Remove-Item -Path "$($VMObject.LogDir)\dmesg.txt" -Force | Out-Null
    return $dmesg
}

Function verifyStopVM($VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting Test : $metaData"
        $stopVMResult = RetryOperation -operation { Stop-AzureVM -ServiceName $VMObject.ServiceName -Name $VMObject.RoleName -StayProvisioned -Force -Verbose } -description "Stopping VM $($VMObject.RoleName)" -maxRetryCount 10 -retryInterval 10
        if($stopVMResult.OperationStatus = "Succeeded")
        {
            LogMsg "VM Stopped Successfully."
            $ExitCode = "PASS"            
        }
        else
        {
            LogErr "Failed to stop VM."
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

Function verifyRestartVM($VMObject, $PrevTestStatus, $metaData)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting Test : $metaData"
        $stopVMResult = RetryOperation -operation { Start-AzureVM -ServiceName $VMObject.ServiceName -Name $VMObject.RoleName -Verbose } -description "Starting VM $($VMObject.RoleName)" -maxRetryCount 10 -retryInterval 10
        if($stopVMResult.OperationStatus = "Succeeded")
        {
            LogMsg "VM Started Successfully."
            $sshStatus = RetryOperation -operation { Test-TCP -testIP $VMObject.PublicIP -testport $VMObject.SSHPort } -description "Checking if $($VMObject.RoleName) SSH port is available or not." -expectResult "True" -maxRetryCount 150 -retryInterval 2
            if ($sshStatus -eq "True")
            {
                LogMsg "SSH port is enabled."    
                $ExitCode = "PASS" 
            }
            else
            {
                LogErr "SSH port is NOT enabled."    
                $ExitCode = "FAIL" 
            }
                       
        }
        else
        {
            LogErr "Failed to stop VM."
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

Function VerifyIO($VMObject, $NewAttachedDiskName, $PrevTestStatus, $metaData, $mountPoint="/mnt/datadisk", [switch]$SkipCreatePartition, [switch]$AlreadyMounted, [switch]$DoNotUnmount)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\VerifyIO-$($NewAttachedDiskName.Replace('/','')).txt"
        $partitionNumber=$null
        $dmesgBefore = GetKernelLogs -VMObject $VMObject
        #Perform the steps ONLY IF $PrevTestStatus flag is set to "PASS"
        if ($AlreadyMounted )
        {
            LogMsg "$NewAttachedDiskName is already mounted to $mountPoint"
        }
        else
        {
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mkdir -p $mountPoint" -runAsSudo 
            if ( $SkipCreatePartition )
            {
                $FormatDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mkfs.ext4 $NewAttachedDiskName" -runAsSudo -runMaxAllowedTime 2400
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mount -o nobarrier $NewAttachedDiskName $mountPoint" -runAsSudo 
            }
            else
            {
                $partitionNumber=1
                $PartitionDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $NewAttachedDiskName -create yes -forRaid no" -runAsSudo 
                $FormatDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mkfs.ext4 $NewAttachedDiskName$partitionNumber" -runAsSudo -runMaxAllowedTime 2400 
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mount -o nobarrier $NewAttachedDiskName$partitionNumber $mountPoint" -runAsSudo 
                Add-Content -Value $formatDiskOut -Path $LogPath -Force
            }
        }
        $ddOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "dd if=/dev/zero bs=1024 count=1000000 of=$mountPoint/file_1GB" -runAsSudo -runMaxAllowedTime 1200
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
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "umount $mountPoint" -runAsSudo 
            }
            catch
            {
                LogMsg "umount failed. Trying umount -l"
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "umount -l $mountPoint" -runAsSudo 
            }
        }
        $dmesgAfter = GetKernelLogs -VMObject $VMObject
        $addedLines = (Compare-Object -ReferenceObject $dmesgBefore -DifferenceObject $dmesgAfter).InputObject
        if ($addedLines)
        {
            LogMsg "Kernel Logs : $($addedLines.Replace('[32m','').Replace('[0m[33m','').Replace('[0m',''))" -LinuxConsoleOuput
        }
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
        $fdiskBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "$fdisk -l" -runAsSudo
        $diskToRemove = RetryOperation -operation { Get-AzureVM -ServiceName  $VMObject.ServiceName | Get-AzureDataDisk -Lun $LUN } -description "Getting disk details from LUN : $LUN..."
        $RemoveDiskStatus = RetryOperation -operation { Get-AzureVM -ServiceName  $VMObject.ServiceName | Remove-AzureDataDisk -LUN $LUN | Update-AzureVM } -description "Removing data disk from LUN : $LUN..."
        $ExpectedDisks = (GetTotalPhysicalDisks -FdiskOutput $fdiskBefore)-1
        if ( $RemoveDiskStatus.OperationStatus -eq "Succeeded")
        {
            WaitFor -seconds 60
            $isVMAlive = RetryOperation -operation { Test-TCP -testIP $VMObject.PublicIP -testport $VMObject.SSHPort } -description "Checking availiblility of SSH port of VM $($VMObject.RoleName).." -expectResult "True" -maxRetryCount 100 -retryInterval 10
            if ( $isVMAlive -eq "True")
            {
                $DiskIsVisible = $true
                $maxTry = 10
                LogMsg 
                $out = RetryOperation -operation {$removeDisk = Remove-AzureDisk -DiskName $($diskToRemove.DiskName) -Verbose; return $removeDisk.OperationStatus} -description "Breaking link between $($diskToRemove.DiskName) and $($diskToRemove.MediaLink); " -retryInterval 10 -maxRetryCount 20 -expectResult "Succeeded"
                LogMsg "Checking inside VM.."
                while ( $DiskIsVisible -and ( $maxTry -gt 0 ))
                {
                    WaitFor -seconds 30
                    $maxTry -= 1
                    $fdiskAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "$fdisk -l" -runAsSudo
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
                LogErr "SSH port is not working after removing disk."
                $ExitCode = "FAIL"
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

Function CreatePartitionOnDisk ($VMObject, $diskName, $isItForRaid, $LogFilePath)
{
    $diskShortName = $diskName.Replace("/dev/","")
    $lsblkBefore = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "lsblk -a" -runAsSudo
    Add-Content -Value $lsblkBefore -Path $LogFilePath -Force
    $PartitionDetected = $false
    foreach ( $line in $lsblkBefore.Split("`n"))
    {
        $line = $line.Trim().Replace("├","").Replace("─","").Replace("└","").Replace("Γ","").Replace("ö","").Replace("Ç","").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ")
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
            $deletePartition = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $diskName -delete yes" -runAsSudo 
        }
        else
        {
            LogMsg "$diskName is mounted to $mountedTo. Trying to unmount"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "umount $mountedTo" -runAsSudo 
            $deletePartition = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $diskName -delete yes" -runAsSudo 
        }
        Add-Content -Value $deletePartition -Path $LogFilePath -Force
    }
    LogMsg "Creating the partition on $diskName"
    $PartitionDiskOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "./ManagePartitionOnDisk.sh -diskName $diskName -create yes -forRaid $isItForRaid" -runAsSudo 
    Add-Content -Value $PartitionDiskOut -Path $LogFilePath -Force
    $lsblkAfter = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "lsblk -a" 
    Add-Content -Value $lsblkAfter -Path $LogFilePath -Force
    $PartitionDetected = $false
    foreach ( $line in $lsblkAfter.Split("`n"))
    {
        $line = $line.Trim().Replace("├","").Replace("─","").Replace("└","").Replace("Γ","").Replace("ö","").Replace("Ç","").Replace('`-',"").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ")
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
    $formatOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mkfs -t $FileSystem $PartitionName" -runAsSudo -runMaxAllowedTime 10800
    Add-Content -Value $formatOut -Path $LogFilePath -Force
    return $true
}

Function StopRaidArry($VMObject, $RaidName)
{
    #Verify if raid is active
    $df = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "df").Split("`n")
    LogMsg "unmounting $RaidName, if any."
    foreach ( $line in $df )
    {
        if ( $line -imatch $RaidName )
        {
            $ActiveArray = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[0]
            $MountDir = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[5]
            LogMsg "Found mounted array : $ActiveArray mounted to $MountDir"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "umount $MountDir" -runAsSudo
        }
    }
    $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
    foreach ( $line in $mdStat )
    {
        if ( $line -imatch "active" )
        {
            $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split()[0]
            LogMsg "Found active arry : $ActiveArray"
            if ($line -imatch '/dev/')
            {
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
            }
            else
            {
                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mdadm --stop /dev/$ActiveArray" -runAsSudo
            }
        }
    }
}

Function CreateRAIDOnPartitionsNotFormatted($VMObject, $NewAttachedDiskNames, $PrevTestStatus , $metaData, $RaidName, $RaidMountPoint, [switch]$DoNotStopRaid)
{
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "STARTING TEST : $metaData"
        $LogPath = "$($VMObject.LogDir)\CreateRaidOnNotFormattedPartition.txt"
        $RaidDisks = $NewAttachedDiskNames.Split("^")
        foreach ($disk in $NewAttachedDiskNames.Split("^"))
        {
            $wipefs = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "wipefs -a $disk" -runAsSudo
            LogMsg $wipefs -LinuxConsoleOuput
            Add-Content -Value $wipefs -Path $LogPath -Force
        }
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
                    $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
                    foreach ( $line in $mdStat )
                    {
                        if ( $line -imatch "active" )
                        {
                            $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split()[0]
                            LogMsg "Found active arry : $ActiveArray"
                            if ($line -imatch '/dev/')
                            {
                                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
                            }
                            else
                            {
                                $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mdadm --stop /dev/$ActiveArray" -runAsSudo
                            }
                        }
                    }
                    Set-Content -Value "#!/bin/bash" -Path "$($VMObject.LogDir)\partprobe.sh" -Force
                    Add-Content -Value "partprobe -s" -Path "$($VMObject.LogDir)\partprobe.sh" -Force
                    Add-Content -Value "exit 0" -Path "$($VMObject.LogDir)\partprobe.sh" -Force
                    RemoteCopy -uploadTo $VMObject.PublicIP -port $VMObject.SSHPort -files "$($VMObject.LogDir)\partprobe.sh" -username $VMObject.username -password $VMObject.password -upload
                    Remove-Item -Path  "$($VMObject.LogDir)\partprobe.sh"
                    $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "chmod +x *.sh" -runAsSudo
                    $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "./partprobe.sh" -runAsSudo
                    $dmesgBefore = GetKernelLogs -VMObject $VMObject
                    $totalDisks = $NewAttachedDiskNames.Split("^").Count
                    LogMsg "Creating raid of $totalDisks disks."
                    LogMsg "Disks : $RaidPartitions"
                    $createRaidOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "./ManageRaid.sh -create yes -diskNames $($RaidPartitions.Replace(" ","^")) -totalDisks $totalDisks -RaidName $RaidName" -runAsSudo 
                    LogMsg $createRaidOut -LinuxConsoleOuput
                    Add-Content -Value $createRaidOut -Path $LogPath -Force
                    $formatRaid = FormatPartition -VMObject $VMObject -PartitionName $RaidName -FileSystem ext4 -LogFilePath "$LogDir\FormatRaid.txt"
                    LogMsg (Get-Content "$LogDir\FormatRaid.txt") -LinuxConsoleOuput
                    $Out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mkdir -p $RaidMountPoint" -runAsSudo 
                    $Out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mount -o nobarrier $RaidName $RaidMountPoint" -runAsSudo 
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
    $psef = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "ps -ef"
    $foundProcesses = 0
    foreach ( $line in $psef.Split("`n"))
    {
        if (( $line -imatch $ProcessName) -and !( $line -imatch "--color=auto"))
        {
            $foundProcesses += 1
            $linuxUID = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[0]
            $linuxPID = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[1]
            $linuxPPID = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[2]
            $linuxC = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[3]
            $linuxSTIME = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[4]
            $linuxTTY = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[5]
            $linuxTIME = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[6]
            $linuxCMD = $line.Trim().Replace("$linuxUID","").Replace("$linuxPID","").Replace("$linuxPPID","").Replace("$linuxC","").Replace("$linuxSTIME","").Replace("$linuxTTY","").Replace("$linuxTIME","").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ")
            LogMsg "FOUND PROCESS : UID=$linuxUID, PID=$linuxPID, RUNNING TIME=$linuxTIME, COMMAND=$linuxCMD"
        }
    }
    return $foundProcesses
}

Function VerifyRaidDiskFunctional($VMObject, $PrevTestStatus, $metaData, $RaidName, $RaidMountPoint)
{
#We don't need to write separate code here, just use VerifyIO function with Raid Mount directory.
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting test $metaData"
        $ExitCode = VerifyIO -VMObject $VMObject -NewAttachedDiskName $RaidName -PrevTestStatus $PrevTestStatus -metaData $metaData -mountPoint $RaidMountPoint -SkipCreatePartition -AlreadyMounted
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

Function AttachDiskToAnotherVM($diskMediaLink, $PrevTestStatus, $metaData, $tempVMSize)
{
#We don't need to write separate code here, just use VerifyIO function with Raid Mount directory.
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting test $metaData"
        LogMsg "Deploying a temporary VM.."
        $oldVMData = $allVMData
        $tempVM = DeployVMS -setupType $tempVMSize -Distro $Distro -xmlConfig $xmlConfig
        #$tempVM = "ICA-HS-SmallVM-U1404-9-23-18-48-58"
        if ($tempVM)
        {
            $allVMData = GetAllDeployementData -DeployedServices $tempVM
            $tempVM = $allVMData
            $fdiskBefore = RunLinuxCmd -username $user -password $password -ip $tempVM.PublicIP -port $tempVM.SSHPort -command "$fdisk -l" -runAsSudo
            $attachDiskStatus = RetryOperation -operation { Get-AzureVM -ServiceName $tempVM.ServiceName | Add-AzureDataDisk -ImportFrom -MediaLocation $diskMediaLink -LUN 0 -DiskLabel "TempDisk" -HostCaching ReadOnly | Update-AzureVM } -description "Attaching data disk $diskMediaLink to $($tempVM.ServiceName)"
            if ($attachDiskStatus.OperationStatus -eq "Succeeded")
            {
                LogMsg "New Disk attached successfully"
                $retryCount = 0
                $maxRetryCount = 20
                $diskNotDetected = $true
                while ($diskNotDetected -and ($retryCount -lt $maxRetryCount))
                {
                    $fdiskAfter = RunLinuxCmd -username $user -password $password -ip $tempVM.PublicIP -port $tempVM.SSHPort -command "$fdisk -l" -runAsSudo
                    if ( ( ( GetTotalPhysicalDisks -FdiskOutput $fdiskBefore ) + 1) -eq ( ( GetTotalPhysicalDisks -FdiskOutput $fdiskAfter ) ) )
                    {
                        LogMsg "New Disk detected successfully"
                        $diskNotDetected = $false
                    }
                    else
                    {
                        $retryCount += 1
                    }
                }
                if ($diskNotDetected)
                {
                    LogErr "Disk not detected in VM. Aborting."
                    $ExitCode = "ABORTED"
                }
                else
                {
                    $newDisk = GetNewPhysicalDiskNames -FdiskOutputBeforeAddingDisk $fdiskBefore -FdiskOutputAfterAddingDisk $fdiskAfter 
                    $out = RunLinuxCmd -username $user -password $password -ip $tempVM.PublicIP -port $tempVM.SSHPort -command "mkdir -p /mnt/datadisk" -runAsSudo
                    $out = RunLinuxCmd -username $user -password $password -ip $tempVM.PublicIP -port $tempVM.SSHPort -command "mount -o nobarrier $newDisk`1 /mnt/datadisk" -runAsSudo
                    #RemoteCopy -uploadTo $tempVM.PublicIP -files "$LogDir\file_1GB.txt" -port $tempVM.SSHPort -username $user -password $password -upload
                    #$md5Out = RunLinuxCmd -username $user -password $password -ip $tempVM.PublicIP -port $tempVM.SSHPort -command "md5sum -c file_1GB.txt" -runAsSudo
                    $lsOut = RunLinuxCmd -username $user -password $password -ip $tempVM.PublicIP -port $tempVM.SSHPort -command "ls /mnt/datadisk" -runAsSudo
                    if ($lsOut -imatch "file_1GB")
                    {
                        $ExitCode = "PASS"
                        LogMsg "Data verified successfully"
                        $out = DeleteService -serviceName $tempVM.ServiceName

                    } 
                    else
                    {
                        $ExitCode = "FAIL"
                        LogErr "Data verification failed"
                        LogMsg "Deleting service but keeping $diskMediaLink."
                        $out = DeleteService -serviceName $tempVM.ServiceName -KeepDisks
                    }
                }
            }
            else
            {
                LogErr "Failed to attatch disk."
                $ExitCode = "ABORTED"
            }
            $allVMData = $oldVMData
        }
        else
        {
            LogErr "Failed to deploy temporary VM."
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
        $ExitCode = "ABORTED"
        LogMsg "Skipping TEST : $metaData due to previous Aborted test"
    }
return $ExitCode
}

Function WriteDataOnSingleDisk($VMObject, $diskName, $PrevTestStatus, $metaData)
{
    $ExitCode = "ABORTED"
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting test $metaData"
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mkdir -p /mnt/datadisk" -runAsSudo 
        $partitionName = CreatePartitionOnDisk -VMObject $VMObject -diskName $diskName -LogFilePath "$($VMObject.LogDir)\PartitionDisk.txt" -isItForRaid "no"
        if ($partitionName[0])
        {
            $mdStat = (RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "cat /proc/mdstat").Split("`n")
            foreach ( $line in $mdStat )
            {
                if ( $line -imatch "active" )
                {
                    $ActiveArray = $line.Trim().Replace(":","").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split()[0]
                    LogMsg "Found active arry : $ActiveArray"
                    if ($line -imatch '/dev/')
                    {
                        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mdadm --stop $ActiveArray" -runAsSudo
                    }
                    else
                    {
                        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mdadm --stop /dev/$ActiveArray" -runAsSudo
                    }
                }
            }
            $formatPartition = FormatPartition -VMObject $VMObject  -PartitionName $partitionName[1] -FileSystem "ext4" -LogFilePath "$($VMObject.LogDir)\FormatDisk.txt"
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "mount -o nobarrier $($partitionName[1]) /mnt/datadisk" -runAsSudo
            LogMSg "Writing a 1GB file on data disk.."
            $ddOut = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "dd if=/dev/zero bs=1024 count=1000000 of=/mnt/datadisk/file_1GB" -runAsSudo -runMaxAllowedTime 1200
            #LogMSg "Calculating MD5 of file.."
            #$Out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "md5sum /mnt/datadisk/file_1GB > file_1GB.txt" -runAsSudo -runMaxAllowedTime 1200
            #RemoteCopy -downloadFrom $VMObject.PublicIP -port $VMObject.SSHPort -files "file_1GB.txt" -username $user -password $password -download -downloadTo $LogDir
            $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "umount /mnt/datadisk" -runAsSudo
            $ExitCode = "PASS"
        }
        else
        {
            LogErr "Failed to format $diskName"
                                
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

Function DeallocateVM($VMObject, $PrevTestStatus, $metaData)
{
    $ExitCode = "ABORTED"
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting test $metaData"
        $DeallocateResult = RetryOperation -operation { $stopVM = Stop-AzureVM -Name $VMObject.RoleName -ServiceName $VMObject.ServiceName -Force -Verbose; return $stopVM.OperationStatus } -expectResult "Succeeded" -description "Deallocating VM $($VMObject.RoleName)" -maxRetryCount 10 -retryInterval 10
        if ($DeallocateResult -eq "Succeeded")
        {
            $ExitCode = "PASS"
            LogMsg "Deallocated successfully."
        }
        else
        {
            LogErr "Failed to deallocate"
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

Function RemoveDataDisks($VMObject, [switch]$oneByOne, [switch]$allAtOnce, $LUNs, [switch]$DeleteVHD, $PrevTestStatus, $metaData)
{
    $ExitCode = "ABORTED"
    if ( $PrevTestStatus -eq "PASS" )
    {
        LogMsg "Starting test $metaData"
        $fdiskBefore = RunLinuxCmd -username $user -password $password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "$fdisk -l" -runAsSudo

        if ($allAtOnce)
        {
            $removeDiskCommand = "Get-AzureVM -ServiceName $($VMObject.ServiceName) -Name $($VMObject.RoleName)"
            foreach ($LUN in $LUNs)
            {
                $removeDiskCommand += " | Remove-AzureDataDisk -LUN $LUN -DeleteVHD"
            }
            $removeDiskCommand += " | Update-AzureVM -Verbose"
        }
        $removeDiskResult = RetryOperation -operation { $stopVM = Invoke-Expression -Command $removeDiskCommand ; return $stopVM.OperationStatus } -expectResult "Succeeded" -description "Removing $($LUNs.count) data disks from $($VMObject.RoleName)" -maxRetryCount 10 -retryInterval 10
        if ($removeDiskResult -eq "Succeeded")
        {
            WaitFor -seconds 10
            LogMsg "All Disks detached successfully."
            LogMsg "Checking if VM is alive or not..."
            $isVMAlive = RetryOperation -operation { Test-TCP -testIP $VMObject.PublicIP -testport $VMObject.SSHPort } -description "Checking availiblility of SSH port of VM $($VMObject.RoleName).." -expectResult "True" -maxRetryCount 100 -retryInterval 10
            if ( $isVMAlive -eq "True")
            {
                $retryCount = 0
                $maxRetryCount = 20
                $disksVisibleinVM = $true
                while ( $disksVisibleinVM -and ($retryCount -lt $maxRetryCount))
                {
                    $fdiskAfter = RunLinuxCmd -username $user -password $password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "$fdisk -l" -runAsSudo
                    $disksBefore = (GetTotalPhysicalDisks -FdiskOutput $fdiskBefore)
                    $disksAfter = ( GetTotalPhysicalDisks -FdiskOutput $fdiskAfter)
                    LogMsg "Disks Expected in VM : $($disksBefore - $LUNs.Count) "
                    LogMsg "Disks Visible in VM : $disksAfter"
                    if ( $disksAfter  -eq ( $disksBefore - $LUNs.Count) )
                    {
                        LogMsg "All disks removed from VM."
                        $disksVisibleinVM = $false
                    }
                }
                if ( $disksVisibleinVM )
                {
                    $ExitCode = "FAIL"
                    LogErr "$($disksAfter - ( $disksBefore - $LUNs.Count)) extra disks are still visible in VM."
                }
                else
                {
                    $ExitCode = "PASS"
                }
            }
            else
            {
                LogErr "SSH port is not working after removing data disks."
                $ExitCode = "FAIL"
            }            
        }
        else
        {
            LogErr "Failed to remove disks."
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

Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",") 
$FinalresultArr = @()
$FinalResult = ""
$RaidName = "/dev/md1"
$RaidMountPoint = "/mnt/RaidVolume"
foreach ($vmSize in $currentTestData.SubtestValues.Split(","))
{
    $result = ""
    $testResult = ""
    $resultArr = @()
    LogMsg "-=-=-=-=-=-=-=-=-=-=-=-=-="
    LogMsg "STARTING TESTS FOR $vmSize"
    $isDeployed = DeployVMS -setupType $vmSize -Distro $Distro -xmlConfig $xmlConfig
    #$isDeployed = "ICA-HS-D1V2DISK2-U1404-9-23-15-30-35"
    if($isDeployed)
    {
        $AllVMData = GetAllDeployementData -DeployedServices $isDeployed
		$hs1VIP = $AllVMData.PublicIP
		$hs1vm1sshport = $AllVMData.SSHPort
		$hs1ServiceUrl = $AllVMData.URL
		$hs1vm1InternalIP = $AllVMData.InternalIP
		$hs1vm1Hostname = $AllVMData.RoleName
        $VMObject = CreateTestVMNode -ServiceName $isDeployed -PublicIP $hs1VIP -SSHPort $hs1vm1sshport -username $user -password $password -URL $hs1ServiceUrl -logDir $LogDir -RoleName $hs1vm1Hostname -InternalIP $hs1vm1InternalIP
        RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
        $out = RunLinuxCmd -username $VMObject.username -password $VMObject.password -ip $VMObject.PublicIP -port $VMObject.SSHPort -command "chmod +x *.sh" -runAsSudo
        $testResult = "PASS"
	    foreach ($currentTask in $currentTestData.Tasks.Split(",")) 
	    {
		    try
		    {
                #Make $testResult = $Null
                $PrevTestResult = $testResult
                $testResult = $null
                switch ($currentTask.Trim())
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
                 "verifyAllDisks" #Deploy and Verify attached disks.
                    {
                        $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $VerifyPreAttachedDisksResult = VerifyAttachedDisks -VMObject $VMObject -PrevTestStatus "PASS" -metaData $metaData
                        $testResult = $VerifyPreAttachedDisksResult[0]
                        $PreAttachedDisks = $VerifyPreAttachedDisksResult[1]
                    }
                "verifyStopVM" #Install LIS4
                    {
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $testResult = verifyStopVM -VMObject $VMObject -PrevTestStatus $PrevTestResult  -metaData $metaData
                    }
                "verifyRestartVM" #Install LIS4
                    {
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $testResult = verifyRestartVM -VMObject $VMObject -PrevTestStatus $PrevTestResult  -metaData $metaData
                    }
                "verifyCreateRaid" #Create RAID on partitions previously not formatted
                    {
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $RaidResult = CreateRAIDOnPartitionsNotFormatted -VMObject $VMObject -NewAttachedDiskNames $PreAttachedDisks -PrevTestStatus $PrevTestResult -RaidName $RaidName -RaidMountPoint $RaidMountPoint -metaData $metaData -DoNotStopRaid
                        $testResult = $RaidResult
                    }
                "verifyRaidIO" # Verify RAID/disks functional
                    {
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $testResult = VerifyRaidDiskFunctional -VMObject $VMObject -PrevTestStatus $PrevTestResult -RaidName $RaidName -RaidMountPoint $RaidMountPoint -metaData $metaData
                        $out = StopRaidArry -VMObject $VMObject -RaidName $RaidName
                    }
                "WriteDataOnSingleDisk" # Verify RAID/disks functional
                    {
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $AttachedDiskLunCount = $PreAttachedDisks.Split("^").Count
                        $diskToRemove = RetryOperation -operation { Get-AzureVM -ServiceName  $VMObject.ServiceName | Get-AzureDataDisk -Lun ($AttachedDiskLunCount-1) } -description "Getting disk details from LUN : $($AttachedDiskLunCount-1)..."
                        $diskNameToRemove = $PreAttachedDisks.Split("^")[($AttachedDiskLunCount-1)]                        
                        foreach ($currentDiskName in $PreAttachedDisks.Split("^"))
                        {
                            LogMsg "Writing files on $currentDiskName"
                            $testResult = WriteDataOnSingleDisk -VMObject $VMObject -PrevTestStatus $PrevTestResult -diskName $currentDiskName  -metaData $metaData
                        }
                    }
                "DetachSingleDisk" #Run sysbench IO test on RAID volume
                    {
                        $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $testResult = DetachDataDisk -VMObject $VMObject -LUN ($AttachedDiskLunCount-1) -PrevTestStatus $PrevTestResult -metaData $metaData
                    }
                "verifyAttachDiskToAnotherVM" # Upgrade kernel
                    {
                        if ($vmSize -imatch "D1V2")
                        {
                            $tempVMSize = "D1V2"
                        }
                        elseif ($vmSize -imatch "D2V2")
                        {
                            $tempVMSize = "D2V2"
                        }
                        elseif ($vmSize -imatch "D3V2")
                        {
                            $tempVMSize = "D3V2"
                        }
                        elseif ($vmSize -imatch "D4V2")
                        {
                            $tempVMSize = "D4V2"
                        }
                        elseif ($vmSize -imatch "D5V2")
                        {
                            $tempVMSize = "D5V2"
                        }
                        elseif ($vmSize -imatch "D11V2")
                        {
                            $tempVMSize = "D11V2"
                        }
                        elseif ($vmSize -imatch "D12V2")
                        {
                            $tempVMSize = "D12V2"
                        }
                        elseif ($vmSize -imatch "D13V2")
                        {
                            $tempVMSize = "D13V2"
                        }
                        elseif ($vmSize -imatch "D14V2")
                        {
                            $tempVMSize = "D14V2"
                        }
                        $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $testResult = AttachDiskToAnotherVM -PrevTestStatus $PrevTestResult -metaData $metaData -diskMediaLink $diskToRemove.MediaLink -tempVMSize $tempVMSize
                    }
                "verifyDeallocateVM" # Upgrade kernel
                    {
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $testResult =  DeallocateVM -VMObject $VMObject -PrevTestStatus $PrevTestResult -metaData $metaData
                    }
                "verifyRootDisk" # Upgrade kernel
                    {
                       $metaData = "$vmSize $currentTask"
                        LogMsg "STARTING TEST : $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $testResult =  VerifyIO -VMObject $VMObject -NewAttachedDiskName "/dev/sda" -PrevTestStatus $PrevTestResult -metaData $metaData -mountPoint "/home/$user" -SkipCreatePartition -AlreadyMounted -DoNotUnmount
                    }
                "verifyRemoveDisks" # Upgrade kernel
                    {                        
                       $metaData = "$vmSize $currentTask"
                        mkdir "$LogDir\$metaData" -Force | Out-Null
                        $VMObject.LogDir = "$LogDir\$metaData"
                        $LUNs = @()
                        $dataDisks = Get-AzureVM -ServiceName $VMObject.ServiceName -Name $VMObject.RoleName | Get-AzureDataDisk -Verbose
                        foreach ($disk in $dataDisks)
                        {
                            $LUNs += $disk.Lun
                        }
                        $testResult = RemoveDataDisks -VMObject $VMObject -allAtOnce -LUNs $LUNs -DeleteVHD $PrevTestResult -metaData $metaData
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
			    $resultSummary +=  CreateResultSummary -testResult $testResult -metaData "$vmSize : $currentTask" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
		    }   
	    }
        $result = GetFinalResultHeader -resultarr $resultArr
        $FinalresultArr += $result
        DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -SkipVerifyKernelLogs
    }
    else
    {
	    $testResult = "Aborted"
        LogMsg "Skipping cleanup due to failed deployment."
	    $FinalresultArr += $testResult
        $resultSummary +=  CreateResultSummary -testResult $testResult -metaData "$vmSize : DeployVM" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
    }
    
}

#Clean up the setup
$FinalResult = GetFinalResultHeader -resultarr $FinalresultArr
#Return the result and summery to the test suite script..
return $FinalResult,$resultSummary