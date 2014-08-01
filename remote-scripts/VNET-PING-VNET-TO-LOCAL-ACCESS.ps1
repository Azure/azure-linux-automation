<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$Subtests= $currentTestData.SubtestValues
$SubtestValues = $Subtests.Split(",") 
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
#region EXTRACT ALL INFORMATION ABOUT DEPLOYED VMs
#Extract the VM information..
	$hsNames = $isDeployed
	$hsNames = $hsNames.Split("^")
	$hs1Name = $hsNames[0]
	$hs2Name = $hsNames[1]
	$testService1Data = Get-AzureService -ServiceName $hs1Name
	$testService2Data =  Get-AzureService -ServiceName $hs2Name
#Get VMs deployed in the service..
	$hs1vms = $testService1Data | Get-AzureVM
	$hs2vms = $testService2Data | Get-AzureVM
	$hs1vm1 = $hs1vms[0]
	$hs1vm2 = $hs1vms[1]
	$hs2vm1 = $hs2vms[0]
	$hs2vm2 = $hs2vms[1]
#Get the IP addresses
	$hs1vm1IP = $hs1vm1.IPaddress
	$hs1vm2IP = $hs1vm2.IPaddress
	$hs2vm1IP = $hs2vm1.IPaddress
	$hs2vm2IP = $hs2vm2.IPaddress
	$hs1vm1Hostname = $hs1vm1.InstanceName
	$hs1vm2Hostname = $hs1vm2.InstanceName
	$hs2vm1Hostname = $hs2vm1.InstanceName
	$hs2vm2Hostname = $hs2vm2.InstanceName
	$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
	$hs1vm2Endpoints = $hs1vm2 | Get-AzureEndpoint
	$hs2vm1Endpoints = $hs2vm1 | Get-AzureEndpoint
	$hs2vm2Endpoints = $hs2vm2 | Get-AzureEndpoint
	$hs1VIP = $hs1vm1Endpoints[0].Vip
	$hs2VIP = $hs2vm1Endpoints[0].Vip
	$hs1ServiceUrl = $hs1vm1.DNSName
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
	$hs2ServiceUrl = $hs2vm1.DNSName
	$hs2ServiceUrl = $hs2ServiceUrl.Replace("http://","")
	$hs2ServiceUrl = $hs2ServiceUrl.Replace("/","")
	$hs1vm1tcpport = GetPort -Endpoints $hs1vm1Endpoints -usage tcp
	$hs1vm2tcpport = GetPort -Endpoints $hs1vm2Endpoints -usage tcp
	$hs2vm1tcpport = GetPort -Endpoints $hs2vm1Endpoints -usage tcp
	$hs2vm2tcpport = GetPort -Endpoints $hs2vm2Endpoints -usage tcp
	$hs1vm1udpport = GetPort -Endpoints $hs1vm1Endpoints -usage udp
	$hs1vm2udpport = GetPort -Endpoints $hs1vm2Endpoints -usage udp
	$hs2vm1udpport = GetPort -Endpoints $hs2vm1Endpoints -usage udp
	$hs2vm2udpport = GetPort -Endpoints $hs2vm2Endpoints -usage udp
	$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh	
	$hs1vm2sshport = GetPort -Endpoints $hs1vm2Endpoints -usage ssh	
	$hs2vm1sshport = GetPort -Endpoints $hs2vm1Endpoints -usage ssh	
	$hs2vm2sshport = GetPort -Endpoints $hs2vm2Endpoints -usage ssh	
	$SSHDetails = Get-SSHDetailofVMs -DeployedServices $isDeployed
	$HostnameDIPDetails = Get-AllVMHostnameAndDIP $isDeployed
#endregion

	try
	{
#region CONFIGURE VNET VMS AND MAKE THEM READY FOR VNET TEST EXECUTION...

#region DEFINE LOCAL NET VMS
		$dnsServer = CreateVMNode -nodeIp "192.168.3.120" -nodeSshPort 22 -user "root" -password "redhat"
		$nfsServer = CreateVMNode -nodeIp "192.168.3.125" -nodeSshPort 22 -user "root" -password "redhat"
		$mysqlServer = CreateVMNode -nodeIp "192.168.3.127" -nodeSshPort 22 -user "root" -password "redhat" -nodeHostname "ubuntumysql"
#endregion

#region DEFINE A INTERMEDIATE VM THAT WILL BE USED FOR ALL OPERATIONS DONE ON THE LOCAL NET VMS [DNS SERVER, NFSSERVER, MYSQL SERVER]
		$intermediateVM = CreateVMNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -nodeDip $hs1vm1.IpAddress -nodeHostname $hs1vm1Hostname
#endregion
#region Upload all files to VNET VMS.. [All files are uploaded at once, to minimise re-upload process, at the execution time of every child method]
		$currentWindowsfiles = $currentTestData.files
		UploadFilesToAllDeployedVMs -SSHDetails $SSHDetails -files $currentWindowsfiles 
#Make python files executable
		RunLinuxCmdOnAllDeployedVMs -SSHDetails $SSHDetails -command "chmod +x *.py"
#endregion
#region Configure VNET VMS.. [edit resolv.conf file and edit hosts files]
        if($EconomyMode -and $vnetIsAllConfigured)
        {
            $isAllConfigured = "True"
        }
        else
        {
		ConfigureVNETVms -SSHDetails $SSHDetails	
#endregion
#region Upload all files to LOCAL NET VMS.. [All files are uploaded to minimise reupload process at the execution of every child method]
		$currentLinuxFiles = ConvertFileNames -ToLinux -currentWindowsFiles $currentTestData.files -expectedLinuxPath "/home/$user"
        #Assuming that all files will be available at VNET VMS..
        #RemoteCopyRemoteVM -upload -intermediateVM $intermediateVM -remoteVM $dnsServer  -remoteFiles $currentLinuxFiles
        #RemoteCopyRemoteVM -upload -intermediateVM $intermediateVM -remoteVM $nfsServer  -remoteFiles $currentLinuxFiles
        #RemoteCopyRemoteVM -upload -intermediateVM $intermediateVM -remoteVM $mysqlServer  -remoteFiles $currentLinuxFiles

        # Make them executable..
        #RunLinuxCmdOnRemoteVM -intermediateVM $intermediateVM -remoteVM $dnsServer -remoteCommand "chmod +x /home/$user/*.py" -runAsSudo
        #RunLinuxCmdOnRemoteVM -intermediateVM $intermediateVM -remoteVM $nfsServer -remoteCommand "chmod +x /home/$user/*.py" -runAsSudo
        #RunLinuxCmdOnRemoteVM -intermediateVM $intermediateVM -remoteVM $mysqlServer -remoteCommand "chmod +x /home/$user/*.py" -runAsSudo
#endregion

#region CONFIGURE DSN SERVER WITH IP ADDRESSES OF DEPLOYED VNET VMs...
		ConfigureDnsServer -intermediateVM $intermediateVM -DnsServer $dnsServer -HostnameDIPDetails $HostnameDIPDetails
#endregion

		$isAllConfigured = "True"
        $vnetIsAllConfigured = $true
        }
#endregion
	}
	catch
	{
		$isAllConfigured = "False"
		$ErrorMessage =  $_.Exception.Message
		LogErr "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{

	}
	if ($isAllConfigured = "True")
	{
#region TEST EXECUTION  


		$pingFrom = CreatePingNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -files $currentTestData.files -logDir $LogDir 

		$resultArr = @()
		foreach ($Value in $SubtestValues) 
		{
			mkdir $LogDir\$Value -ErrorAction SilentlyContinue | out-null
			switch ($Value)
			{

				"HS1VM1" {
					$pingFrom = CreateVMNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -user $user -password $password -logDir $LogDir
				}
				"HS1VM2" {
					$pingFrom = CreateVMNode -nodeIp $hs1VIP -nodeSshPort $hs1vm2sshport -user $user -password $password -logDir $LogDir
				}
				"HS2VM1" {
					$pingFrom = CreateVMNode -nodeIp $hs2VIP -nodeSshPort $hs2vm1sshport -user $user -password $password -logDir $LogDir
				}
				"HS2VM2" {
					$pingFrom = CreateVMNode -nodeIp $hs2VIP -nodeSshPort $hs2vm2sshport -user $user -password $password -logDir $LogDir
				}

# Reference - Output of tested virtual machines -

#PS C:\Users\v-shisav> $hs1vm1IP
#192.168.4.198

#PS C:\Users\v-shisav> $hs1vm2IP
#192.168.4.134

#PS C:\Users\v-shisav> $hs2vm1IP
#192.168.4.135

#PS C:\Users\v-shisav> $hs2vm2IP
#192.168.4.199
			}
			foreach ($mode in $currentTestData.TestMode.Split(","))
			{ 
				try
				{

					if(($mode -eq "IP") -or ($mode -eq "VIP") -or ($mode -eq "DIP"))
					{
						Write-Host $VnetTestIP
						$pingFrom.cmd = "./ping.py -x $($mysqlServer.ip) -c 10"
					}

					if(($mode -eq "URL") -or ($mode -eq "Hostname"))
					{
						Write-Host $VnetTestHostName
						$pingFrom.cmd = "./ping.py -x $($mysqlServer.hostname)  -c 10"
					}
					LogMsg "Test Started for $Value in $mode mode.."

					mkdir $LogDir\$Value\$mode -ErrorAction SilentlyContinue | out-null
					$pingFrom.logDir = $LogDir + "\$Value\$mode"

					$testResult = DoPingTest -pingFrom $pingFrom -isVNET

					LogMsg "Test Status for $mode mode - $testResult"
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

#endregion
	}
	else
	{
		LogErr "Test Aborted due to Configuration Failure.."
		$testResult = "Aborted"
		$resultArr += $testResult
	}
}
else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#region Clenup the DNS server.

#$dnsServer.cmd = "/home/$user/CleanupDnsServer.py"
#RunLinuxCmdOnRemoteVM -intermediateVM $intermediateVM -remoteVM $dnsServer -runAsSudo

#endregion

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed

#Return the result and summery to the test suite script..
return $result , $resultSummary
