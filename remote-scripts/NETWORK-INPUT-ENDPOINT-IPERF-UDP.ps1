Import-Module .\TestLibs\RDFELibs.psm1 -Force
$testResult = ""
$result = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	$hsNames = $isDeployed.Split("^")
	$hs1Name = $hsNames[0]
	$hs2Name = $hsNames[1]
	$testServiceData = Get-AzureService -ServiceName $hs1Name
	$dtapServiceData = Get-AzureService -ServiceName $hs2Name
	#Extract Test VM Data
	$testVMsinService = $testServiceData | Get-AzureVM
	$hs1vm1 = $testVMsinService
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
	#Extract DTAP VM data
   	$dtapServer = $dtapServiceData | Get-AzureVM
	$dtapServerEndpoints = $dtapServer | Get-AzureEndpoint
	$dtapServerIp = $dtapServerEndpoints[0].Vip
	$dtapServerUrl = $dtapServer.DNSName
	$dtapServerUrl = $dtapServerUrl.Replace("http://","")
	$dtapServerUrl = $dtapServerUrl.Replace("/","")
	$dtapServerTcpport = GetPort -Endpoints $dtapServerEndpoints -usage tcp
	$dtapServerUdpport = GetPort -Endpoints $dtapServerEndpoints -usage udp
	$dtapServerSshport = GetPort -Endpoints $dtapServerEndpoints -usage ssh
	LogMsg "Test Machine : $hs1VIP : $hs1vm1sshport"
	LogMsg "DTAP Machine : $dtapServerIp : $hs1vm1sshport"
	$iperfTimeoutSeconds = $currentTestData.iperfTimeoutSeconds

	$server = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeUdpPort $dtapServerUdpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$client = CreateIperfNode -nodeIp $dtapServerIp  -nodeSshPort $dtapServerSshport -nodeudpPort $hs1vm1udpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

	foreach ($mode in $currentTestData.TestMode.Split(","))
	{
		try
		{
			$testResult = $null
			LogMsg "Test Started in $mode mode.."
			mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null

			$server.cmd ="python start-server.py -i1 -p $hs1vm1udpport -u yes && mv Runtime.log start-server.py.log -f"

			if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
			{
				$client.cmd ="python start-client.py -c $hs1VIP -i1 -p $hs1vm1udpport -t$iperfTimeoutSeconds -u yes -l 1420"
			}

			if(($mode -eq "URL") -or ($mode -eq "Hostname"))
			{
				$client.cmd ="python start-client.py -c $hs1ServiceUrl -i1 -p $hs1vm1udpport -t$iperfTimeoutSeconds -u yes -l 1420"
			}
			$server.logDir = "$LogDir\$mode"
			$client.logDir = "$LogDir\$mode"
			$testResult =IperfClientServerUDPTest -server $server -client $client
			LogMsg "$($currentTestData.testName) : $mode : $testResult"
		}
		catch
		{
			$ErrorMessage =  $_.Exception.Message
			LogMsg "EXCEPTION : $ErrorMessage"   
		}
		Finally
		{
			$metaData = $mode 
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
