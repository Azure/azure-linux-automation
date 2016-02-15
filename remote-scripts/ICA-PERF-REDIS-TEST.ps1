﻿<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
		$noServer = $true
		$noClient = $true
		$redisSummary = $null
		foreach ( $vmData in $allVMData )
		{
			if ( $vmData.RoleName -imatch "Server" )
			{
				$serverVMData = $vmData
				$noServer = $false
			}
			elseif ( $vmData.RoleName -imatch "Client" )
			{
				$clientVMData = $vmData
				$noClient = $fase
			}
		}
		if ( $noServer )
		{
			Throw "No any server VM defined. Be sure that, server VM role name matches with the pattern `"*server*`". Aborting Test."
		}
		if ( $noSlave )
		{
			Throw "No any client VM defined. Be sure that, client machine role names matches with pattern `"*client*`" Aborting Test."
		}
		#region CONFIGURE VMs for TEST
		LogMsg "SERVER VM details :"
		LogMsg "  RoleName : $($serverVMData.RoleName)"
		LogMsg "  Public IP : $($serverVMData.PublicIP)"
		LogMsg "  SSH Port : $($serverVMData.SSHPort)"
		LogMsg "CLIENT VM details :"
		LogMsg "  RoleName : $($clientVMData.RoleName)"
		LogMsg "  Public IP : $($clientVMData.PublicIP)"
		LogMsg "  SSH Port : $($clientVMData.SSHPort)"

		#
		# PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.	
		#
		ProvisionVMsForLisa -allVMData $allVMData
		
		foreach ( $vmData in $allVMData )
		{
			LogMsg "Adding $($vmData.InternalIP) $($vmData.RoleName) to /etc/hosts of $($serverVMData.RoleName) "
			$out = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "echo $($vmData.InternalIP) $($vmData.RoleName) >> /etc/hosts"
		}
		#endregion

		#region Geting Test Data from remote XML file
		$redisXMLURL = $($currentTestData.remoteXML)
		LogMsg "Downloading redis XML : $redisXMLURL ..."
		$redisXMLFileName = $($redisXMLURL.Split("/")[$redisXMLURL.Split("/").Count-1])
		$out = Invoke-WebRequest -Uri $redisXMLURL -OutFile "$LogDir\$redisXMLFileName"
		$redisXMLData = [xml](Get-Content -Path "$LogDir\$redisXMLFileName") 

		LogMsg "Generating constansts.sh ..."
		$constantsFile = "$LogDir\constants.sh"
		Set-Content -Value "#Generated by Azure Automation." -Path $constantsFile
		foreach ($redisParam in $redisXMLData.config.testCases.test.testParams.param )
		{
			if ($redisParam -imatch "REDIS_HOST_IP")
			{
				Add-Content -Value "REDIS_HOST_IP=$($clientVMData.InternalIP)" -Path $constantsFile
				LogMsg "REDIS_HOST_IP=$($clientVMData.InternalIP) added to constansts.sh"
			}
			else
			{
				Add-Content -Value "$redisParam" -Path $constantsFile
				LogMsg "$redisParam added to constansts.sh"
			}
			if ($redisParam -imatch "REDIS_PACKAGE")
			{
				$redisPackage = $redisParam.Replace("REDIS_PACKAGE=","")
			}
		}		
		LogMsg "constanst.sh created successfully..."
		#endregion

		#region Download remote files needed to run tests
		LogMsg "Downloading remote files ..."
		foreach ( $fileURL in  $($currentTestData.remoteFiles).Split(",") )
		{
			LogMsg "Downloading $fileURL ..."
			$start_time = Get-Date
			$fileName =  $fileURL.Split("/")[$fileURL.Split("/").Count-1]
			$out = Invoke-WebRequest -Uri $fileURL -OutFile "$LogDir\$fileName"
			LogMsg "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
		}
		LogMsg "Downloading REDIS package : $redisPackage"
		$redisPackageUrl = "http://download.redis.io/releases/$redisPackage"
		$start_time = Get-Date
		$out = Invoke-WebRequest -Uri $redisPackageUrl -OutFile "$LogDir\$redisPackage"
		LogMsg "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
		#endregion
		
		#region EXECUTE TEST
		Set-Content -Value "/root/performance_redis.sh &> redisConsoleLogs.txt" -Path "$LogDir\StartRedisTest.sh"
		RemoteCopy -uploadTo $serverVMData.PublicIP -port $serverVMData.SSHPort -files ".\$LogDir\$redisPackage,.\$constantsFile,.\$LogDir\performance_redis.sh,.\$LogDir\StartRedisTest.sh" -username "root" -password $password -upload
		$out = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "chmod +x *.sh"
		$testJob = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "/root/StartRedisTest.sh" -RunInBackground
		#endregion

		#region MONITOR TEST
		while ( (Get-Job -Id $testJob).State -eq "Running" )
		{
			$currentStatus = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "tail -n 1 /root/redisConsoleLogs.txt"
			LogMsg "Current Test Staus : $currentStatus"
			WaitFor -seconds 10
		}
		
		$redisResult = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "sed -i '/^$/d' /root/redis.log && tail -n 1 /root/redis.log"
		$finalStatus = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "cat /root/state.txt"
		
		RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/redisConsoleLogs.txt"
		RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/summary.log"
		$redisSummary = Get-Content -Path "$LogDir\summary.log" -ErrorAction SilentlyContinue
		#endregion

		if (!$redisSummary)
		{
			LogMsg "summary.log file is empty."
			$redisSummary = "<EMPTY>"
		}
		if ( $finalStatus -imatch "TestFailed")
		{
			LogErr "Test failed. Last known status : $currentStatus."
			$testResult = "FAIL"
		}
		elseif ( $finalStatus -imatch "TestAborted")
		{
			LogErr "Test Aborted. Last known status : $currentStatus."
			$testResult = "ABORTED"
		}
		elseif ( $finalStatus -imatch "TestCompleted")
		{
			LogMsg "Test Completed. Result : $redisResult."
			$testResult = "PASS"
		}
		elseif ( $finalStatus -imatch "TestRunning")
		{
			LogMsg "Powershell backgroud job for test is completed but VM is reporting that test is still running. Please check $LogDir\redisConsoleLogs.txt"
			LogMsg "Contests of summary.log : $redisResult"
			$testResult = "PASS"
		}
		LogMsg "Test result : $testResult"
		LogMsg "Test Completed"
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = "REDIS RESULT"
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
		$resultSummary +=  CreateResultSummary -testResult $redisResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
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
return $result, $resultSummary