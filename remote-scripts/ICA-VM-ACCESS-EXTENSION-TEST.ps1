<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

$extnXML = [xml](Get-Content .\XML\Extensions.xml)
foreach ($extn in $extnXML.Extensions.Extension) 
{ 
	if($extn.Name -imatch "VMAccess")
	{
		$MyExtn = $extn
		LogMsg $MyExtn.Name
	}
}

$NewUser = $MyExtn.PrivateConfiguration.username
$passwd = $MyExtn.PrivateConfiguration.password
$newpassword = $MyExtn.NewPassword
$expiration = $MyExtn.PrivateConfiguration.Expiration
$PrivateConfig = ""
$PublicConfig = '{}'
$ExtensionName = $MyExtn.OfficialName
$Publisher = $MyExtn.Publisher
$Version =  $MyExtn.Version
$VersionForARM = $MyExtn.LatestVersion
$TaskType = ""
$LogFilesPaths = ""
$LogFiles = ""

if ( $UseAzureResourceManager )
{
	$ConfirmExtensionScriptBlock = {
		$ExtensionStatus = Get-AzureResource -OutputObjectFormat New -ResourceGroupName $isDeployed  -ResourceType "Microsoft.Compute/virtualMachines/extensions" -ExpandProperties
		if ( ($ExtensionStatus.Properties.ProvisioningState -eq "Succeeded") -and ( $ExtensionStatus.Properties.Type -eq $ExtensionName ) )
		{
			  LogMsg "$ExtensionName extension status is Succeeded in Properties.ProvisioningState"
			  $ExtensionVerfiedWithPowershell = $True
		}
		else
		{
			  LogErr "$ExtensionName extension status is Failed in Properties.ProvisioningState"
			  $ExtensionVerfiedWithPowershell = $False
		}
		return $ExtensionVerfiedWithPowershell
	}
}
else
{
	$ConfirmExtensionScriptBlock = {

	$vmDetails = Get-AzureVM -ServiceName $isDeployed
		if ( ( $vmDetails.ResourceExtensionStatusList.ExtensionSettingStatus.Status -eq "Success" ) -and ($vmDetails.ResourceExtensionStatusList.ExtensionSettingStatus.Name -imatch $ExtensionName ))
		{
			  $ExtensionVerfiedWithPowershell = $True
			  LogMsg "$ExtensionName extension status is SUCCESS in (Get-AzureVM).ResourceExtensionStatusList.ExtensionSettingStatus"
		}
		else
		{
			  $ExtensionVerfiedWithPowershell = $False
			  LogErr "$ExtensionName extension status is FAILED in (Get-AzureVM).ResourceExtensionStatusList.ExtensionSettingStatus"
		}
		return $ExtensionVerfiedWithPowershell
	}
}

Function VMAccessExtensionLog($user,$password)
{
	$varLogFolder = "/var/log/"
	$lsOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "ls -lR $varLogFolder"  -runAsSudo
	$folderToSearch = "/var/log/azure"
	foreach ($line in $lsOut.Split("`n") )
	{
		if ($line -imatch $varLogFolder)
		{
			$currentFolder = $line.Replace(":","")
		}
		if ( ( ($line.Split(" ")[0][0])  -eq "-" ) -and ($currentFolder -imatch $folderToSearch) )
		{
			$currentLogFile = $line.Trim().Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Replace("  "," ").Split(" ")[8]
			if ($LogFilesPaths)
			{
				$LogFilesPaths += "," + $currentFolder + "/" + $currentLogFile
				$LogFiles += "," + $currentLogFile
			}
			else
			{
				$LogFilesPaths = $currentFolder + "/" + $currentLogFile
				$LogFiles += $currentLogFile
			}
		}
	}
	return $LogFilesPaths,$LogFiles
}
Function VMAccessExtensionExecutionStatus($user,$password,$ExtensionType,$LogFilesPaths)
{
	if ($LogFilesPaths)
	{
		$ExtLog = $LogFilesPaths.split(",")[1]	   
		$extensionOutput = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $ExtLog" -runAsSudo
		if ( $extensionOutput -imatch "Succeeded in $ExtensionType" )
		{
			$ExtExecutionStatus = $True
		}
		else{
			$ExtExecutionStatus = $False
		}
	}
	else
	{
		LogErr "No Extension logs are available."
		$ExtExecutionStatus = $False
	}
	return $ExtExecutionStatus
}

Function VMAccessExtTest($TaskType)
{
	if($TaskType -imatch "AddUser")
	{
		$ExtType = "create the account or set the password"
		[hashtable]$Param=@{};
		$Param['username'] = $NewUser;
		$Param['password'] = $passwd;
		$Param['expiration'] = $expiration;
		$PrivateConfig = ConvertTo-Json $Param;
		$statusfile = "$LogDir\after-adduser-shadow.txt"
		if ( $UseAzureResourceManager )
		{
			$RGName = $AllVMData.ResourceGroupName
			$VMName = $AllVMData.RoleName
			$Location = $vm.Location
			write-host "Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose"
			$out = Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose
			WaitFor -seconds 120
		}
		else{
			write-host "Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose"
			$out = Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose
			WaitFor -seconds 120
		}
		$LogPaths = VMAccessExtensionLog -user $user -password $password
		$LogFilesPaths = $LogPaths.split(" ")[0]
		$LogFiles = $LogPaths.split(" ")[1]
		$ExtExecutionLogStatus = VMAccessExtensionExecutionStatus -user $user -password $password -ExtensionType $ExtType -LogFilesPaths $LogFilesPaths
		$ExtensionStatus = RetryOperation -operation $ConfirmExtensionScriptBlock -description "Confirming $ExtensionName extension from Azure side." -expectResult $true -maxRetryCount 10 -retryInterval 10
		LogMsg "Status of $TaskType extension ExtExecutionStatus: $ExtensionStatus and ExtExecutionLogStatus : $ExtExecutionLogStatus"
		if(($ExtensionStatus -eq $True) -and ($ExtExecutionLogStatus -eq $True))  		
		{
			LogMsg "$TaskType Extension executed successfully.."
			$output = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "ps aux | grep waagent | grep -v grep" -runAsSudo  
			if($output -match 'python3')  
			{  
				$VMStatus = RunLinuxCmd -username $NewUser -password $passwd -ip $hs1VIP -port $hs1vm1sshport -command "python3 /usr/sbin/waagent --version"  
			}  
			else  
			{  
 				$VMStatus = RunLinuxCmd -username $NewUser -password $passwd -ip $hs1VIP -port $hs1vm1sshport -command "/usr/sbin/waagent --version" 
 			}
 			$VMStatus1 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/shadow" -runAsSudo
			if(($VMStatus -imatch "WALinuxAgent") -and ($VMStatus1 -imatch $NewUser))
			{
				$ExtStatus = $True
				LogMsg "Added $NewUser logged in Successfully: $VMStatus"
			}
			else{
				$ExtStatus = $False
				LogErr "Added $NewUser login Failed: $VMStatus"
			}
		}
		else{
			LogErr "$TaskType Extension execution failed : $ExtensionStatus : $ExtExecutionLogStatus"
			$ExtStatus = $False
		}
		$VMStatus1 > $statusfile
		$VMStatus >> $statusfile
	}
	elseif($TaskType -imatch "ResetPassword")
	{
		$ExtType = "create the account or set the password"	
		[hashtable]$Param=@{};
		$Param['username'] = $NewUser;
		$Param['password'] = $newpassword;
		$Param['expiration'] = $expiration;
		$PrivateConfig = ConvertTo-Json $Param;
		$statusfile = "$LogDir\ResetPassword.txt"
		$UserStatusBeforeExt = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/shadow" -runAsSudo
		if($UserStatusBeforeExt -imatch $NewUser)
		{
			if ( $UseAzureResourceManager )
			{
				$RGName = $AllVMData.ResourceGroupName
				$VMName = $AllVMData.RoleName
				$Location = $vm.Location
				write-host "Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose"
				$out = Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose
				WaitFor -seconds 120
			}
			else{
				write-host "Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose"
				$out = Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose
				WaitFor -seconds 120
			}
			$LogPaths = VMAccessExtensionLog -user $user -password $password
			$LogFilesPaths = $LogPaths.split(" ")[0]
			$LogFiles = $LogPaths.split(" ")[1]
			$ExtExecutionLogStatus = VMAccessExtensionExecutionStatus -user $user -password $password -ExtensionType $ExtType -LogFilesPaths $LogFilesPaths
			$ExtensionStatus = RetryOperation -operation $ConfirmExtensionScriptBlock -description "Confirming $ExtensionName extension from Azure side." -expectResult $true -maxRetryCount 10 -retryInterval 10
			LogMsg "Status of $TaskType extension ExtExecutionStatus: $ExtensionStatus and ExtExecutionLogStatus : $ExtExecutionLogStatus"
			if(($ExtensionStatus -imatch $True) -and ($ExtExecutionLogStatus -eq $True))
			{
				LogMsg "$TaskType Extension executed successfully.."
				$output = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "ps aux | grep waagent | grep -v grep" -runAsSudo  
				if($output -match 'python3')  
				{
					$VMStatus = RunLinuxCmd -username $NewUser -password $newpassword -ip $hs1VIP -port $hs1vm1sshport -command "python3 /usr/sbin/waagent --version"  
				}
				else  
				{
					$VMStatus = RunLinuxCmd -username $NewUser -password $newpassword -ip $hs1VIP -port $hs1vm1sshport -command "/usr/sbin/waagent --version"  
				}
  				$VMStatus2 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/shadow" -runAsSudo
				if(($VMStatus -imatch "WALinuxAgent") -and ($VMStatus2 -imatch $NewUser))
				{
					$ExtStatus = $True
					LogMsg "Added $NewUser logged in Successfully with New Password: $VMStatus"
				}
				else{
					$ExtStatus = $False
					LogErr "Added $NewUser login Failed with New Password: $VMStatus"
				}
			}
			else{
				LogErr "$TaskType Extension execution failed : $ExtensionStatus : $ExtExecutionLogStatus"
				$ExtStatus = $False
			}
			$VMStatus2 > $statusfile
			$VMStatus >> $statusfile
		}
		else{
			LogErr "$TaskType Extension execution Aborted.. due to $NewUser is not available"
			$ExtStatus = $False
		}
	}
	elseif($TaskType -imatch "DeleteUser")
	{
		$PrivateConfig = '{"remove_user": "' + $NewUser + '"}'
		$statusfile = "$LogDir\after-deleteuser-shadow.txt"
		$UserStatusBeforeExt = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/shadow" -runAsSudo
		if($UserStatusBeforeExt -imatch $NewUser)
		{
			if ( $UseAzureResourceManager )
			{
				$RGName = $AllVMData.ResourceGroupName
				$VMName = $AllVMData.RoleName
				$Location = $vm.Location
				write-host "Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose"
				$out = Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose
				WaitFor -seconds 120
			}
			else{
				write-host "Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose"
				$out = Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose
				WaitFor -seconds 120
			}			
			$UserStatusAfterExt = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/shadow" -runAsSudo
			$ExtensionStatus = RetryOperation -operation $ConfirmExtensionScriptBlock -description "Confirming $ExtensionName extension from Azure side." -expectResult $true -maxRetryCount 10 -retryInterval 10
			LogMsg "Status of $TaskType extension ExtExecutionStatus: $ExtensionStatus"
			if($ExtensionStatus -imatch $True)
			{
				LogMsg "$TaskType Extension executed successfully.."
				if($UserStatusAfterExt -imatch $NewUser)
				{
					$ExtStatus = $False
					LogErr "Deleting added $NewUser is Failed.."
				}
				else{
					$ExtStatus = $True
					LogMsg "Added $NewUser is deleted successfully.."
				}
			}
			else{
				LogErr "$TaskType Extension execution failed : $ExtensionStatus : $ExtExecutionLogStatus"
				$ExtStatus = $False
			}
			$UserStatusAfterExt > $statusfile
		}
		else{
			LogErr "$TaskType Extension execution Aborted.. due to $NewUser is not available"
			$ExtStatus = $False
		}
	}
	elseif($TaskType -imatch "ResetSSHConfig")
	{
		$ExtType = "reset sshd_config"
		$NewSshPort = "99"
		$password = $xmlConfig.config.Azure.Deployment.Data.Password
		$user = $xmlConfig.config.Azure.Deployment.Data.UserName
		$PrivateConfig = '{"reset_ssh": "True"}'
		$SSHstatus1 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp /etc/ssh/sshd_config /home/$user/logs/sshd_config.bak" -runAsSudo
		$sshdconfig = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/ssh/sshd_config | grep '#Port 22'" -runAsSudo -ignoreLinuxExitCode
		if($sshdconfig -imatch "#Port 22")
		{
			$SSHstatus2 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "sed --in-place -e 's/#Port 22\s*/#Port 99/' /etc/ssh/sshd_config" -runAsSudo -ignoreLinuxExitCode
		}
		else{
			$SSHstatus3 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "sed --in-place -e 's/Port 22\s*/Port 99/' /etc/ssh/sshd_config" -runAsSudo -ignoreLinuxExitCode
		}
		$SSHstatus4 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp /etc/ssh/sshd_config /home/$user/logs/sshd_config_mod" -runAsSudo
		$VMStatusBeforeExt = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/ssh/sshd_config | grep 'Port 99'" -runAsSudo -ignoreLinuxExitCode
		if ( $UseAzureResourceManager )
		{
			$RGName = $AllVMData.ResourceGroupName
			$VMName = $AllVMData.RoleName
			$Location = $vm.Location
			write-host "Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose"
			$out = Set-AzureVMExtension -ResourceGroupName $RGName -VMName $VMName -Location $Location -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionName -TypeHandlerVersion $VersionForARM -Settingstring $PublicConfig -ProtectedSettingString $PrivateConfig -Verbose
			WaitFor -seconds 120
		}
		else{
			write-host "Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose"
			$out = Set-AzureVMExtension -ExtensionName $ExtensionName -VM $vm -Publisher $Publisher -Version $Version -PrivateConfiguration $PrivateConfig | Update-AzureVM -Verbose
			WaitFor -seconds 120
		}	
		
		$LogPaths = VMAccessExtensionLog -user $user -password $password
		$LogFilesPaths = $LogPaths.split(" ")[0]
		$LogFiles = $LogPaths.split(" ")[1]
		$ExtExecutionLogStatus = VMAccessExtensionExecutionStatus -user $user -password $password -ExtensionType $ExtType -LogFilesPaths $LogFilesPaths
		$ExtensionStatus = RetryOperation -operation $ConfirmExtensionScriptBlock -description "Confirming $ExtensionName extension from Azure side." -expectResult $true -maxRetryCount 10 -retryInterval 10
		LogMsg "Status of $TaskType extension ExtExecutionStatus: $ExtensionStatus and ExtExecutionLogStatus : $ExtExecutionLogStatus"
		if(($ExtensionStatus -imatch $True) -and ($ExtExecutionLogStatus -eq $True))
		{
			LogMsg "$TaskType Extension executed successfully.."
			$VMStatusAfterExt = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat /etc/ssh/sshd_config | grep 'Port 22'" -runAsSudo -ignoreLinuxExitCode
			if(($VMStatusAfterExt -imatch "Port 22") -and ($VMStatusBeforeExt -imatch "Port 99"))
			{
				$ExtStatus = $True
			}
			else{
				$ExtStatus = $False
				LogMsg "sshd_config reset failed, ssh port reset back to 22 manually, not with extension"
				$SSHstatus = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $NewSshPort -command "cp /home/$user/logs/sshd_config.bak  /etc/ssh/sshd_config" -runAsSudo -ignoreLinuxExitCode
				if($Distro -imatch "UBUNTU"){
					$SSHstatus = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $NewSshPort -command "service ssh restart" -runAsSudo -ignoreLinuxExitCode
				}
				else{
					$SSHstatus = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $NewSshPort -command "service sshd restart" -runAsSudo -ignoreLinuxExitCode
				}
			}
		}
		else{
			LogErr "$TaskType Extension execution failed : $ExtensionStatus : $ExtExecutionLogStatus"
			$ExtStatus = $False
			$SSHstatus = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $NewSshPort -command "cp -f /home/$user/logs/sshd_config.bak  /etc/ssh/sshd_config" -runAsSudo -ignoreLinuxExitCode
			if($Distro -imatch "UBUNTU"){
				$SSHstatus = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $NewSshPort -command "service ssh restart" -runAsSudo -ignoreLinuxExitCode
			}
			else{
				$SSHstatus = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $NewSshPort -command "service sshd restart" -runAsSudo -ignoreLinuxExitCode
			}
		}
	}
	else{
		LogMsg "provide the proper extension task $TaskType"
		break
	}
	return $ExtStatus
}
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
		#Get VMs deployed in the service..
		$hs1VIP = $AllVMData.PublicIP
		$hs1vm1sshport = $AllVMData.SSHPort
		$hs1ServiceUrl = $AllVMData.URL
		$hs1vm1Dip = $AllVMData.InternalIP
		
		if ( $UseAzureResourceManager )
		{
			$vm = Get-AzureResourceGroup -Name $AllVMData.ResourceGroupName
		}
		else{
			$vm = Get-AzureVM -ServiceName $AllVMData.ServiceName -Name $AllVMData.RoleName
		}
		$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mkdir /home/$user/logs" -runAsSudo
		$SSHstatus1 = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp /etc/ssh/sshd_config /home/$user/logs/sshd_config.bakup" -runAsSudo
		foreach ( $TaskType in $MyExtn.ExtensionTask.split(","))
		{
			try
			{			
				LogMsg "$TaskType Test Started.."
				$VMAccessExtStatus = VMAccessExtTest -TaskType $TaskType #-vm $vm				
				if($VMAccessExtStatus -eq $True)
				{
					$testResult = "PASS"
					LogMsg "$TaskType is completed successfully...PASS"
					$metaData = "$TaskType"
				}
				else
				{
					$testResult = "FAIL"
					LogErr "$TaskType is failed...FAIL"
					$metaData = "$TaskType"
				}
			}
			catch
			{
				$testResult = "Aborted"
				LogErr "$TaskType is Aborted..."
				$metaData = "$TaskType"   
			}
			$resultArr += $testResult
			$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
			$password = $xmlConfig.config.Azure.Deployment.Data.Password
			$user = $xmlConfig.config.Azure.Deployment.Data.UserName
		}
		$LogPaths = VMAccessExtensionLog -user $user -password $password
		$LogFilesPaths = $LogPaths.split(" ")[0]
		$LogFiles = $LogPaths.split(" ")[1]
		LogMsg "Collecting Logs"
		foreach ($file in $LogFilesPaths.Split(","))
		{
			$fileName = $file.Split("/")[$file.Split("/").Count -1]
			if ( $file -imatch $ExtensionName )
			{
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $file > $fileName" -runAsSudo
				RemoteCopy -download -downloadFrom $hs1VIP -files $fileName -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
			}
			else
			{
				LogErr "Unexpected Extension Found : $($file.Split("/")[4]) with version $($file.Split("/")[5])"
				LogMsg "Skipping download for : $($file.Split("/")[4]) : $fileName"
			}
		}
		$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod 664 /home/$user/logs/*" -runAsSudo
		RemoteCopy -download -downloadFrom $hs1VIP -files "/var/log/waagent.log,/home/$user/logs/*" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
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
			$resultArr += $testResult
			$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
		}
	}
}
else
{
	$testResult = "FAIL"
	$resultArr += $testResult
	$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
}
$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $result, $resultSummary
