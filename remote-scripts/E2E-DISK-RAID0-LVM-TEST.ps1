<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$LinuxDistro=""
#Define Total LUNS according to VM size.
$SmallVMLUNs = 2
$MediumVMLUNs = 4
$LargeVMLUNs = 8
$ExtraLargeVMLUNs= 16
$DiskType=$($currentTestData.DiskType)
$DiskFormat=$($currentTestData.DiskFormat)
$MountDir='/data'

Function RebootVMandVerifyMount()
{
	$temp = RetryOperation -operation { Restart-AzureVM -ServiceName $hs1vm1.ServiceName -Name $hs1vm1.Name -Verbose } -description "Restarting VM.." -maxRetryCount 10 -retryInterval 5
	if ( $temp.OperationStatus -eq "Succeeded" )
	{
		LogMsg "Restarted Successfully"
		if ((isAllSSHPortsEnabled -DeployedServices $testVMsinService.DeploymentName) -imatch "True")
		{
			$mountstatus =RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mount -l" -runAsSudo #2>&1 | Out-Null 
			if( $mountstatus -imatch "$MountDir")
			{
				LogMsg "Found the mount point successfully"
				return $true
			}
			else
			{
				LogErr "Mount point not found"
				return $false
			}
		}
	}
	else
	{
		Throw "Failed to restart the VM"
		$testResult = "Aborted"
	}
}

foreach ($newSetupType in $currentTestData.SubtestValues)
{
	try
	{
		#Deploy A new VM..
		$isDeployed = DeployVMS -setupType $newSetupType -Distro $Distro -xmlConfig $xmlConfig
		
		#Start Test if Deployment is successfull.
		if ($isDeployed)
		{
			$testServiceData = Get-AzureService -ServiceName $isDeployed
			#Add-Member -InputObject $diskResult -MemberType MemberSet -Name $newSetupType
			#Get VMs deployed in the service..
			$testVMsinService = $testServiceData | Get-AzureVM
			$hs1vm1 = $testVMsinService
			$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
			$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
			$hs1VIP = $hs1vm1Endpoints[0].Vip
			$hs1ServiceUrl = $hs1vm1.DNSName
			$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
			$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
			$hs1vm1InstanceSize = $hs1vm1.InstanceSize
			$testVMObject = CreateHotAddRemoveDataDiskNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -ServiceName $isDeployed -logDir "$LogDir\$newSetupType" -InstanceSize $hs1vm1InstanceSize
			mkdir "$LogDir\$newSetupType"
			RemoteCopy -uploadTo $testVMObject.ip -port $testVMObject.sshPort -files $currentTestData.files -username $testVMObject.user -password $testVMObject.password -upload 2>&1 | Out-Null
			$LinuxDistro=DetectLinuxDistro -VIP $hs1VIP -SSHport $hs1vm1sshport -testVMUser $user -testVMPassword $password
			
			if($LinuxDistro -imatch "UBUNTU")
			{
				RemoteCopy -uploadTo $testVMObject.ip -port $testVMObject.sshPort -files .\remote-scripts\Packages\iozone3_308-1_amd64.deb,.\remote-scripts\Packages\mdadm_3.3-2ubuntu1_amd64.deb -username $testVMObject.user -password $testVMObject.password -upload 2>&1 | Out-Null
			}
			elseif($LinuxDistro -imatch "SUSE" -or "SLES")
			{
				RemoteCopy -uploadTo $testVMObject.ip -port $testVMObject.sshPort -files .\remote-scripts\Packages\iozone-3.424-2.el6.rf.x86_64.rpm,.\remote-scripts\Packages\mdadm-3.3-4.8.1.x86_64.rpm -username $testVMObject.user -password $testVMObject.password -upload 2>&1 | Out-Null
							
			}
			elseif($LinuxDistro -imatch "CENTOS" -or "EULEROS" -or "REDHAT" -or "ORACLE" -or "RHEL")
			{
				RemoteCopy -uploadTo $testVMObject.ip -port $testVMObject.sshPort -files .\remote-scripts\Packages\iozone-3.424-2.el6.rf.x86_64.rpm,.\remote-scripts\Packages\mdadm-3.2.6-31.el7.x86_64.rpm -username $testVMObject.user -password $testVMObject.password -upload 2>&1 | Out-Null
			}
			switch ($hs1vm1.InstanceSize)
			{
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

			#getting the list of available disks before adding new disks
			RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "fdisk -l | grep 'Disk.*/dev/sd[a-z]' |awk  '{print `$2}' | sed s/://| sort >beforedisk.list" -runAsSudo 2>&1 | Out-Null
			
			try
			{
				$testCommand = "DoHotAddNewDataDiskTestParallel -testVMObject `$testVMObject -TotalLuns `$testLUNs"
				
				$testResult = Invoke-Expression $testCommand
				
				$out=RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "fdisk -l | grep 'Disk.*/dev/sd[a-z]' |awk  '{print `$2}' | sed s/://| sort >afterdisk.list" -runAsSudo
				$disks_attached	= RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "diff beforedisk.list afterdisk.list | grep '/dev/'| wc -l" -runAsSudo 
				write-host "disk attach: $disks_attached"
				if ($disks_attached)
				{
					#Create a RAID0 or LVM with the 4 data disks 
					try
					{
						$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "python $($currentTestData.testScript) -f $DiskFormat -g $DiskType -m $MountDir" -runAsSudo -ignoreLinuxExitCode 2>&1 | Out-Null
						RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/test_result.txt" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password 2>&1 | Out-Null
						try{
							$out = Select-String -Simple "PASS"  $LogDir\test_result.txt
							if($out){
								LogMsg "$DiskType disk created successfully"
								
								if(RebootVMandVerifyMount)
								{
									try{
										LogMsg "OZONE TEST : Started .."
										$IOZoneoutput = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "iozone -f $MountDir/iozone.tmp -a -z -g 500m -k 16 -Vazure > iozoneOuput.txt" -runAsSudo -runmaxallowedtime 6000 -ignoreLinuxExitCode #2>&1 | Out-Null
										RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/iozoneOuput.txt" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password 2>&1 | Out-Null
										
										$iozonestatus = Select-String -Simple "iozone test complete"  $LogDir\iozoneOuput.txt
										if($iozonestatus)
										{
											LogMsg "successfully Completed IOZONE TEST"
											if(RebootVMandVerifyMount)
											{
												$testResult = "PASS"
												RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/logs.tar.gz " -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password 2>&1 | Out-Null
											}
											else
											{
												$testResult = "FAIL"
											}
										}
										else
										{
											LogErr "IOZONE TEST FAILED" 
											$testResult = "FAIL"
										}
									}catch{
										LogErr "IOZONE TEST FAILED"
										$testResult="FAIL"
									}
								}
								else
								{
									$testResult = "FAIL"
								}
							}else{
								LogErr "$DiskType disk creation failed"
								$testResult="FAIL"
							}
						}catch{
							LogErr "$DiskType disk creation failed"
							$testResult="FAIL"
						} 	
					}
					catch
					{
						LogErr "Exception in $DiskType DISK Creation"
						$testResult = "FAIL" 
					}
				}
				else
				{
					$testResult = "FAIL"
					LogErr "Disk Attachments Failed" 
				}
			}
			catch
			{
				$ErrorMessage =  $_.Exception.Message
				LogMsg "EXCEPTION : $ErrorMessage" 
				$testResult = "FAIL"
			}
		}
		else
		{
			$testResult = "Aborted"
			$resultArr += $testResult
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
			$resultArr += $testResult
		}
	}
	$resultArr += $testResult
	$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
}
$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result
