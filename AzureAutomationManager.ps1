##############################################################################################
# AzureAutomationManager.ps1
# Description : This script manages all the setup and test operations in Azure environemnt.
#               It is an entry script of Azure Automation
# Operations : 
#              - Installing AzureSDK 
#              - VHD preparation : Installing packages required by ICA, LIS drivers and waagent
#              - Uplaoding test VHD to cloud
#              - Invokes azure test suite
## Author : v-ampaw@microsoft.com
###############################################################################################
param ([string] $xmlConfigFile, [switch] $eMail, [string] $logFilename="azure_ica.log", [switch] $runtests, [switch]$onCloud, [switch] $vhdprep, [switch]$upload, [switch] $help, [string] $Distro, [string] $cycleName, [string] $TestPriority, [string]$osImage, [switch]$EconomyMode, [switch]$keepReproInact)

#Import-Module .\TestLibs\RDFELibs.psm1 -Force
Import-Module .\TestLibs\AzureWinUtils.psm1 -Force

$xmlConfig = [xml](Get-Content $xmlConfigFile)
$user = $xmlConfig.config.Azure.Deployment.Data.UserName
$password = $xmlConfig.config.Azure.Deployment.Data.Password
$sshKey = $xmlConfig.config.Azure.Deployment.Data.sshKey
$sshPublickey = $xmlConfig.config.Azure.Deployment.Data.sshPublicKey
Set-Variable -Name user -Value $user -Scope Global
Set-Variable -Name password -Value $password -Scope Global
Set-Variable -Name sshKey -Value $sshKey -Scope Global
Set-Variable -Name sshPublicKey -Value $sshPublicKey -Scope Global

$dtapServerIp = $xmlConfig.config.Azure.Deployment.Data.DTAP.IP

try
{
    # Main Body of the script
    # Work flow starts here
    #Creating TestResults directory
    $testResults = "TestResults"
    if (! (test-path $testResults))
    {
        mkdir $testResults | out-null
    }
    if ($help)
    {
        Usage
        Write-Host "Info : Help command was passed, not runTests." 
        exit 1
    }
    if (! $xmlConfigFile)
    {
        Write-Host  "Error: Missing the xmlConfigFile command-line argument." -ForegroundColor Red
        Usage
        exit 2
    }
    if (! (test-path $xmlConfigFile))
    {
        Write-Host  "Error: XML config file", $xmlConfigFile, "does not exist." -ForegroundColor Red
        exit 3
    }

    #Parse XML file
    #Get Parameters through XML file

    $xmlConfig=[XML](Get-Content $xmlConfigFile)
    $Platform=$xmlConfig.config.global.platform
    $global=$xmlConfig.config.global
	
	

    $testStartTime = [DateTime]::Now.ToUniversalTime()
    Set-Variable -Name testStartTime -Value $testStartTime -Scope Global

    $fname = [System.IO.Path]::GetFilenameWithoutExtension($xmlConfigFile)
    $testDir = $testResults + "\" + $fname + "-" + $testStartTime.ToString("yyyyMMdd-HHmmss")

    mkdir $testDir -ErrorAction SilentlyContinue | out-null

    if ($logFilename)
    {
    	$logfile = $logFilename
    }
    $logFile = $testDir + "\" + $logfile
    Set-Variable -Name logfile -Value $logFile -Scope Global
    Set-Variable -Name Distro -Value $Distro -Scope Global
    Set-Variable -Name onCloud -Value $onCloud -Scope Global
    Set-Variable -Name xmlConfig -Value $xmlConfig -Scope Global
    Set-Variable -Name vnetIsAllConfigured -Value $false -Scope Global
    if($EconomyMode)
    {
        Set-Variable -Name EconomyMode -Value $true -Scope Global
        if($keepReproInact)
        {
            Set-Variable -Name keepReproInact -Value $true -Scope Global
        }
    }
    else
    {
        Set-Variable -Name EconomyMode -Value $false -Scope Global
        Set-Variable -Name keepReproInact -Value $false -Scope Global
    }

    
    $AzureSetup = $xmlConfig.config.Azure.General
    LogMsg  ("Info : AzureAutomationManager.ps1 - LIS on Azure Automation")
    LogMsg  ("Info : Created test results directory:", $testDir)
    LogMsg  ("Info : Logfile = ", $logfile)
    LogMsg  ("Info : Using config file $xmlConfigFile")
    LogMsg  ("Setting Subscription")
    SetSubscription -subscriptionID $AzureSetup.SubscriptionID -subscriptionName $AzureSetup.SubscriptionName -certificateThumbprint $AzureSetup.CertificateThumbprint -managementEndpoint $AzureSetup.ManagementEndpoint -storageAccount $AzureSetup.StorageAccount
    $AllSubscriptions = Get-AzureSubscription
    foreach ($subscription in $AllSubscriptions)
    {
        if (($subscription.CurrentStorageAccountName -imatch $AzureSetup.StorageAccount) -and ( $subscription.SubscriptionName -imatch $AzureSetup.SubscriptionName))
        {
            $currentSubscription = $subscription
        }
    }
    LogMsg "SubscriptionName           : $($currentSubscription.SubscriptionName)"
    LogMsg "SubscriptionId             : $($currentSubscription.SubscriptionID)"
    LogMsg "ServiceEndpoint            : $($currentSubscription.ServiceEndpoint)"
    LogMsg "CurrentStorageAccount      : $($currentSubscription.CurrentStorageAccountName)"
    #Check for the Azure platform
    if($Platform -eq "Azure")
    {
	    #Installing Azure-SDK
	    .\SetupScripts\ImportAzureSDK.ps1
	    if(!$?)
	    {
	        LogMsg "Failed to import Azure-SDK"
	        exit 2
	   
	    }
	    LogMsg "*************AZURE POWERSHELL****************"
    }
    if($upload)
    {
    $uploadflag=$true
    }
    if ($vhdprep)
    {
	    $sts=VHDProvision $xmlConfig $uploadflag 
	    if($sts -contains $false)
	    {
	        LogMsg  "Exiting with Error..!!!"
	        exit 3
	    }
	     LogMsg  "moving VHD provision log file to test results directory"
	     LogMsg "move VHD_Provision.log ${testDir}\VHD_Provision.log"
	     move "VHD_Provision.log" "${testDir}\VHD_Provision.log"
	     LogMsg "----------------------------------------------------------"
	     LogMsg "VHD provision logs : ${testDir}\VHD_Provision.log "
    }
    if (!$runTests)
    {
	    LogMsg "No tests will be run as runtests parameter is not provided"
	    LogMsg "Exiting : with VHD prepared for Automation"
	    LogMsg "==========================================="
	    exit 4
    }
    if ($runTests)
    {
		if($Platform -ne "Azure")
		{
	        LogMsg "Info : Starting ICA test suite on Hyper-V Server"
	        ##To do
	        #Ivoking ICA scripts on Hyper-V server
	        #cd ...\Win8_ICA\ica
	        #.\ica.ps1 .\XML\test.xml -runtests 
	        exit
        }
        $testCycle =  GetCurrentCycleData -xmlConfig $xmlConfig -cycleName $cycleName
        #Invoke Azure Test Suite  

        $testSuiteResultDetails=.\AzureTestSuite.ps1 $xmlConfig -Distro $Distro -cycleName $cycleName
        #if(!$sts)
        #{
            #exit
        #}
        # Add summary information to the ica log file
        $logDirFilename = [System.IO.Path]::GetFilenameWithoutExtension($xmlConfigFile)
        #$summaryText = "<br />~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<br /><br />"
        $summaryAll = GetTestSummary -testCycle $testCycle -StartTime $testStartTime -xmlFileName $logDirFilename -distro $Distro -testSuiteResultDetails $testSuiteResultDetails
        $PlainTextSummary += $summaryAll[0]
        $HtmlTextSummary += $summaryAll[1]
        # Remove HTML tags from platin text summary.
        $PlainTextSummary = $PlainTextSummary.Replace("<br />", "`r`n")
        $PlainTextSummary = $PlainTextSummary.Replace("<pre>", "")
        $PlainTextSummary = $PlainTextSummary.Replace("</pre>", "")
        LogMsg  "$PlainTextSummary"
        if($eMail)
        {
            SendEmail $xmlConfig -body $HtmlTextSummary
        }
    }
}
catch
{
    $ErrorMessage =  $_.Exception.Message
    LogMsg "EXCEPTION : $ErrorMessage"   
}
Finally
{
	exit
}
