#author - vhisav@microsoft.com
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig -timeOutSeconds 4200
if ($isDeployed)
{
	try
	{
		$allVMData = GetAllDeployementData -DeployedServices $isDeployed
		$noServer = $true
		$noClient = $true
		$clientMachines = @()
		$slaveHostnames = ""
		foreach ( $vmData in $allVMData )
		{
			if (( $vmData.RoleName -imatch "Server" ) -or ( $vmData.RoleName -imatch "master" ))
			{
				$serverVMData = $vmData
				$noMaster = $false

			}
			elseif (( $vmData.RoleName -imatch "Client" ) -or ( $vmData.RoleName -imatch "slave" ))
			{
				$clientMachines += $vmData
				$noSlave = $fase
				if ( $slaveHostnames )
				{
					$slaveHostnames += "," + $vmData.RoleName
				}
				else
				{
					$slaveHostnames = $vmData.RoleName
				}
			}
		}
		if ( $noMaster )
		{
			Throw "No any master VM defined. Be sure that, server VM role name matches with the pattern `"*master*`". Aborting Test."
		}
		if ( $noSlave )
		{
			Throw "No any slave VM defined. Be sure that, client machine role names matches with pattern `"*slave*`" Aborting Test."
		}
		#region CONFIGURE VMs for TEST


		LogMsg "SERVER VM details :"
		LogMsg "  RoleName : $($serverVMData.RoleName)"
		LogMsg "  Public IP : $($serverVMData.PublicIP)"
		LogMsg "  SSH Port : $($serverVMData.SSHPort)"
		$i = 1
		foreach ( $clientVMData in $clientMachines )
		{
			LogMsg "CLIENT VM #$i details :"
			LogMsg "  RoleName : $($clientVMData.RoleName)"
			LogMsg "  Public IP : $($clientVMData.PublicIP)"
			LogMsg "  SSH Port : $($clientVMData.SSHPort)"
			$i += 1		
		}
		#
		# PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.	
		#
		
		ProvisionVMsForLisa -allVMData $allVMData -installPackagesOnRoleNames "none"

		#endregion

		#region Verfiy 

		#region Provision VMs for RDMA tests

		#region Generate etc-hosts.txt file
		$hostsFile = ".\$LogDir\etc-hosts.txt"
		foreach ( $vmDetails in $allVMData )
		{
			Add-Content -Value "$($vmDetails.InternalIP)`t$($vmDetails.RoleName)" -Path "$hostsFile"
			LogMsg "$($vmDetails.InternalIP)`t$($vmDetails.RoleName) added to etc-hosts.txt" 
		}
		#endregion

		#region Set contents of limits.conf...
		Set-Content -Value "/root/TestRDMA.sh &> rdmaConsole.txt" -Path "$LogDir\StartRDMA.sh"
		Set-Content -Value "*			   hard	memlock			unlimited" -Path "$LogDir\limits.conf"
		Add-Content -Value "*			   soft	memlock			unlimited" -Path "$LogDir\limits.conf"
		RemoteCopy -uploadTo $serverVMData.PublicIP -port $serverVMData.SSHPort -files "$constantsFile,$hostsFile,.\remote-scripts\TestRDMA.sh,.\$LogDir\StartRDMA.sh,.\$LogDir\limits.conf" -username "root" -password $password -upload
		#endregion

		#region Install LIS-RDMA drivers..

		$osRelease = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "cat /etc/*release*"
		$modinfo_hv_vmbus = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "modinfo hv_vmbus"
		if (!( $modinfo_hv_vmbus -imatch "microsoft-hyper-v-rdma" ))
		{
			
			#region Generate constants.sh

			LogMsg "Generating constansts.sh ..."
			$constantsFile = ".\$LogDir\constants.sh"

			Set-Content -Value "master=`"$($serverVMData.RoleName)`"" -Path $constantsFile
			LogMsg "master=$($serverVMData.RoleName) added to constansts.sh"


			Add-Content -Value "slaves=`"$slaveHostnames`"" -Path $constantsFile
			LogMsg "slaves=$slaveHostnames added to constansts.sh"

			Add-Content -Value "rdmaPrepare=`"yes`"" -Path $constantsFile
			LogMsg "rdmaPrepare=yes added to constansts.sh"

			Add-Content -Value "rdmaRun=`"no`"" -Path $constantsFile
			LogMsg "rdmaRun=no added to constansts.sh"

			Add-Content -Value "installLocal=`"yes`"" -Path $constantsFile
			LogMsg "installLocal=yes added to constansts.sh"

			LogMsg "constanst.sh created successfully..."
			#endregion
			if ( $osRelease -imatch "CentOS Linux release 7.1.")
			{
				$LIS4folder = "RHEL71"
			}
			if ( $osRelease -imatch "CentOS Linux release 7.0.")
			{
				$LIS4folder = "RHEL70"
			}
			if ( $osRelease -imatch "CentOS Linux release 6.5")
			{
				$LIS4folder = "RHEL65"
			}
		
			$lisRDMAFileUrl = "https://ciwestus.blob.core.windows.net/linuxbinaries/lis-4.0.11-RDMA.tar"
			Set-Content -Value "tar -xf lis-4.0.11-RDMA.tar" -Path "$LogDir\InstallLIS.sh"
			Add-Content -Value "chmod +x $LIS4folder/install.sh" -Path "$LogDir\InstallLIS.sh"
			Add-Content -Value "cd $LIS4folder" -Path "$LogDir\InstallLIS.sh"
			Add-Content -Value "./install.sh > /root/LIS4InstallStatus.txt 2>&1" -Path "$LogDir\InstallLIS.sh"
			$LIS4IntallCommand = "./InstallLIS.sh"
			$LIS4InstallJobs = @()
			foreach ( $vm in $allVMData )
			{   
				#Install LIS4 RDMA drivers...
				LogMsg "Setting contents of /etc/security/limits.conf..."
				$out = .\tools\dos2unix.exe ".\$LogDir\limits.conf" 2>&1
				LogMsg $out
				RemoteCopy -uploadTo $vm.PublicIP -port $vm.SSHPort -files ".\$LogDir\limits.conf,.\$LogDir\InstallLIS.sh" -username "root" -password $password -upload
				$out = RunLinuxCmd -ip $vm.PublicIP -port $vm.SSHPort -username "root" -password $password -command "cat limits.conf >> /etc/security/limits.conf"

				LogMsg "Downlaoding LIS-RDMA drivers in $($vm.RoleName)..."
				$out = RunLinuxCmd -ip $vm.PublicIP -port $vm.SSHPort -username "root" -password $password -command "wget $lisRDMAFileUrl"
				$out = RunLinuxCmd -ip $vm.PublicIP -port $vm.SSHPort -username "root" -password $password -command "chmod +x InstallLIS.sh"
				LogMsg "Executing $LIS4IntallCommand ..."
				$jobID = RunLinuxCmd -ip $vm.PublicIP -port $vm.SSHPort -username "root" -password $password -command "$LIS4IntallCommand" -RunInBackground
				$LIS4InstallObj = New-Object PSObject
				Add-member -InputObject $LIS4InstallObj -MemberType NoteProperty -Name ID -Value $jobID
				Add-member -InputObject $LIS4InstallObj -MemberType NoteProperty -Name RoleName -Value $vm.RoleName
				Add-member -InputObject $LIS4InstallObj -MemberType NoteProperty -Name PublicIP -Value $vm.PublicIP
				Add-member -InputObject $LIS4InstallObj -MemberType NoteProperty -Name SSHPort -Value $vm.SSHPort
				$LIS4InstallJobs += $LIS4InstallObj
			}

			#Monitor LIS installation...
			$LIS4InstallJobsRunning = $true
			$lisInstallErrorCount = 0
			while ($LIS4InstallJobsRunning)
			{
				$LIS4InstallJobsRunning = $false
				foreach ( $job in $LIS4InstallJobs )
				{
					if ( (Get-Job -Id $($job.ID)).State -eq "Running" )
					{
						LogMsg "lis-4.0.11-RDMA Installation Status for $($job.RoleName) : Running"
						$LIS4InstallJobsRunning = $true
					}
					else
					{
						$jobOut = Receive-Job -ID $($job.ID)
						$LIS4out = RunLinuxCmd -ip $job.PublicIP -port $job.SSHPort -username "root" -password $password -command "cat LIS4InstallStatus.txt"
						if ( $LIS4out -imatch "Please reboot your system")
						{
							LogMsg "lis-4.0.11-RDMA installed successfully for $($job.RoleName)"
						}
						else
						{
							#LogErr "LIS-rdma installation failed $($job.RoleName)"
							#$lisInstallErrorCount += 1
						}
					}

				}
				if ( $LIS4InstallJobsRunning )
				{
					WaitFor -seconds 10
				}
				#else
				#{
				#	if ( $lisInstallErrorCount -ne 0 )
				#	{
				#		Throw "LIS-rdma installation failed for some VMs.Aborting Test."
				#	}
				#}
			}
		
			$isRestarted = RestartAllDeployments -allVMData $allVMData
			if ( ! $isRestarted )
			{
				Throw "Failed to restart deployments in $isDeployed. Aborting Test."
			}
			#region Prepare VMs for test
			$packageInstallJobs = @()
			Set-Content -Value "/root/TestRDMA.sh &> prepareForRDMAConsole.txt" -Path "$LogDir\PrepareForRDMA.sh"
			$packageIntallCommand = "/root/PrepareForRDMA.sh"
			foreach ( $vm in $allVMData )
			{   
				#Install Intel and IBM MPI libraries...
				RemoteCopy -uploadTo $vm.PublicIP -port $vm.SSHPort -files "$constantsFile,$hostsFile,.\remote-scripts\TestRDMA.sh,.\$LogDir\PrepareForRDMA.sh" -username "root" -password $password -upload
				$jobID = RunLinuxCmd -ip $vm.PublicIP -port $vm.SSHPort -username "root" -password $password -command "chmod +x PrepareForRDMA.sh"
				LogMsg "Executing $packageIntallCommand ..."

				$jobID = RunLinuxCmd -ip $vm.PublicIP -port $vm.SSHPort -username "root" -password $password -command "$packageIntallCommand" -RunInBackground
				$packageInstallObj = New-Object PSObject
				Add-member -InputObject $packageInstallObj -MemberType NoteProperty -Name ID -Value $jobID
				Add-member -InputObject $packageInstallObj -MemberType NoteProperty -Name RoleName -Value $vm.RoleName
				Add-member -InputObject $packageInstallObj -MemberType NoteProperty -Name PublicIP -Value $vm.PublicIP
				Add-member -InputObject $packageInstallObj -MemberType NoteProperty -Name SSHPort -Value $vm.SSHPort
				$packageInstallJobs += $packageInstallObj
			}

			$packageInstallJobsRunning = $true
			$packageInstallErrorCount = 0
			while ($packageInstallJobsRunning)
			{
				$packageInstallJobsRunning = $false
				foreach ( $job in $packageInstallJobs )
				{
					if ( (Get-Job -Id $($job.ID)).State -eq "Running" )
					{
						LogMsg "RDMA preparation Status for $($job.RoleName) : Running"
						$packageInstallJobsRunning = $true
					}
					else
					{
						$jobOut = Receive-Job -ID $($job.ID) 
						if ( $jobOut -imatch "Please reboot your system")
						{
							LogMsg "RDMA preparation completed for $($job.RoleName)"
						}
						else
						{
							#LogErr "RDMA preparation failed $($job.RoleName)"
							#$packageInstallErrorCount += 1
						}
					}

				}
				if ( $packageInstallJobsRunning )
				{
					WaitFor -seconds 10
				}
				#else
				#{
				#	if ( $packageInstallErrorCount -ne 0 )
				#	{
				#		Throw "RDMA preparation failed for some VMs.Aborting Test."
				#	}
				#}
			}
		
			#endregion
		}
		else
		{
			LogMsg "RDMA LIS Drivers are already installed."
			LogMsg $modinfo_hv_vmbus
			LogMsg "Generating constansts.sh ..."
			$constantsFile = ".\$LogDir\constants.sh"

			Set-Content -Value "master=`"$($serverVMData.RoleName)`"" -Path $constantsFile
			LogMsg "master=$($serverVMData.RoleName) added to constansts.sh"


			Add-Content -Value "slaves=`"$slaveHostnames`"" -Path $constantsFile
			LogMsg "slaves=$slaveHostnames added to constansts.sh"

			Add-Content -Value "rdmaPrepare=`"no`"" -Path $constantsFile
			LogMsg "rdmaPrepare=no added to constansts.sh"

			Add-Content -Value "rdmaRun=`"yes`"" -Path $constantsFile
			LogMsg "rdmaRun=yes added to constansts.sh"

			LogMsg "constanst.sh created successfully..."
		}
		#endregion

		Set-Content -Value "/root/TestRDMA.sh &> rdmaConsole.txt" -Path "$LogDir\StartRDMA.sh"

		RemoteCopy -uploadTo $serverVMData.PublicIP -port $serverVMData.SSHPort -files "$constantsFile,$LogDir\StartRDMA.sh" -username "root" -password $password -upload
		$out = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "chmod +x *.sh"

		if ( $modinfo_hv_vmbus -imatch "microsoft-hyper-v-rdma" )
		{
			$testOut = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "/root/StartRDMA.sh"
		}
		else
		{
			#region EXECUTE TEST
			$testJob = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "/root/StartRDMA.sh" -RunInBackground
			#endregion

			#region MONITOR TEST
			while ( (Get-Job -Id $testJob).State -eq "Running" )
			{
				$currentStatus = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "tail -n 1 /root/rdmaConsole.txt"
				LogMsg "Current Test Staus : $currentStatus"
				WaitFor -seconds 10
			}
		}
		
		RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/rdmaConsole.txt"
		RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/summary.log"
		RemoteCopy -downloadFrom $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/pingPongTestInterNodeTestOut.txt"
		$finalStatus = RunLinuxCmd -ip $serverVMData.PublicIP -port $serverVMData.SSHPort -username "root" -password $password -command "cat /root/state.txt"
		$rdmaSummary = Get-Content -Path "$LogDir\summary.log" -ErrorAction SilentlyContinue
		
		if ($finalStatus -imatch "TestCompleted")
		{
			LogMsg "Test finished successfully."
			$pingPongInterNodeTestOut =  ( Get-Content -Path "$LogDir\pingPongTestInterNodeTestOut.txt" | Out-String )
			LogMsg $pingPongInterNodeTestOut
		}

		else
		{
			LogErr "Test did not finished successfully. Please check $LogDir\rdmaConsole.txt for detailed results."
		}
		#endregion


		if ( $finalStatus -imatch "TestFailed")
		{
			LogErr "Test failed. Last known status : $currentStatus."
			$testResult = "FAIL"
		}
		elseif ( $finalStatus -imatch "TestAborted")
		{
			LogErr "Test Aborted. Last known status : $currentStatus."
			$testResult = "ABORTED"
		}
		elseif ( $finalStatus -imatch "TestCompleted")
		{
			LogMsg "Test Completed. Result : $finalStatus."
			$testResult = "PASS"
		}
		elseif ( $finalStatus -imatch "TestRunning")
		{
			LogMsg "Powershell backgroud job for test is completed but VM is reporting that test is still running. Please check $LogDir\mdConsoleLogs.txt"
			LogMsg "Contests of state.txt : $finalStatus"
			$testResult = "PASS"
		}
		LogMsg "Test result : $testResult"
		LogMsg "Test Completed"
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = "PingPong"
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
		$resultSummary +=  CreateResultSummary -testResult $finalStatus -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
	}   
}

else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $result, $resultSummary
