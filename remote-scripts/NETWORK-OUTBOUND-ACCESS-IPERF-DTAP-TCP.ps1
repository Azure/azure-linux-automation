Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
		$hs1Name = $isDeployed
		$testServiceData = Get-AzureService -ServiceName $hs1Name

#Get VMs deployed in the service..
		$testVMsinService = $testServiceData | Get-AzureVM

		$hs1vm1 = $testVMsinService
		$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint

		$hs1VIP = $hs1vm1Endpoints[0].Vip
		$hs1ServiceUrl = $hs1vm1.DNSName
		$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
		$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")

#$hs1vm2 = $testVMsinService[1]
#$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
		$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
		$dtapServerTcpport = "750"
		$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
		$dtapServerUdpport = "990"
		$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
		$dtapServerSshport = "22"
#$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP
        
	    RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
	    RemoteCopy -uploadTo $dtapServerIp -port $dtapServerSshport -files $currentTestData.files -username $user -password $password -upload
	    $suppressedOut = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo
	    $suppressedOut = RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "chmod +x * && rm -rf *.log *.txt" -runAsSudo

		$cmd1="./start-server.py -p $dtapServerTcpport && mv Runtime.log start-server.py.log -f"
		$cmd2="./start-client.py -c $dtapServerIp -p $dtapServerTcpport -t10"
		$server = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
		$client = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

		$testresult=IperfClientServerTest -server $server -client $client

	}
	catch{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"
	}

	Finally{

		if (!$testResult){
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
