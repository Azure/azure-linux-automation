<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	$hs1Name = $isDeployed
	$testServiceData = Get-AzureService -ServiceName $hs1Name

    #Get VMs deployed in the service..
	$testVMsinService = $testServiceData | Get-AzureVM

	$hs1vm1 = $testVMsinService[0]
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
	$hs1vm1IP = $hs1vm1.IpAddress
	$hs1vm1Hostname = $hs1vm1.InstanceName
	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")

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

	$cmd1="./start-server.py -i1 -p $hs1vm1udpport -u yes && mv Runtime.log start-server.py.log -f"
	$cmd2="./start-client.py -c $($hs1vm1.IpAddress) -i1 -p $hs1vm1udpport -t20 -P 1 -u yes"

	$server = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeUdpPort $hs1vm1udpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$client = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeudpPort $hs1vm2udpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

	foreach ($Value in $SubtestValues) 
	{
        #Create New directory for each subtest value..
		mkdir $LogDir\$Value -ErrorAction SilentlyContinue | out-null

        #perform test for each test mode..
		foreach ($mode in $currentTestData.TestMode.Split(","))
		{      
			try
			{
				LogMsg "Starting test with $value parallel connections in $mode mode.."

				if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
				{
					$client.cmd = "./start-client.py -c $hs1vm1IP  -p $hs1vm1udpport -t10 -P$Value -u yes"
				}

				if(($mode -eq "URL") -or ($mode -eq "Hostname"))
				{
					$client.cmd = "./start-client.py -c $hs1vm1Hostname  -p $hs1vm1udpport -t10 -P$Value -u yes"
				}

                #Create Directory for each test mode to collect all results..
				mkdir $LogDir\$Value\$mode -ErrorAction SilentlyContinue | out-null

				$server.logDir = $LogDir + "\$Value\$mode"
				$client.logDir = $LogDir + "\$Value\$mode"
                
				$testResult=IperfClientServerUDPTestParallel $server $client
                LogMsg "Test Result for Parallel Connecitons : $Value Mode : $mode : $testResult"
			}
			catch
			{
				$ErrorMessage =  $_.Exception.Message
				LogErr "EXCEPTION : $ErrorMessage"   
			}
			Finally
			{
				$metaData = "$Value : $mode" 
				if (!$testResult)
				{
					$testResult = "Aborted"
				}
				$resultArr += $testResult
				$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
			}   
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