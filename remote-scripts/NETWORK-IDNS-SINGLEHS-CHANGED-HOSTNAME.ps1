<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$result = ""
$testResult = ""
$resultArr = @()
$resultSummary = ""
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
	$hs1Name = $isDeployed
	$testServiceData = Get-AzureService -ServiceName $hs1Name

    #Get VMs deployed in the service..
	$testVMsinService = $testServiceData | Get-AzureVM
	$hs1vm1 = $testVMsinService[0]
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
	$hs1vm1IP = $hs1vm1.IpAddress
	$hs1vm1Hostname = $hs1vm1.InstanceName
	$hs1vm2 = $testVMsinService[1]
	$hs1vm2IP = $hs1vm2.IpAddress
	$hs1vm2Hostname = $hs1vm2.InstanceName	
	$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
	$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
	$hs1vm2udpport = GetPort -Endpoints $hs1vm2Endpoints -usage udp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
	$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh
	$hs1vm1NewHostname = $hs1vm1Hostname + "-New"
	$hs1vm2NewHostname = $hs1vm2Hostname + "-New"
	$vm1 = CreateIdnsNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -logDir $LogDir -nodeDip $hs1vm1IP -nodeUrl $hs1ServiceUrl -nodeDefaultHostname $hs1vm1Hostname -nodeNewHostname $hs1vm1NewHostname
	$vm2 = CreateIdnsNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -user $user -password $password -logDir $LogDir -nodeDip $hs1vm2IP -nodeUrl $hs1ServiceUrl -nodeDefaultHostname $hs1vm2Hostname -nodeNewHostname $hs1vm2NewHostname
    $retryInterval = 30
    $waitAfterChangingHostname = 180
	$resultArr = @()
    $vm1DefaultFqdn = $null 
    $vm2DefaultFqdn =$null
    $filesUploaded = $false
    $uploadFiles = 
    {
            RemoteCopy -upload -uploadTo $vm1.ip -port $vm1.SShport -username $vm1.user -password $vm1.password -files .\remote-scripts\temp.txt
			RemoteCopy -upload -uploadTo $vm2.ip -port $vm2.SShport -username $vm2.user -password $vm2.password -files .\remote-scripts\temp.txt
            $filesUploaded = $true
    }
	foreach ($mode in $currentTestData.TestMode.Split(","))
	{
		LogMsg "Starting test for : $mode.."
		mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
		$vm1.logDir = "$LogDir\$mode"
		$vm2.logDir = "$LogDir\$mode"
		try
		{
            if(!$filesUploaded)
            {
                Invoke-Command -ScriptBlock $uploadFiles
            }
            $testResult = ""
            if(!$vm1DefaultFqdn -and !$vm2DefaultFqdn)
            {
                $vm1DefaultFqdn = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "hostname --fqdn"
                $vm2DefaultFqdn = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "hostname --fqdn"
                $vm1.hostname = $hs1vm1Hostname
                $vm2.hostname = $hs1vm2Hostname
                $vm1.fqdn = $vm1DefaultFqdn
                $vm2.fqdn = $vm2DefaultFqdn
                $vm1Default = $vm1
                $vm2Default = $vm2
                $vm1DefaultHostname =  $hs1vm1Hostname
                $vm1NewHostname = "$vm1DefaultHostname-New"
                $vm2DefaultHostname = $hs1vm2Hostname
                $vm2NewHostname = "$vm2DefaultHostname-New"
                $vm1NewFqdn = $vm1DefaultFqdn.Replace($vm1DefaultHostname, $vm1NewHostname) 
                $vm2NewFqdn = $vm2DefaultFqdn.Replace($vm2DefaultHostname, $vm2NewHostname) 
            }
            $out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -rf *.txt *.log" -runAsSudo 
            $out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm2sshport -command "rm -rf *.txt *.log" -runAsSudo 
			switch ($mode)
			{
				"VerifyDefaultHostname" {
                    do
					{
                        $vm1.hostname = $hs1vm1Hostname
						$vm2.hostname = $hs1vm2Hostname
                        $vm1Default = $vm1
                        $vm2Default = $vm2
					    $nslookupResult1 = DoNslookupTest -vm1 $vm1 -vm2 $vm2
                        $digResult1 = DoDigTest -vm1 $vm1 -vm2 $vm2
						if(($nslookupResult1 -imatch "FAIL") -or ($digResult1 -imatch "FAIL"))
						{
							LogMsg "Try $($counter+1). Waiting 30 seconds more.."
							WaitFor -seconds $retryInterval
						}
						else
						{
							break
						}
						$counter += 1
					}
					while ((($nslookupResult1 -eq "FAIL") -or ($digResult1 -eq "FAIL")) -and $counter -le 10 )

                    if (($nslookupResult1 -eq "PASS") -and ($digResult1 -eq "PASS"))
					{
						$testResult = "PASS"
                        LogMsg "NSLOOKUP : PASS. Expected behavior!"
                        LogMsg "DIG : PASS. Expected behavior!"
					}
					else
					{
						$testResult = "FAIL"
                        if($nslookupResult3 -eq "PASS")
                        {
                            LogErr "NSLOOKUP : FAIL. Unexpected behavior! "
                        }
                        if($digResult3 -eq "PASS")
                        {
                            LogErr "DIG : FAIL. Unexpected behavior!"
                        }
					}
                    LogMsg "VerifyDefaultHostname : $testResult"
				}

				"VerifyChangedHostname" {

                    $vm1.hostname = $vm1NewHostname
                    $vm2.hostname = $vm2NewHostname
                    $vm1.fqdn = $vm1NewFqdn
                    $vm2.fqdn = $vm2NewFqdn

					LogMsg "Changing the hostname of VM2"
					$suppressedOut = RunLinuxCmd -username $vm2.user -password $vm2.password -ip $vm2.Ip -port $vm2.SshPort -command "hostname $hs1vm2NewHostname" -runAsSudo
#it takes approximately 5 minutes [calculated after 5 dry runs] to reflect the changed host name..
#So, Let's wait for 5 minutes.. There is no point to check whether hostname is changed or not in every 1 minute..
					WaitFor -seconds $waitAfterChangingHostname
					$counter = 1 
					do
					{    
                        LogMsg "VM2 New hostname : $($vm2.hostname)"
                        LogMsg "VM2 New fqdn : $($vm2.fqdn)"

						$nslookupResult = ""
                        $digResult = ""
                        $nslookupResult2 = DoNslookupTest -vm1 $vm1 -vm2 $vm2
                        $digResult2 = DoDigTest -vm1 $vm1 -vm2 $vm2
						if(($nslookupResult2 -ne "PASS") -or ($digResult2 -ne "PASS"))
						{
							LogMsg "Try $($counter+1). Waiting 30 seconds more.."
							WaitFor -seconds $retryInterval
						}
						else
						{
							break
						}
						$counter += 1
					}
					while ((($nslookupResult2 -eq "FAIL") -or ($digResult2 -eq "FAIL")) -and $counter -le 10 )

						if (($nslookupResult2 -eq "PASS") -and ($digResult2 -eq "PASS"))
						{
							$testResult = "PASS"
						}
						else
						{
							$testResult = "FAIL"
						}
                    LogMsg "VerifyChangedHostname : $testResult"
				}

				"VerifyDefaultHostnameNotAccessible" {
                    $vm1.hostname = $vm1DefaultHostname
                    $vm2.hostname = $vm2DefaultHostname
                    $vm1.fqdn = $vm1DefaultFqdn
                    $vm2.fqdn = $vm2DefaultFqdn
                    do
					{
						LogMsg "VM2 Default hostname : $($vm2.hostname)"
                        LogMsg "VM2 Default fqdn : $($vm2.fqdn)"
					    $nslookupResult3 = DoNslookupTest -vm1 $vm1 -vm2 $vm2
                        $digResult3 = DoDigTest -vm1 $vm1 -vm2 $vm2
						if(($nslookupResult3 -imatch "PASS") -or ($digResult3 -imatch "PASS"))
						{
							if($nslookupResult3 -eq "PASS")
                            {
                                LogErr "NSLOOKUP : PASS. Unexpected behavior! "
                            }
                            if($digResult3 -eq "PASS")
                            {
                                LogErr "DIG : PASS. Unexpected behavior!"
                            }
							WaitFor -seconds $retryInterval
						}
						else
						{
							break
						}
						$counter += 1
					}
					while ((($nslookupResult3 -eq "PASS") -or ($digResult3 -eq "PASS")) -and $counter -le 10 )

                    if (($nslookupResult3 -eq "FAIL") -and ($digResult3 -eq "FAIL"))
					{
						$testResult = "PASS"
                        LogMsg "NSLOOKUP : FAIL. Expected behavior!"
                        LogMsg "DIG : FAIL. Expected behavior!"
					}
					else
					{
						$testResult = "FAIL"
                        if($nslookupResult3 -eq "PASS")
                        {
                            LogErr "NSLOOKUP : PASS. Unexpected behavior! "
                        }
                        if($digResult3 -eq "PASS")
                        {
                            LogErr "DIG : PASS. Unexpected behavior!"
                        }
					}
                    LogMsg "VerifyDefaultHostnameNotAccessible : $testResult"
				}

				"ResetHostnameToDefaultAndVerify" {


					LogMsg "Resetting the hostname of VM2"
					$suppressedOut = RunLinuxCmd -username $vm2.user -password $vm2.password -ip $vm2.Ip -port $vm2.SshPort -command "hostname $hs1vm2Hostname" -runAsSudo
                    #it takes approximately 5 minutes [calculated after 5 dry runs] to reflect the changed host name..
                    #So, Let's wait for 5 minutes.. There is no point to check whether hostname is changed or not in every 1 minute..
					WaitFor -seconds $waitAfterChangingHostname                   
                    $vm1.hostname = $vm1DefaultHostname
                    $vm2.hostname = $vm2DefaultHostname
                    $vm1.fqdn = $vm1DefaultFqdn
                    $vm2.fqdn = $vm2DefaultFqdn
					$counter = 0 
					do
					{
                        LogMsg "VM2 Default hostname : $($vm2.hostname)"
                        LogMsg "VM2 Default fqdn : $($vm2.fqdn)"
						$nslookupResult4 = DoNslookupTest -vm1 $vm1 -vm2 $vm2
                        $digResult4 = DoDigTest -vm1 $vm1 -vm2 $vm2
						if(($nslookupResult4 -imatch "FAIL") -or ($digResult4 -imatch "FAIL"))
						{
							LogMsg "Try $($counter+1). Waiting 30 seconds more.."
                            WaitFor -seconds $retryInterval
						}
						else
						{
							break
						}
						$counter += 1
					}
					while ((($nslookupResult4 -eq "FAIL") -or ($digResult4 -eq "FAIL")) -and $counter -le 10 )

						if (($nslookupResult4 -eq "PASS") -or ($digResult4 -eq "PASS"))
						{
							$testResult = "PASS"
						}
						else
						{
							$testResult = "FAIL"
						}
                    LogMsg "ResetHostnameToDefaultAndVerify : $testResult"
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
			$metaData = "$mode"
			if (!$testResult)
			{
				$testResult = "Aborted"
			}
			$resultArr += $testResult
			$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
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
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result,$resultSummary