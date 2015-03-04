Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
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

		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		RemoteCopy -uploadTo $dtapServerIp -port $dtapServerSshport -files $currentTestData.files -username $user -password $password -upload
		$suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo
		$suppressedOut = RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo

		$cmd1="python start-server.py -p $dtapServerTcpport && mv Runtime.log start-server.py.log -f"
		$cmd2="python start-client.py -c $dtapServerIp -p $dtapServerTcpport -t$iperfTimeoutSeconds"
		$server = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
		$client = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir
		$testresult=IperfClientServerTest -server $server -client $client
		LogMsg "$($currentTestData.testName) : $testResult"
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
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result