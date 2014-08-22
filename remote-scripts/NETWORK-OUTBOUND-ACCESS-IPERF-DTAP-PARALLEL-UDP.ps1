<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$testResult = ""
$result = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
#$isDeployed = "ICA-PublicEndpoint-Ubuntu1404beta2-4-2-5-5-18"
if($isDeployed)
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

	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$dtapServerTcpport = "750"
	$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
	$dtapServerUdpport = "990"
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
	$dtapServerSshport = "22"
#$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP
	$cmd1="./start-server.py -p $dtapServerUDPport -u yes && mv Runtime.log start-server.py.log -f"
	$cmd2="./start-client.py -c $dtapServerIp -p $dtapServerUDPport -t20 -P1 -u yes"

	$a = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$b = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

	$resultArr = @()
	$result = "", ""
	foreach ($Value in $SubtestValues) 
	{
		try
		{

			LogMsg "Test Started for Parallel Connections $Value"
			$b.cmd = "./start-client.py -c $dtapServerIp -p $dtapServerUDPport -t20 -P$Value -u yes"
			mkdir $LogDir\$Value -ErrorAction SilentlyContinue | out-null
			$b.logDir = $LogDir + "\$Value"
			$a.logDir = $LogDir + "\$Value"
			$server = $a
			$client = $b

			$suppressedOut = RunLinuxCmd -username $a.user -password $a.password -ip $a.ip -port $a.sshport -command "rm -rf iperf-server.txt" -runAsSudo

			$testResult=IperfClientServerUDPTestParallel $server $client
			LogMsg "Test Status for Parallel Connections $Value - $testResult"
		}

		catch
		{
			$ErrorMessage =  $_.Exception.Message
			LogMsg "EXCEPTION : $ErrorMessage"
		}

		Finally
		{
			$metaData = $Value 
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



