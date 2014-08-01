<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$testResult = ""
$result = ""
$resultArr = @()
$filesUploaded = $false
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
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
	$cmd1="./start-server.py -i1 -p $dtapServerTcpport && mv Runtime.log start-server.py.log -f"
	$cmd2="./start-client.py -c $dtapServerIp -p $dtapServerTcpport -t20 -P$Value"

	$server = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
    LogMsg "$dtapServerIp set as iperf server"
	$client = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir
    LogMsg "$hs1VIP set as iperf client"
	foreach ($Value in $SubtestValues) 
	{
		try
		{
			LogMsg "Test Started for Parallel Connections $Value"
			$client.cmd = "./start-client.py -c $dtapServerIp -p $dtapServerTcpport -t20 -P$Value"
			mkdir $LogDir\$Value -ErrorAction SilentlyContinue | out-null
			$client.logDir = $LogDir + "\$Value"
			$server.logDir = $LogDir + "\$Value"
            function UploadFiles()
            {
	            RemoteCopy -uploadTo $server.ip -port $server.sshPort -files $server.files -username $server.user -password $server.password -upload
	            RemoteCopy -uploadTo $client.Ip -port $client.sshPort -files $client.files -username $client.user -password $client.password -upload
	            $suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "chmod +x *.py" -runAsSudo
	            $suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "chmod +x *.py" -runAsSudo

                return $true
            }
            if(!$filesUploaded)
            {
                $filesUploaded = UploadFiles
            }
	        $suppressedOut = RunLinuxCmd -username $client.user -password $client.password -ip $client.ip -port $client.sshPort -command "rm -rf *.txt *.log" -runAsSudo
	        $suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshPort -command "rm -rf *.txt *.log" -runAsSudo
			$testResult=IperfClientServerTestParallel -server $server -client $client
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







