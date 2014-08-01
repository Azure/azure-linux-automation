<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",")
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
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

	$cmd1="./start-client.py -c $hs1VIP -p $hs1vm1tcpport -t20 -P$Value"
	$cmd2="./start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"

	$client = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$server = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

	foreach ($Value in $SubtestValues) 
    {
		LogMsg "Test Started for Parallel Connections $Value"
		mkdir $LogDir\$Value -ErrorAction SilentlyContinue | out-null
		foreach ($mode in $currentTestData.TestMode.Split(","))
        {    #.1............ Added foreach for modes...
            $testResult = ""
			try{
                RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -username $user -password $password -files $currentTestData.files -upload
                RemoteCopy -uploadTo $dtapServerIp -port $dtapServerSshport -files $currentTestData.files -username $user -password $password -upload
                $suppressedOut = RunLinuxCmd -ip $hs1VIP -username $user -password $password -port $hs1vm1sshport -command "chmod +x * && rm -rf *.txt *.log" -runAsSudo
                $suppressedOut = RunLinuxCmd -ip $dtapServerIp -username $user -password $password -port $dtapServerSshport -command "chmod +x * && rm -rf *.txt *.log" -runAsSudo
				LogMsg "Starting the test in $mode.."
				if(($mode -eq "IP") -or ($mode -eq "VIP"))
                {
					$client.cmd = "./start-client.py -c $hs1VIP  -p $hs1vm1tcpport -t20 -P$Value"
				}
				if(($mode -eq "URL") -or ($mode -eq "Hostname"))
                {
					$client.cmd = "./start-client.py -c $hs1ServiceUrl  -p $hs1vm1tcpport -t20 -P$Value"
				}
				mkdir $LogDir\$Value\$mode -ErrorAction SilentlyContinue | out-null
				$server.logDir = $LogDir + "\$Value" + "\$mode"
				$client.logDir = $LogDir + "\$Value" + "\$mode"
				$testResult = IperfClientServerTestParallel $server $client
			}
			catch
            {
				$ErrorMessage =  $_.Exception.Message
				LogMsg "EXCEPTION : $ErrorMessage"
				$testResult = "Aborted"
			}
			Finally
			{
				$metaData = $Value + " : " + $mode  
				if (!$testResult){
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