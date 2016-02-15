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
		$hs1VIP = $AllVMData.PublicIP
		$hs1vm1sshport = $AllVMData.SSHPort
		$hs1ServiceUrl = $AllVMData.URL
		$hs1vm1Dip = $AllVMData.InternalIP
		$hs1vm1Hostname = $AllVMData.RoleName
		$ExtensionVerfiedWithPowershell = $false
		$LogFilesPaths = ""
		$LogFiles = ""
		$ExtensionName = "CustomScriptForLinux"
		$statusFile = "0.status"
		
		#region check Extension Status from 0.status file
		LogMsg "--------------------- STAGE 1/3 : verification of $statusFile : START ---------------------"
		$statusFilePath = GetFilePathsFromLinuxFolder -folderToSearch "/var/lib/waagent" -IpAddress $allVMData.PublicIP -SSHPort $allVMData.SSHPort -username $user -password $password -expectedFiles "$statusFile"

		if ( $statusFilePath[0] )
		{
			$ExtensionStatusInStatusFile = GetExtensionStatusFromStatusFile -statusFilePaths $statusFilePath[0] -ExtensionName $ExtensionName -vmData $allVMData
		}
		else
		{
			LogErr "status file not found under /var/lib/waagent"
			$ExtensionStatusInStatusFile = $false
		}
		LogMsg "--------------------- STAGE 1/3 : verification of $statusFile : END ---------------------"
		#endregion

		#region check Extension from Azure Side
		LogMsg "--------------------- STAGE 2/3 : verification from Azure : START ---------------------"
		$ExtensionStatusFromAzure = VerifyExtensionFromAzure -ExtensionName $ExtensionName -ServiceName $isDeployed -ResourceGroupName $isDeployed
		LogMsg "--------------------- STAGE 2/3 : verification from Azure : END ---------------------"
		#endregion

		#region check if extension has done its job properply...
		LogMsg "--------------------- STAGE 3/3 : verification of Extension Execution : START ---------------------"
		$folderToSearch = "/var/log/azure"
		$FoundFiles = GetFilePathsFromLinuxFolder -folderToSearch $folderToSearch -IpAddress $hs1VIP -SSHPort $hs1vm1sshport -username $user -password $password -expectedFiles "extension.log,CommandExecution.log"
		$LogFilesPaths = $FoundFiles[0]
		$LogFiles = $FoundFiles[1]
		$retryCount = 1
		$maxRetryCount = 10
		if ($LogFilesPaths)
		{   
			do
			{
				DownloadExtensionLogFilesFromVarLog -LogFilesPaths $LogFilesPaths -ExtensionName $ExtensionName -vmData $AllVMData
				LogMsg "Attempt : $retryCount/$maxRetryCount : Checking if Custom Script is executed...."
				RemoteCopy -download -downloadFrom $hs1VIP -files "/var/log/waagent.log" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
				$lsOutput = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "ls /var/log/" -runAsSudo
				LogMsg -msg $lsOutput -LinuxConsoleOuput
				if ($lsOutput -imatch "CustomExtensionSuccessful")
				{
					$extensionExecutionVerified = $true
					$waitForExtension = $false
					LogMsg "Custom Script execution verified successfully."
				}
				else
				{
					$extensionExecutionVerified  = $false
					LogErr "Custom Script execution not yet detected."
					$waitForExtension = $true
					WaitFor -Seconds 30
				}
				$retryCount += 1
			}
			while (($retryCount -le $maxRetryCount) -and $waitForExtension )
		}
		else
		{
			LogErr "No Extension logs are available."
			$extensionExecutionVerified  = $false
		}
		LogMsg "--------------------- STAGE 3/3 : verification of Extension Execution : END ---------------------"
		#endregion

		if ( $ExtensionStatusFromAzure -and $extensionExecutionVerified  -and $ExtensionStatusInStatusFile )
		{
			LogMsg "STATUS FILE VERIFICATION : PASS"
			LogMsg "AZURE STATUS VERIFICATION : PASS"
			LogMsg "EXTENSION EXECUTION VERIFICATION : PASS"
			$testResult = "PASS"
		}
		else
		{
			if ( !$ExtensionStatusInStatusFile )
			{
				LogErr "STATUS FILE VERIFICATION : FAIL"
			}
			if ( !$ExtensionStatusFromAzure )
			{
				LogErr "AZURE STATUS VERIFICATION : FAIL"
			}
			if ( !$extensionExecutionVerified )
			{
				LogErr "EXTENSION EXECUTION VERIFICATION : FAIL"
			}
			$testResult = "FAIL"
		}
		LogMsg "Test result : $testResult"
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
	}   
}
else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $result