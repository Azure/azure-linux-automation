Function ProvisionVMsForLisa($allVMData)
{
	$scriptUrl = "https://raw.githubusercontent.com/LIS/lis-test/master/WS2012R2/lisa/remote-scripts/ica/provisionLinuxForLisa.sh"
	$sshPrivateKeyPath = ".\ssh\myPrivateKey.key"
	$sshPrivateKey = "myPrivateKey.key"
	LogMsg "Downloading $scriptUrl ..."
	$scriptName =  $scriptUrl.Split("/")[$scriptUrl.Split("/").Count-1]
	$start_time = Get-Date
	$out = Invoke-WebRequest -Uri $scriptUrl -OutFile "$LogDir\$scriptName"
	LogMsg "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"

	Set-Content -Value "echo `"Host *`" > /home/$user/.ssh/config" -Path "$LogDir\disableHostKeyVerification.sh"
	Add-Content -Value "echo StrictHostKeyChecking=no >> /home/$user/.ssh/config" -Path "$LogDir\disableHostKeyVerification.sh"
	Add-Content -Value "echo IdentityFile /root/$sshPrivateKey >> /home/$user/.ssh/config" -Path "$LogDir\disableHostKeyVerification.sh"

	foreach ( $vmData in $allVMData )
	{
		LogMsg "Configuring $($vmData.RoleName) for LISA test..."
		RemoteCopy -uploadTo $vmData.PublicIP -port $vmData.SSHPort -files ".\remote-scripts\enableRoot.sh,$sshPrivateKeyPath,.\$LogDir\disableHostKeyVerification.sh,.\$LogDir\provisionLinuxForLisa.sh" -username $user -password $password -upload
		$out = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username $user -password $password -command "chmod +x /home/$user/*.sh" -runAsSudo			
		$rootPasswordSet = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username $user -password $password -command "/home/$user/enableRoot.sh -password $($password.Replace('"',''))" -runAsSudo
		LogMsg $rootPasswordSet
		if (( $rootPasswordSet -imatch "ROOT_PASSWRD_SET" ) -and ( $rootPasswordSet -imatch "SSHD_RESTART_SUCCESSFUL" ))
		{
			LogMsg "root user enabled for $($vmData.RoleName) and password set to $password"
		}
		else
		{
			Throw "Failed to enable root password / starting SSHD service. Please check logs. Aborting test."
		}
		$out = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "chmod 600 /home/$user/$sshPrivateKey && cp -ar /home/$user/* /root/"
		$out = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "mkdir -p /root/.ssh/ && cp /home/$user/.ssh/authorized_keys /root/.ssh/" 
		$out = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "/home/$user/disableHostKeyVerification.sh" 
		$out = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "cp /home/$user/.ssh/config /root/.ssh/" 
		$out = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "service sshd restart" 

		LogMsg "Executing $scriptName ..."
		$provisionJob = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "/root/$scriptName" -RunInBackground
		#endregion
		while ( (Get-Job -Id $provisionJob).State -eq "Running" )
		{
			$currentStatus = RunLinuxCmd -ip $vmData.PublicIP -port $vmData.SSHPort -username "root" -password $password -command "tail -n 1 /root/provisionLinux.log"
			LogMsg "Current Package Installation Status : $currentStatus"
			WaitFor -seconds 10
		}
		RemoteCopy -download -downloadFrom $vmData.PublicIP -port $vmData.SSHPort -files "/root/provisionLinux.log" -username "root" -password $password -downloadTo $LogDir
		Rename-Item -Path "$LogDir\provisionLinux.log" -NewName "$($vmData.RoleName)-provisionLinux.log" -Force | Out-Null
		LogMsg "$($vmData.RoleName) preparation finished."
	}
	#endregion
}