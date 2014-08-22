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

$hs1vm1 = $testVMsinService[0]
$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint

$hs1VIP = $hs1vm1Endpoints[0].Vip
$hs1ServiceUrl = $hs1vm1.DNSName
$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")

$hs1vm2 = $testVMsinService[1]
$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh
$hs1vm1ProbePort = GetProbePort -Endpoints $hs1vm1Endpoints -usage TCPtest
$hs1vm2ProbePort = GetProbePort -Endpoints $hs1vm2Endpoints -usage TCPtest

$dtapServerTcpport = "750"
$dtapServerUdpport = "990"
$dtapServerSshport = "22"
#$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP
$cmd1="./start-server.py -p $hs1vm1ProbePort && mv Runtime.log start-server.py.log -f"
$cmd2="./start-server.py -p $hs1vm2ProbePort && mv Runtime.log start-server.py.log -f"


$server1 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
$server2 = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -nodeTcpPort $hs1vm2tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir

$testResult = ""

mkdir $LogDir\Server1CP -ErrorAction SilentlyContinue | out-null
mkdir $LogDir\Server2CP -ErrorAction SilentlyContinue | out-null
mkdir $LogDir\Server1LB -ErrorAction SilentlyContinue | out-null
mkdir $LogDir\Server2LB -ErrorAction SilentlyContinue | out-null

$server1.logDir = $LogDir + "\Server1CP"
$server2.logDir = $LogDir + "\Server2CP"

$result1=VerifyCustomProbe -server1 $server1 -server2 $server2 -probe "yes"
If ($result1 -eq "PASS") {
	LogMsg "CustomProbe Messages Observed on Probe Port"
	$testResult=$result1
} else {
	LogMsg "CustomProbe Messages Observed on Probe Port"
	$testResult=$result1
}

$server1.cmd = "./start-server.py -p $hs1vm1tcpport && mv Runtime.log start-server.py.log -f"
$server1.cmd = "./start-server.py -p $hs1vm2tcpport && mv Runtime.log start-server.py.log -f"
$server1.logDir = $LogDir + "\Server1LB"
$server2.logDir = $LogDir + "\Server2LB"

$suppressedOut = RunLinuxCmd -username $server2.user -password $server2.password -ip $server2.ip -port $server2.sshPort -command "rm -rf iperf-server.txt" -runAsSudo
$suppressedOut = RunLinuxCmd -username $server1.user -password $server1.password -ip $server1.ip -port $server1.sshPort -command "rm -rf iperf-server.txt" -runAsSudo

$result2=VerifyCustomProbe -server1 $server1 -server2 $server2 -probe "no"

If ($result2 -eq "PASS") {
	LogMsg "CustomProbe Messages Not Observed on Load Balancer Port"
	$testResult=$result2
} else {
	LogMsg "CustomProbe Messages Observed on Load Balancer Port"
	$testResult=$result2
}
return $testResult
