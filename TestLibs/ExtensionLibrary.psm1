Function VerifyExtensionFromAzure ([string]$ExtensionName, [string]$ServiceName, [string]$ResourceGroupName, $maxRetryCount=20, $retryIntervalInSeconds=10)
{
	$retryCount = 1
	do
	{
		if ( $UseAzureResourceManager )
		{
			LogMsg "Verifying $ExtensionName from Using Get-AzureResource command ..."
			$ExtensionStatus = Get-AzureResource -OutputObjectFormat New -ResourceGroupName $ResourceGroupName  -ResourceType "Microsoft.Compute/virtualMachines/extensions" -ExpandProperties
			if ( ($ExtensionStatus.Properties.ProvisioningState -eq "Succeeded") -and ( $ExtensionStatus.Properties.Type -eq $ExtensionName ) )
			{
				LogMsg "$ExtensionName extension status is Succeeded in Properties.ProvisioningState"
				$retValue = $true
				$waitForExtension = $false
			}
			else
			{
				LogErr "$ExtensionName extension status is Failed in Properties.ProvisioningState"
				$retValue = $false
				$waitForExtension = $true
				WaitFor -Seconds 30
			}
		}
		else
		{
			LogMsg "Verifying $ExtensionName from Using Get-AzureVM command ..."
			$vmDetails = Get-AzureVM -ServiceName $ServiceName
 			if ( ( $vmDetails.ResourceExtensionStatusList.ExtensionSettingStatus.Status -eq "Success" ) -and ($vmDetails.ResourceExtensionStatusList.ExtensionSettingStatus.Name -imatch $ExtensionName ))
			{
				
				LogMsg "$ExtensionName extension status is SUCCESS in (Get-AzureVM).ResourceExtensionStatusList.ExtensionSettingStatus"
				$retValue = $true
				$waitForExtension = $false
			}
			else
			{
				LogErr "$ExtensionName extension status is FAILED in (Get-AzureVM).ResourceExtensionStatusList.ExtensionSettingStatus"
				$retValue = $false
				$waitForExtension = $true
				WaitFor -Seconds 30
			}
		}
		$retryCount += 1
		if ( ($retryCount -le $maxRetryCount) -and $waitForExtension )
		{
			LogMsg "Retrying... $($maxRetryCount-$retryCount) attempts left..."
		}
		elseif ($waitForExtension)
		{
			LogMsg "Retry Attempts exhausted."
		}
	}
	while (($retryCount -le $maxRetryCount) -and $waitForExtension )
	return $retValue
}

Function DownloadExtensionLogFilesFromVarLog ($LogFilesPaths, $ExtensionName, $vmData)
{
	foreach ($file in $LogFilesPaths.Split(","))
	{
		$fileName = $file.Split("/")[$file.Split("/").Count -1]
		if ( $file -imatch $ExtensionName )
		{
			$out = RunLinuxCmd -username $user -password $password -ip $vmData.PublicIP -port $vmData.SSHPort -command "cat $file > $fileName" -runAsSudo
			RemoteCopy -download -downloadFrom $vmData.PublicIP -files $fileName -downloadTo $LogDir -port $vmData.SSHPort -username $user -password $password
		}
		else
		{
			LogErr "Unexpected Extension Found : $($file.Split("/")[4]) with version $($file.Split("/")[5])"
			LogMsg "Skipping download for : $($file.Split("/")[4]) : $fileName"
		}
	}
}

Function GetExtensionStatusFromStatusFile ( $statusFilePaths, $ExtensionName, $vmData, $expextedFile, $maxRetryCount = 20, $retryIntervalInSeconds=10)
{
	$retryCount = 1
	do
	{
		foreach ($file in $statusFilePaths.Split(","))
		{
			$fileName = $file.Split("/")[$file.Split("/").Count -1]
			LogMsg "Verifying $ExtensionName from $file ..."
			if($fileName -imatch "\d.status")
			{
				if ( $file -imatch $ExtensionName ) 
				{
					$extensionErrorCount = 0
					$statusFileNotFound = $false
					$out = RunLinuxCmd -username $user -password $password -ip $vmData.PublicIP -port $vmData.SSHPort -command "cat $file > $fileName" -runAsSudo
					RemoteCopy -download -downloadFrom $vmData.PublicIP -files $fileName -downloadTo $LogDir -port $vmData.SSHPort -username $user -password $password
					$statusFile = Get-Content -Path "$LogDir\$fileName"
					$extensionVarLibStatus = ConvertFrom-Json -InputObject $statusFile
					if ( $extensionVarLibStatus.Status.status -eq "success" )
					{
						LogMsg "$fileName reported status : $($extensionVarLibStatus.Status.status)"
					}
					else
					{
						LogMsg "$fileName reported status : $($extensionVarLibStatus.Status.status)"
						$extensionErrorCount += 1
					}
					if ( $extensionVarLibStatus.Status.code -eq 0 )
					{
						LogMsg "$fileName reported code : $($extensionVarLibStatus.Status.code)"
					}
					else
					{
						LogErr "$fileName reported code : $($extensionVarLibStatus.Status.code)"
						$extensionErrorCount += 1
					}
				}
				else
				{
					LogErr "Unexpected status file Found : $file"
					LogMsg "Skipping checking for this file"
				}
			}
		}
		if ( $extensionErrorCount -eq 0 )
		{
			LogMsg "Extension verified successfully."
			$retValue = $true
			$waitForExtension = $false

		}
		else
		{
			LogErr "Extension Verification Failed."
			$retValue = $false
			$waitForExtension = $true
			WaitFor -Seconds 30

		}		
		$retryCount += 1
		if ( ($retryCount -le $maxRetryCount) -and $waitForExtension )
		{
			LogMsg "Retrying... $($maxRetryCount-$retryCount) attempts left..."
		}
		elseif ($waitForExtension)
		{
			LogMsg "Retry Attempts exhausted."
		}
	}
	while (($retryCount -le $maxRetryCount) -and $waitForExtension )
	return $retValue
}