#v-shisav : STILL IN BETA VERSION

param($xmlConfig, [string] $Distro, [string] $cycleName)


$user = $xmlConfig.config.Azure.Deployment.Data.UserName
$password = $xmlConfig.config.Azure.Deployment.Data.Password
Set-Variable -Name user -Value $user -Scope Global
Set-Variable -Name password -Value $password -Scope Global
$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP

Import-Module .\TestLibs\UtilLibs.psm1 -Force
Import-Module .\TestLibs\RDFELibs.psm1 -Force
Import-Module .\TestLibs\DataBase\DataBase.psm1 -Force
Import-Module .\TestLibs\PerfTest\PerfTest.psm1 -Force

Function CollectLogs()
{}

Function GetCurrentCycleData($xmlConfig, $cycleName)
{	
	foreach ($Cycle in $xmlConfig.config.testCycles.Cycle )
	{
		if($cycle.cycleName -eq $cycleName)
		{
		return $cycle
		break
		}
	}
	
}


#This function will check in the xmlConfig for test data and will return the object.
Function GetCurrentTestData($xmlConfig, $testName)
{
	foreach ($test in $xmlConfig.config.testsDefinition.test)
	{
		if ($test.testName -eq $testName)
		{
		LogMsg "Loading the test data for $($test.testName)"
		Set-Variable -Name CurrentTestData -Value $test -Scope Global -Force
		return $test
		break
		}
	}
}

Function RefineTestResult2 ($testResult)
{
	$i=0
	$tempResult = @()
	foreach ($cmp in $testResult)
	{
		if(($cmp -eq "PASS") -or ($cmp -eq "FAIL") -or ($cmp -eq "ABORTED"))
		{
			$tempResult += $testResult[$i]
			$tempResult += $testResult[$i+1]
			$testResult = $tempResult
			break
		}
		$i++;
	}
	return $testResult
}

Function RefineTestResult1 ($tempResult)
{
	foreach ($new in $tempResult)
	{
		$lastObject = $new
	}
	$tempResultSplitted = $lastObject.Split(" ")
	if($tempResultSplitted.Length > 1 )
	{
		Write-Host "Test Result =  $lastObject" -ForegroundColor Gray
	}
	$lastWord = ($tempResultSplitted.Length - 1)

	return $tempResultSplitted[$lastWord]
}

Function RunTestsOnCycle ($cycleName , $xmlConfig, $Distro )
{
	$StartTime = [Datetime]::Now.ToUniversalTime()
	LogMsg "Starting the Cycle - $($CycleName.ToUpper())"
	$xmlConfig.config.Azure.Deployment.Data.Distro | ? { $_.name -eq $Distro} | % { 
		if ( $_.OsImage ) 
		{ 
			$BaseOsImage = $_.OsImage.ToUpper() 
			Set-Variable -Name BaseOsImage -Value $BaseOsImage -Scope Global
			LogMsg "Base image name - $BaseOsImage"
		}
		if ( $_.OsVHD )
		{ 
			$BaseOsVHD = $_.OsVHD.ToUpper() 
			Set-Variable -Name BaseOsVHD -Value $BaseOsVHD -Scope Global
			LogMsg "Base VHD name - $BaseOsVHD"
		}
	}
    if (!$BaseOsImage -and !$BaseOSVHD)
    {
        Throw "Please give ImageName or OsVHD for deployment."
    }
	LogMsg "Loading the cycle Data..."
	$currentCycleData = GetCurrentCycleData -xmlConfig $xmlConfig -cycleName $cycleName

	$xmlElementsToAdd = @("currentTest", "stateTimeStamp", "state", "emailSummary", "htmlSummary", "jobID", "testCaseResults")
	foreach($element in $xmlElementsToAdd)
	{
		if (! $testCycle.${element})
		{
			$newElement = $xmlConfig.CreateElement($element)
			$newElement.set_InnerText("")
			$results = $testCycle.AppendChild($newElement)
		}
	}


	$testSuiteLogFile=$logFile
	$testSuiteResultDetails=@{"totalTc"=0;"totalPassTc"=0;"totalFailTc"=0;"totalAbortedTc"=0}
	$id = ""
	
	# Start JUnit XML report logger.
	$reportFolder = "$pwd/report"
	if(!(Test-Path $reportFolder))
	{
		New-Item -ItemType "Directory" $reportFolder
	}
	StartLogReport("$reportFolder/report_$($testCycle.cycleName).xml")
	$testsuite = StartLogTestSuite "CloudTesting"
	
	$testCount = $currentCycleData.test.Length
	if (-not $testCount)
	{
		$testCount = 1
	}

	for ($counter = 0; $counter -lt $testCount; $counter++)
	{
		$test = $currentCycleData.test[$counter]
		if (-not $test)
		{
			$test = $currentCycleData.test
		}
		$currentTestData = GetCurrentTestData -xmlConfig $xmlConfig -testName $test.Name
		# Generate Unique Test
		$server = $xmlConfig.config.global.ServerEnv.Server		
		$cluster = $xmlConfig.config.global.ClusterEnv.Cluster
		$rdosVersion = $xmlConfig.config.global.ClusterEnv.RDOSVersion
		$fabricVersion = $xmlConfig.config.global.ClusterEnv.FabricVersion
		$Location = $xmlConfig.config.global.ClusterEnv.Location
		$testDescription = "Running BVT Tests.."
		$testId = $currentTestData.TestId
		$testSetup = $currentTestData.setupType
		$lisBuild = $xmlConfig.config.global.VMEnv.LISBuild
		$lisBuildBranch = $xmlConfig.config.global.VMEnv.LISBuildBranch
		$VMImageDetails = $xmlConfig.config.global.VMEnv.VMImageDetails
		$waagentBuild=$xmlConfig.config.global.VMEnv.waagentBuild

		# For the last test running in economy mode, set the IsLastCaseInCycle flag so that the deployments could be cleaned up
		if ($EconomyMode -and $counter -eq ($testCount - 1))
		{
			Set-Variable -Name IsLastCaseInCycle -Value $true -Scope Global
		}
		else
		{
			Set-Variable -Name IsLastCaseInCycle -Value $false -Scope Global
		}
		if ($currentTestData)
		{
			if ( $UseAzureResourceManager -and !($currentTestData.SupportedExecutionModes -imatch "AzureResourceManager"))
			{
				LogMsg "$($currentTestData.testName) does not support AzureResourceManager execution mode."
				continue;
			}
			if (!$UseAzureResourceManager -and !($currentTestData.SupportedExecutionModes -imatch "AzureServiceManagement"))
			{
				LogMsg "$($currentTestData.testName) does not support AzureServiceManagement execution mode."
				continue;
			}
			$testcase = StartLogTestCase $testsuite "$($test.Name)" "CloudTesting.$($testCycle.cycleName)"
			$testSuiteResultDetails.totalTc = $testSuiteResultDetails.totalTc +1
			$stopWatch = SetStopWatch
			mkdir $testDir\$($test.Name) -ErrorAction SilentlyContinue | out-null
			if(($testPriority -imatch $currentTestData.Priority ) -or (!$testPriority))
			{
				$testCaseLogFile = $testDir + "\" + $($currentTestData.testName) + "\" + "azure_ica.log"
				$global:logFile  = $testCaseLogFile 
				if ((!$currentTestData.SubtestValues -and !$currentTestData.TestMode))
				{
					#Tests With No subtests and no SubValues will be executed here..
					try
					{
						$testResult = ""
						$LogDir = "$testDir\$($currentTestData.testName)"
						Set-Variable -Name LogDir -Value $LogDir -Scope Global
						LogMsg "~~~~~~~~~~~~~~~TEST STARTED : $($currentTestData.testName)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
						$testScriptPs1 = $currentTestData.testScriptPs1
						$startTime = [Datetime]::Now.ToUniversalTime()
						$command = ".\remote-scripts\" + $testScriptPs1
						LogMsg "Starting test $($currentTestData.testName)"
						$testResult = Invoke-Expression $command
						$testResult = RefineTestResult1 -tempResult $testResult
						$endTime = [Datetime]::Now.ToUniversalTime()
						$vmRam= GetTestVMHardwareDetails -xmlConfigFile $xmlConfig -setupType $testSetup  -RAM
						$vmVcpu = GetTestVMHardwareDetails -xmlConfigFile $xmlConfig -setupType $testSetup  -VCPU 
						$testRunDuration = GetStopWatchElapasedTime $stopWatch "mm"
						$testCycle.emailSummary += "$($currentTestData.testName) Execution Time: $testRunDuration minutes<br />"
						$testCycle.emailSummary += "	$($currentTestData.testName) : $testResult <br />"
						$testCycle.htmlSummary += "<tr><td>$($currentTestData.testName) - Execution Time  : </td><td> $testRunDuration min</td></tr>"
						$testResultRow = ""
						LogMsg "~~~~~~~~~~~~~~~TEST END : $($currentTestData.testName)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
					}
					catch
					{
						$testResult = "Aborted"
						$ErrorMessage =  $_.Exception.Message
						LogMsg "EXCEPTION : $ErrorMessage"   
					}
					if($testResult -imatch "PASS")
					{
						$testSuiteResultDetails.totalPassTc = $testSuiteResultDetails.totalPassTc +1
						$testResultRow = "<span style='color:green;font-weight:bolder'>PASS</span>"
						FinishLogTestCase $testcase
					}
					elseif($testResult -imatch "FAIL")
					{
						$testSuiteResultDetails.totalFailTc = $testSuiteResultDetails.totalFailTc +1
						$testResultRow = "<span style='color:red;font-weight:bolder'>FAIL</span>"
						$caseLog = Get-Content -Raw $testCaseLogFile
						FinishLogTestCase $testcase "FAIL" "$($test.Name) failed." $caseLog
					}
					elseif($testResult -imatch "ABORTED")
					{
						$testSuiteResultDetails.totalAbortedTc = $testSuiteResultDetails.totalAbortedTc +1
						$testResultRow = "<span style='background-color:yellow;font-weight:bolder'>ABORT</span>"
						$caseLog = Get-Content -Raw $testCaseLogFile
						FinishLogTestCase $testcase "ERROR" "$($test.Name) is aborted." $caseLog
					}
					$testCycle.htmlSummary += "<tr><td>	$($currentTestData.testName) </td><td> $testResultRow </td></tr>"
				}
				else
				{
					try
					{
						$testResult = @()
						$LogDir = "$testDir\$($currentTestData.testName)"
						Set-Variable -Name LogDir -Value $LogDir -Scope Global
						LogMsg "~~~~~~~~~~~~~~~TEST STARTED : $($currentTestData.testName)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
						$testScriptPs1 = $currentTestData.testScriptPs1
						$command = ".\remote-scripts\" + $testScriptPs1
						LogMsg "$command"
						LogMsg "Starting multiple tests : $($currentTestData.testName)"
						$startTime = [Datetime]::Now.ToUniversalTime()
						$testResult = Invoke-Expression $command
						$testResult = RefineTestResult2 -testResult $testResult
						$testRunDuration = GetStopWatchElapasedTime $stopWatch "mm"
						$testRunDuration = $testRunDuration.ToString()
						$testCycle.emailSummary += "$($currentTestData.testName) Execution Time: $testRunDuration minutes<br />"
						$testCycle.emailSummary += "	$($currentTestData.testName) : $($testResult[0])  <br />"
						$testCycle.emailSummary += "$($testResult[1])"
						LogMsg "~~~~~~~~~~~~~~~TEST END : $($currentTestData.testName)~~~~~~~~~~"
					}
					catch
					{
						$testResult[0] = "ABORTED"
						$ErrorMessage =  $_.Exception.Message
						LogMsg "EXCEPTION : $ErrorMessage"   
					}
					if($testResult[0] -imatch "PASS")
					{
						$testSuiteResultDetails.totalPassTc = $testSuiteResultDetails.totalPassTc +1
						FinishLogTestCase $testcase
					}
					elseif($testResult[0] -imatch "FAIL")
					{
						$testSuiteResultDetails.totalFailTc = $testSuiteResultDetails.totalFailTc +1
						$caseLog = Get-Content -Raw $testCaseLogFile
						FinishLogTestCase $testcase "FAIL" "$($test.Name) failed." $caseLog
					}
					elseif($testResult[0] -imatch "ABORTED")
					{
						$testSuiteResultDetails.totalAbortedTc = $testSuiteResultDetails.totalAbortedTc +1
						$caseLog = Get-Content -Raw $testCaseLogFile
						FinishLogTestCase $testcase "ERROR" "$($test.Name) is aborted." $caseLog
					}
				} 
				$currentJobs = Get-Job
				foreach ( $job in $currentJobs )
				{
					$out = Remove-Job $job -Force -ErrorAction SilentlyContinue
					if ( $? )
					{
						LogMsg "Removed background job ID $($job.Id)."
					}
				}
				Write-Host $testSuiteResultDetails.totalPassTc,$testSuiteResultDetails.totalFailTc,$testSuiteResultDetails.totalAbortedTc
				#Back to Test Suite Main Logging
				$global:logFile = $testSuiteLogFile
			}
			else
			{
			LogMsg "Skipping $($currentTestData.Priority) test : $($currentTestData.testName)"
			}
		}
		else
		{
			LogErr "No Test Data found for $($test.Name).."
		}
	}
	
	LogMsg "Cycle Finished.. $($CycleName.ToUpper())"
	$EndTime =  [Datetime]::Now.ToUniversalTime()

	FinishLogTestSuite($testsuite)
	FinishLogReport

	$testSuiteResultDetails
 }

RunTestsOnCycle -cycleName $cycleName -xmlConfig $xmlConfig -Distro $Distro