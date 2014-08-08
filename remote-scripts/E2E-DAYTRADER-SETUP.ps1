<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$passwd = $password.Replace('"','')

Function CreateIbmTar($ip,$port)
{
	Logmsg "Creating IBMWebSphere tar .. "
	LogMsg "distro:  $Distro"
	if($Distro -imatch "UBUNTU")
	{
		$out = RemoteCopy -uploadTo $ip -port $port -files .\remote-scripts\Packages\IBMWebSphere\ibm-java-x86-64-sdk_6.0-10.1_amd64.deb -username $user -password $password -upload 2>&1 | Out-Null
	}
	else
	{
		$out = RemoteCopy -uploadTo $ip -port $port -files .\remote-scripts\Packages\IBMWebSphere\ibm-java-x86_64-sdk-6.0-9.1.x86_64.rpm -username $user -password $password -upload 2>&1 | Out-Null
	}
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "mkdir IBMWebSphere" -runAsSudo 2>&1 | Out-Null
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "tar -xvzf daytrader.tar.gz -C IBMWebSphere" -runAsSudo 2>&1 | Out-Null
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "mv wasce_setup-2.1.1.6-unix.bin ibm-java* IBMWebSphere/" -runAsSudo 2>&1 | Out-Null
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "chmod -R +x IBMWebSphere/" -runAsSudo 2>&1 | Out-Null
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "tar -cvzf IBMWebSphere.tar.gz IBMWebSphere/" -runAsSudo 2>&1 | Out-Null
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "cp IBMWebSphere.tar.gz /tmp" -runAsSudo 2>&1 | Out-Null
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "rm -rf IBMWebSphere/" -runAsSudo 2>&1 | Out-Null
	$istar = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "ls /tmp" -runAsSudo
	if($istar -imatch "IBMWebSphere.tar")
	{
		Logmsg "Creating IBMWebsphere tar completed .. "
		return $true
	}
	else
	{
		Logerr "Creating IBMWebsphere tar Failed .. "
		return $false
	}
}

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig

if ($isDeployed)
{
	try
	{
		$testServiceData = Get-AzureService -ServiceName $isDeployed

		#Get VMs deployed in the service..
		$testVMsinService = $testServiceData | Get-AzureVM
		try{
			if($currentTestData.E2ESetupCmdLineArgument -imatch "loadbalancer_setup")
			{
				$hs1bvm = $testVMsinService[0]
				$hs1fevm1 = $testVMsinService[1]
				$hs1fevm2 = $testVMsinService[2]
				$hs1fevm3 = $testVMsinService[3]
				
				$hs1bvmEndpoints = $hs1bvm | Get-AzureEndpoint
				$hs1bvmsshport = GetPort -Endpoints $hs1bvmEndpoints -usage ssh
				
				$hs1VIP = $hs1bvmEndpoints.Vip
				
				$hs1ServiceUrl = $hs1bvm.DNSName
				$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
				$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
				
				$wsurl = "http:`/`/"+$hs1ServiceUrl.Replace(" ","")+":8080"
				$dturl = "$wsurl`/daytrader"
				LogMsg "URL : $hs1ServiceUrl"
				
				$beip = $hs1bvm.Ipaddress.ToString()
				$fe1ip = $hs1fevm1.Ipaddress.ToString()
				$fe2ip = $hs1fevm2.Ipaddress.ToString()
				$fe3ip = $hs1fevm3.Ipaddress.ToString()
			
				$hs1fevm1Endpoints = $hs1fevm1 | Get-AzureEndpoint
				$hs1fevm1sshport = GetPort -Endpoints $hs1fevm1Endpoints -usage ssh
			
				$hs1fevm2Endpoints = $hs1fevm2 | Get-AzureEndpoint
				$hs1fevm2sshport = GetPort -Endpoints $hs1fevm2Endpoints -usage ssh
			
				$hs1fevm3Endpoints = $hs1fevm3 | Get-AzureEndpoint
				$hs1fevm3sshport = GetPort -Endpoints $hs1fevm3Endpoints -usage ssh
				
				#Collecting VM Host names
				$hs1bvmHostName = $hs1bvm.Name
				$hs1fevm1HostName = $hs1fevm1.Name
				$hs1fevm2HostName = $hs1fevm2.Name
				$hs1fevm3HostName = $hs1fevm3.Name
				
				#Preparation of daytrader install xml file
				"#all the IPs should be Internal ips `n<back_endVM_ip>$beip</back_endVM_ip>`n<front_endVM_ips>$fe1ip $fe2ip $fe3ip</front_endVM_ips>`n<username>$user</username>`n<password>$passwd</password>" > 'Daytrader_install.XML'
				$out = RemoteCopy -uploadTo $hs1VIP -port $hs1bvmsshport -files "Daytrader_install.XML" -username $user -password $password -upload 2>&1 | Out-Null
				Remove-Item Daytrader_install.XML
							
				$out = RemoteCopy -uploadTo $hs1VIP -port $hs1bvmsshport -files $currentTestData.files -username $user -password $password -upload 2>&1 | Out-Null
				$istarcreated = CreateIbmTar -ip $hs1VIP -port $hs1bvmsshport
				if($istarcreated -eq $false){
					throw "Failed to create IBMWebSphere tar file"
				}
				else
				{
					Logmsg "Creating IBMWebsphere tar completed .. "
				}
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1bvmsshport -command "chmod +x *" -runAsSudo 2>&1 | Out-Null
				# converting file format from UTF-16 to ASCII
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1bvmsshport -command "iconv -f UTF-16 -t ASCII Daytrader_install.XML > Daytrader_install.XML.tmp ; mv -f Daytrader_install.XML.tmp Daytrader_install.XML" -runAsSudo 2>&1 | Out-Null
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1bvmsshport -command "chmod +x *.XML" -runAsSudo 2>&1 | Out-Null
				
				#Uploading temp file fot test
                $out = RemoteCopy -uploadTo $hs1VIP -port $hs1fevm1sshport -files .\remote-scripts\temp.txt -username $user -password $password -upload 2>&1 | Out-Null
				$out = RemoteCopy -uploadTo $hs1VIP -port $hs1fevm2sshport -files .\remote-scripts\temp.txt -username $user -password $password -upload 2>&1 | Out-Null
				$out = RemoteCopy -uploadTo $hs1VIP -port $hs1fevm3sshport -files .\remote-scripts\temp.txt -username $user -password $password -upload 2>&1 | Out-Null
				
				#Checking Hostname is correct or not
				$bHostName = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1bvmsshport -command "hostname" -runAsSudo
				$fe1HostName = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1fevm1sshport -command "hostname" -runAsSudo
				$fe2HostName = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1fevm2sshport -command "hostname" -runAsSudo
				$fe3HostName = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1fevm3sshport -command "hostname" -runAsSudo
				if(($bHostName -imatch $hs1bvmHostName) -and ($fe1HostName -imatch $hs1fevm1HostName) -and ($fe2HostName -imatch $hs1fevm2HostName) -and ($fe3HostName -imatch $hs1fevm3HostName)){
					LogMsg "HostName is correct -- no need to set..`n Hostname in WA Portal: $hs1bvmHostName `n Hostname in VM (with hosname command): $bHostName `n Hostname in WA Portal: $hs1fevm1HostName `n Hostname in VM (with hosname command): $fe1HostName `n Hostname in WA Portal: $hs1fevm2HostName `n Hostname in VM (with hosname command): $fe2HostName `n Hostname in WA Portal: $hs1fevm3HostName `n Hostname in VM (with hosname command): $fe3HostName"
				}
				else{
					LogMsg "HostName is not correct -- need to be set.. `n Hostname in WA Portal: $hs1bvmHostName `n Hostname in VM (with hosname command): $bHostName `n Hostname in WA Portal: $hs1fevm1HostName `n Hostname in VM (with hosname command): $fe1HostName `n Hostname in WA Portal: $hs1fevm2HostName `n Hostname in VM (with hosname command): $fe2HostName `n Hostname in WA Portal: $hs1fevm3HostName `n Hostname in VM (with hosname command): $fe3HostName"
					$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1bvmsshport -command "hostname $hs1bvmHostName" -runAsSudo 2>&1 | Out-Null
					$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1fevm1sshport -command "hostname $hs1fevm1HostName" -runAsSudo 2>&1 | Out-Null
					$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1fevm2sshport -command "hostname $hs1fevm2HostName" -runAsSudo 2>&1 | Out-Null
					$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1fevm3sshport -command "hostname $hs1fevm3HostName" -runAsSudo 2>&1 | Out-Null
					LogMsg "Setting of correct HostName done.."
				}
				
				LogMsg "Executing : $($currentTestData.testScript)"
				Write-host "#################################################################################################"
				Write-host ""
				Write-host "Daytrader four vm installation has been started." -foregroundcolor "yellow"
				Write-host "It takes nearly 50 minutes and may take even more time depending on internet speed." -foregroundcolor "yellow"
				Write-host ""
				Write-host "#################################################################################################"
			
			#Here Daytrader setup is Executing...
				$dtr_setup_status = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1bvmsshport -command "python $($currentTestData.testScript) $($currentTestData.E2ESetupCmdLineArgument) 2>&1 > print.log" -runAsSudo -runmaxallowedtime 9000 -ignoreLinuxExitCode 2>&1 | Out-Null
				$out = RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/dtr_test.txt,/home/$user/logs.tar.gz" -downloadTo $LogDir -port $hs1bvmsshport -username $user -password $password 2>&1 | Out-Null
			}
			elseif($currentTestData.E2ESetupCmdLineArgument -imatch "singleVM_setup")
			{
				$hs1vm1 = $testVMsinService
				
					
				$hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
				$hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
				$hs1VIP = $hs1vm1Endpoints[0].Vip
				$hs1ServiceUrl = $hs1vm1.DNSName
				$hs1HostName = $hs1vm1.Name
				$hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
				$hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")

				$wsurl = "http:`/`/"+$hs1ServiceUrl.Replace(" ","")+":8080"
				$dturl = "$wsurl`/daytrader"
				$dip = $hs1vm1.Ipaddress.ToString()
				
				"#all the IPs should be Internal ips `n<username>$user</username>`n<password>$passwd</password>" > 'Daytrader_install.XML'
				$out = RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files "Daytrader_install.XML" -username $user -password $password -upload 2>&1 | Out-Null
				
				$out = RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload 2>&1 | Out-Null
				$istarcreated = CreateIbmTar -ip $hs1VIP -port $hs1vm1sshport
				if($istarcreated -eq $false){
					throw "Failed to create IBMWebSphere tar file"
				}
				else{
					Logmsg "Creating IBMWebsphere tar completed .. "
				}
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo 2>&1 | Out-Null
				
				# converting file format from UTF-16 to ASCII
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "iconv -f UTF-16 -t ASCII Daytrader_install.XML > Daytrader_install.XML.tmp ; mv -f Daytrader_install.XML.tmp Daytrader_install.XML" -runAsSudo 2>&1 | Out-Null
				$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *.XML" -runAsSudo 2>&1 | Out-Null	
				
				#Checking Hostname is correct or not
				$HostName = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "hostname" -runAsSudo
				if($HostName -imatch $hs1HostName){
					LogMsg "HostName is correct -- no need to set.. `n Hostname in WA Portal: $hs1HostName `n Hostname in VM (with hosname command): $HostName"
				}
				else{
					LogMsg "HostName is not correct -- need to be set.. `n Hostname in WA Portal: $hs1HostName `n Hostname in VM (with hosname command): $HostName"
					RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "hostname $hs1HostName" -runAsSudo 2>&1 | Out-Null
                    LogMsg "Setting of correct HostName done.."
				}
				
				LogMsg "Executing : $($currentTestData.testScript)"
				Write-host "#################################################################################################"
				Write-host ""
				Write-host "Daytrader single vm installation has been started." -foregroundcolor "yellow"
				Write-host "It takes nearly 20 minutes and may take more time depending on internet speed." -foregroundcolor "yellow"
				Write-host ""
				Write-host "#################################################################################################"
				
				$dtr_setup_status = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "python $($currentTestData.testScript) $($currentTestData.E2ESetupCmdLineArgument) 2>&1 > print.log" -runAsSudo -runmaxallowedtime 9000 -ignoreLinuxExitCode 2>&1 | Out-Null
				$temp = RetryOperation -operation { Restart-AzureVM -ServiceName $hs1vm1.ServiceName -Name $hs1vm1.Name -Verbose } -description "Restarting VM.." -maxRetryCount 10 -retryInterval 5
				if ( $temp.OperationStatus -eq "Succeeded" )
				{
					LogMsg "Restarted Successfully"

                    if ((isAllSSHPortsEnabled -DeployedServices $testVMsinService.DeploymentName) -imatch "True")
				    {
					    $out = RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/dtr_test.txt, /home/$user/logs.tar.gz" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password 2>&1 | Out-Null
				    }
				}
				else
				{
					Throw "Error in VM Restart."
				}
				
			}
			else{
				$testResult="FAIL"
				LogErr "Command line argument not properly added for Daytrader Setup, add the argument for FourVM: loadbalancer_setup, SingleVM: singleVM_setup in azure_ica_all.xml file at E2ESetupCmdLineArgument tag"
			}
		#Verifying Daytrader setup id completed or not
			try
			{
				$out = Select-String -Simple "DTR_INSTALL_PASS"  $LogDir\dtr_test.txt
				if($out){
					write-host "Daytrader setup finished successfully."
					$testResult="PASS"

				}else{
					write-host "Daytrader setup failed."
					$testResult="FAIL"
				}
			}catch{
				 write-host "Daytrader setup failed..."
				$testResult="FAIL"
			}
		}
		catch{
			$ErrorMessage =  $_.Exception.Message
			$testResult="Aborted"
		}		
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = ""
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

#Verification of Daytrader URL
try{
    Start-Sleep -s 120
	$webclient = New-Object System.Net.WebClient
    $out = $webclient.DownloadString($dturl)
    
	if($out -imatch "DayTrader"){
		write-host "Daytrader verification using url: $dturl success." 
		$testResult="PASS"
    }else{
		write-host "Daytrader verification using url: $dturl failed." 
		$testResult="FAIL"
    }
}
catch
{
     write-host "Daytrader verification using url: $dturl failed..." 
	 $testResult="FAIL"
}
$resultArr += $testResult
$result = $testResult

if ($testResult -eq "PASS")
{
	Write-host "#################################################################################################"
	Write-host ""
	Write-host  "Open $wsurl in the browser and you should be able to see the Websphere page." -foregroundcolor "yellow"
	Write-host  "Open $dturl in the browser and you should be able to see the Daytrader home page." -foregroundcolor "yellow"
	Write-host ""
	Write-host "#################################################################################################"
}
#Return the result and summery to the test suite script..
return $result