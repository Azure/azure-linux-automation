﻿Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
    #Collect deployment information
    $hsNames = $isDeployed
    $hsNames = $hsNames.Split("^")
    $hs1Name = $hsNames[0]
    $hs2Name = $hsNames[1]
    $testService1Data = Get-AzureService -ServiceName $hs1Name
    $testService2Data =  Get-AzureService -ServiceName $hs2Name
    $hs1vm1 = $testService1Data | Get-AzureVM
    $hs2vm1 = $testService2Data | Get-AzureVM
    $hs1vm1IP = $hs1vm1.IPaddress
    $hs2vm1IP = $hs2vm1.IPaddress
    $hs1vm1Hostname = $hs1vm1.InstanceName
    $hs2vm1Hostname = $hs2vm1.InstanceName
    $hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
    $hs2vm1Endpoints = $hs2vm1 | Get-AzureEndpoint
    $hs1VIP = $hs1vm1Endpoints[0].Vip
    $hs2VIP = $hs2vm1Endpoints[0].Vip
    $hs1ServiceUrl = $hs1vm1.DNSName
    $hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
    $hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
    $hs2ServiceUrl = $hs2vm1.DNSName
    $hs2ServiceUrl = $hs2ServiceUrl.Replace("http://","")
    $hs2ServiceUrl = $hs2ServiceUrl.Replace("/","")

    $hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
    $hs2vm1tcpport = GetPort -Endpoints $hs2vm1Endpoints -usage tcp

    $hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
    $hs2vm1udpport = GetPort -Endpoints $hs2vm1Endpoints -usage udp

    $hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
    $hs2vm1sshport = GetPort -Endpoints $hs2vm1Endpoints -usage ssh	
    $testPort = $hs1vm1UDPport + 10
	$iperfTimeoutSeconds = $currentTestData.iperfTimeoutSeconds

	$server = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport  -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodetcpPort $hs1vm1tcpport
    LogMsg "$hs1VIP set as iperf server."
	$client = CreateIperfNode -nodeIp $hs2VIP -nodeSshPort $hs2vm1sshport  -user $user -password $password -files $currentTestData.files -logDir $LogDir -nodetcpPort $hsvm1tcpport
    LogMsg "$hs2VIP set as iperf client."

    #Start test
    foreach ($mode in $currentTestData.TestMode.Split(","))
    { 
	    try
        {
            $testResult = $null
            if(($mode -eq "IP") -or ($mode -eq "VIP"))
            {
	            $client.cmd ="python start-client.py -c $hs1vm1IP -p $testPort  -t$iperfTimeoutSeconds -u yes"
	        }
            if(($mode -eq "URL") -or ($mode -eq "Hostname"))
            {
	            $client.cmd ="python start-client.py -c $hs1vm1Hostname -p $testPort  -t$iperfTimeoutSeconds -u yes"
	        }
            LogMsg "Starting the test in $mode mode.."
            $server.cmd="python start-server.py -p $testPort -u yes  && mv Runtime.log start-server.py.log"
	        #$cmd2="python start-client.py -c $($hs1vm1.IpAddress)  -p $hs1vm1tcpport -t10"
	        mkdir $LogDir\$mode -ErrorAction SilentlyContinue | out-null
            $server.LogDir = "$LogDir\$mode"
            $client.LogDir = "$LogDir\$mode"
            $testResult = IperfClientServerUDPNonConnectivity -server $server -client $client
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