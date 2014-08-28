	#v-shisav : STILL IN BETA VERSION

param($xmlConfig, [string] $Distro, [string] $cycleName)



<#
$xmlConfig = [XML](Get-Content .\XML\Azure_ICA.xml)
$Distro = "UBUNTULTS"
$cycleName = "BVTTests"
#$cycleName = "NetworkTests"
#>
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
    $tempResultSplitted = $tempResult.Split(" ")
    if($tempResultSplitted.Length -gt 1 )
    {
        Write-Host "Test Result =  $tempResult" -ForegroundColor Gray
    }
    $lastWord = ($tempResultSplitted.Length - 1)

    return $tempResultSplitted[$lastWord]
}

Function RunTestsOnCycle ($cycleName , $xmlConfig, $Distro )
{
	$StartTime = [Datetime]::Now.ToUniversalTime()
	LogMsg "Starting the Cycle - $($CycleName.ToUpper())"
	$OsImage = $xmlConfig.config.Azure.Deployment.Data.Distro | ? { $_.name -eq $Distro} | % {$_.OsImage.ToUpper()}
	Set-Variable -Name BaseOsImage -Value $OsImage -Scope Global
	LogMsg "Base image name - $BaseOsImage"
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
    if(Test-Path $reportFolder)
    {
        Remove-Item -Force -Recurse $reportFolder
    }
    New-Item -ItemType "Directory" $reportFolder
	StartLogReport("$reportFolder/report_$($testCycle.cycleName).xml")
	$testsuite = StartLogTestSuite "CloudTesting"
	
	foreach($test in $currentCycleData.test)
	{
		$currentTestData = GetCurrentTestData -xmlConfig $xmlConfig -testName $test.Name
		#$testType=$currentTestData.TestType.Tostring()
			
		# Initiate Connection With SQL Server and Database
		# note: this feature is currently disabled
#		LogMsg "Connecting to Database.."
#		$conn=ConnectSqlDB -sqlServer "LISINTER620-4" -sqlDBName "LISPerfTestDB"
#		Write-Host $conn
#		if ($conn.State -eq "Open")
#		{
#			LogMsg "Connected to the Database."
#		}
#		else
#		{
#			Throw "Failed to connect to the database."
#		}
#		Set-Variable -Name Conn -Value $conn -Scope Global
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
#		if(!$testSuiteRunID)
		{
#			$now = [Datetime]::Now.ToUniversalTime().ToString("MMddyyyyhhmmss")
#			$testSuiteRunID= $now + $cycleName + "3.2.0-35-virtual"
			
			
#			$testSuiteRunID=GenerateTestSuiteRunID -conn $conn
#			$now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy hh:mm:ss")
#			$testSuiteRunObj = CreateTestSuiteObject -testSuiteRunId $testSuiteRunID -testSuiteName $cycleName -server $server -linuxDistro $Distro -startTime $now -comments ""
				
#			Set-Variable -Name testSuiteRunObj -Value $testSuiteRunObj -Scope Global
#			$clusterObj= CreateClusterEnvObject -cluster $cluster -rdos $rdosVersion -fabric $fabricVersion -location $Location
			
			#Add Test Case details and result in DB
#			$tmp=AddTestSuiteDetailsinDB -conn $conn -testSuiteObj $testSuiteRunObj
#			AddClusterEnvDetailsinDB -conn $conn -clusterObj $clusterObj -testSuiteRunId $testSuiteRunID
		}
#		$testCaseRunObj = CreateTestCaseObject -testSuiteRunId $testSuiteRunID -testCaseId $testId -testName $test.Name -testDescp $test.Name -testCategory "BVT" -perfTool "none"
		
#		$vmEnvObj= CreateVMEnvObject -lisBuildBranch $lisBuildBranch -lisBuild $lisBuild -kernelVersion "3.2.0-35-virtual" -waagentBuild $waagentBuild -vmImageDetails $VMImageDetails
#		Set-Variable -Name testCaseRunObj -Value $testCaseRunObj -Scope Global
				
		if ($currentTestData)
		{
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
					$testResult = ""
					$LogDir = "$testDir\$($currentTestData.testName)"
					Set-Variable -Name LisLogDir -Value $LogDir -Scope Global
					LogMsg "~~~~~~~~~~~~~~~TEST STARTED : $($currentTestData.testName)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
					$testScriptPs1 = $currentTestData.testScriptPs1
					$startTime = [Datetime]::Now.ToUniversalTime()
					$command = ".\remote-scripts\" + $testScriptPs1
					LogMsg "Starting test $($currentTestData.testName)"
					$testResult = Invoke-Expression $command
                    $testResult = RefineTestResult1 -tempResult $testResult
					#AddTestCaseDetailsinDB -conn $conn -testCaseObj $testCaseRunObj -testSuiteRunId $testSuiteRunObj.testSuiteRunId
					#$testResult = "PASS"
					$endTime = [Datetime]::Now.ToUniversalTime()
#					$testCaseRunObj.startTime= $startTime
#					$testCaseRunObj.endTime = $endTime
					$vmRam= GetTestVMHardwareDetails -xmlConfigFile $xmlConfig -setupType $testSetup  -RAM
					$vmVcpu = GetTestVMHardwareDetails -xmlConfigFile $xmlConfig -setupType $testSetup  -VCPU 
#					$testCaseRunObj.vmRam=$vmRam
#					$testCaseRunObj.vmVcpu=$vmVcpu
					$testRunDuration = GetStopWatchElapasedTime $stopWatch "mm"
#					$testCaseRunObj.result=$testResult
#					AddTestCaseDetailsinDB -conn $conn -testCaseObj $testCaseRunObj -testSuiteRunId $testSuiteRunObj.testSuiteRunId

					$testCycle.emailSummary += "$($currentTestData.testName) Execution Time: $testRunDuration minutes<br />"
					$testCycle.emailSummary += "	$($currentTestData.testName) : $testResult <br />"
					$testCycle.htmlSummary += "<tr><td>$($currentTestData.testName) - Execution Time  : </td><td> $testRunDuration min</td></tr>"
					$testResultRow = ""
					if($testResult -imatch "PASS")
					{
						$testSuiteResultDetails.totalPassTc = $testSuiteResultDetails.totalPassTc +1
						$testResultRow = "<span style='color:green;font-weight:bolder'>PASS</span>"
						FnishLogTestCase $testcase
					}
					elseif($testResult -imatch "FAIL")
					{
						$testSuiteResultDetails.totalFailTc = $testSuiteResultDetails.totalFailTc +1
						$testResultRow = "<span style='color:red;font-weight:bolder'>FAIL</span>"
						FnishLogTestCase $testcase "FAIL" "$($test.Name) fail"
					}
					elseif($testResult -imatch "ABORTED")
					{
						$testSuiteResultDetails.totalAbortedTc = $testSuiteResultDetails.totalAbortedTc +1
						$testResultRow = "<span style='background-color:yellow;font-weight:bolder'>ABORT</span>"
						FnishLogTestCase $testcase "ERROR" "$($test.Name) abort"
					}
					$testCycle.htmlSummary += "<tr><td>	$($currentTestData.testName) </td><td> $testResultRow </td></tr>"
		  			LogMsg "~~~~~~~~~~~~~~~TEST END : $($currentTestData.testName)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
				}
				else	
				{
					$LogDir = "$testDir\$($currentTestData.testName)"
					Set-Variable -Name LisLogDir -Value $LogDir -Scope Global
					LogMsg "~~~~~~~~~~~~~~~TEST STARTED : $($currentTestData.testName)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
					$testScriptPs1 = $currentTestData.testScriptPs1
					$command = ".\remote-scripts\" + $testScriptPs1
					LogMsg "$command"
					LogMsg "Starting multiple tests : $($currentTestData.testName)"
					$startTime = [Datetime]::Now.ToUniversalTime()

					# Adding test case run details before starting test so that, sub test case result can be added while executing the test.
#					$testCaseRunObj.startTime= $startTime
#					$vmRam= GetTestVMHardwareDetails -xmlConfigFile $xmlConfig -setupType $testSetup  -RAM
#					$vmVcpu = GetTestVMHardwareDetails -xmlConfigFile $xmlConfig -setupType $testSetup  -VCPU 
#					$testCaseRunObj.vmRam=$vmRam
#					$testCaseRunObj.vmVcpu=$vmVcpu
#					AddTestCaseDetailsinDB -conn $conn -testCaseObj $testCaseRunObj -testSuiteRunId $testSuiteRunObj.testSuiteRunId
					#
					$testResult = Invoke-Expression $command
					$testResult = RefineTestResult2 -testResult $testResult
					 #For debug:
					#$testResult = @()
					#$testResult += "PASS"
					#$testResult += "	DemoSummery:TEST RUN SIMULATION. NO EXECUTION!<br />"

#					$endTime = [Datetime]::Now.ToUniversalTime()
#					$testCaseRunObj.endTime = $endTime

#					$testCaseRunObj.result=$testResult[0]
					
					#Update subtest details.
#					ParseAndAddSubtestResultsToDB -resultSummary $testResult[1] -conn $conn -testCaseRunObj $testCaseRunObj
					
					#Updating Result and Endtime.
#					UpdateTestCaseResultAndEndtime -conn $conn -testCaseObj $testCaseRunObj
					
					$testRunDuration = GetStopWatchElapasedTime $stopWatch "mm"
					$testRunDuration = $testRunDuration.ToString()
					$testCycle.emailSummary += "$($currentTestData.testName) Execution Time: $testRunDuration minutes<br />"
					$testCycle.emailSummary += "	$($currentTestData.testName) : $($testResult[0])  <br />"
					$testCycle.emailSummary += "$($testResult[1])"
					LogMsg "~~~~~~~~~~~~~~~TEST END : $($currentTestData.testName)~~~~~~~~~~"
					if($testResult[0] -imatch "PASS")
					{
						$testSuiteResultDetails.totalPassTc = $testSuiteResultDetails.totalPassTc +1
						FnishLogTestCase $testcase
					}
					elseif($testResult[0] -imatch "FAIL")
					{
						$testSuiteResultDetails.totalFailTc = $testSuiteResultDetails.totalFailTc +1
						FnishLogTestCase $testcase "FAIL" "$($test.Name) fail"
					}
					elseif($testResult[0] -imatch "ABORTED")
					{
						$testSuiteResultDetails.totalAbortedTc = $testSuiteResultDetails.totalAbortedTc +1
						FnishLogTestCase $testcase "ERROR" "$($test.Name) abort"
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
#	$now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy hh:mm:ss")
#	$testSuiteRunObj.endTime=$now
#	UpdateTestSuiteEndTime -conn $conn -testSuiteObj $testSuiteRunObj
#	AddVmEnvDetailsinDB -conn $conn -vmEnvObj $vmEnvObj -testSuiteRunId $testSuiteRunObj.testSuiteRunId
#	$tmp=DisconnectSqlDB -conn $conn
	$testSuiteResultDetails
 }

RunTestsOnCycle -cycleName $cycleName -xmlConfig $xmlConfig -Distro $Distro

