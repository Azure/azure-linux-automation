<#-------------Create Deployment Start------------------#>

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if (!$isDeployed)
{
	exit
}

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
$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP

$cmd1="./start-server.py -i1 -p $dtapServerTcpport && mv Runtime.log start-server.py.log -f"
$cmd2="./start-client.py -c $dtapServerIp -i1 -p $dtapServerTcpport -t20"
$a = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
$b = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

#IperfClientServerTest -serverIp $dtapServerIp -serverSshPort $dtapServerSshport -serverTcpport $dtapServerTcpport -serverIperfCmd $cmd1 -clientIp $hs1VIP -clientSshPort  -clientTcpport  -clientIperfCmd 
$result=IperfClientServerTest $a $b
return $result



