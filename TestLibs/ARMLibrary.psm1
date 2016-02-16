Function CreateAllResourceGroupDeployments($setupType, $xmlConfig, $Distro)
{
    $resourceGroupCount = 0
    $xml = $xmlConfig
    LogMsg $setupType
    $setupTypeData = $xml.config.Azure.Deployment.$setupType
    $allsetupGroups = $setupTypeData
    if ($allsetupGroups.HostedService[0].Location -or $allsetupGroups.HostedService[0].AffinityGroup)
    {
        $isMultiple = 'True'
        $resourceGroupCount = 0
    }
    else
    {
        $isMultiple = 'False'
    }

    foreach ($newDistro in $xml.config.Azure.Deployment.Data.Distro)
    {

        if ($newDistro.Name -eq $Distro)
        {
            $osImage = $newDistro.OsImage
            $osVHD = $newDistro.OsVHD
        }
    }

    $location = $xml.config.Azure.General.Location
    $AffinityGroup = $xml.config.Azure.General.AffinityGroup

    foreach ($RG in $setupTypeData.HostedService )
    {
        $curtime = Get-Date
        $isServiceDeployed = "False"
        $retryDeployment = 0
        if ( $RG.Tag -ne $null )
        {
            $groupName = "ICA-RG-" + $RG.Tag + "-" + $Distro + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
        }
        else
        {
            $groupName = "ICA-RG-" + $setupType + "-" + $Distro + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
        }
        if($isMultiple -eq "True")
        {
            $groupName = $groupName + "-" + $resourceGroupCount
        }

        while (($isServiceDeployed -eq "False") -and ($retryDeployment -lt 1))
        {
            LogMsg "Creating Resource Group : $groupName."
            LogMsg "Verifying that Resource group name is not in use."
            $isRGDeleted = DeleteResourceGroup -RGName $groupName 
            if ($isRGDeleted)
            {    
                $isServiceCreated = CreateResourceGroup -RGName $groupName -location $location
                if ($isServiceCreated -eq "True")
                {
                    $azureDeployJSONFilePath = "$LogDir\$groupName.json"
                    $DeploymentCommand = GenerateAzureDeployJSONFile -RGName $groupName -osImage $osImage -osVHD $osVHD -RGXMLData $RG -Location $location -azuredeployJSONFilePath $azureDeployJSONFilePath
                    $DeploymentStartTime = (Get-Date)
                    $CreateRGDeployments = CreateResourceGroupDeployment -RGName $groupName -location $location -setupType $setupType -TemplateFile $azureDeployJSONFilePath
                    $DeploymentEndTime = (Get-Date)
                    $DeploymentElapsedTime = $DeploymentEndTime - $DeploymentStartTime
                    if ( $CreateRGDeployments )
                    {
                        $retValue = "True"
                        $isServiceDeployed = "True"
                        $resourceGroupCount = $resourceGroupCount + 1
                        if ($resourceGroupCount -eq 1)
                        {
                            $deployedGroups = $groupName
                        }
                        else
                        {
                            $deployedGroups = $deployedGroups + "^" + $groupName
                        }

                    }
                    else
                    {
                        LogErr "Unable to Deploy one or more VM's"
                        $retryDeployment = $retryDeployment + 1
                        $retValue = "False"
                        $isServiceDeployed = "False"
                    }
                }
                else
                {
                    LogErr "Unable to create $groupName"
                    $retryDeployment = $retryDeployment + 1
                    $retValue = "False"
                    $isServiceDeployed = "False"
                }
            }    
            else
            {
                LogErr "Unable to delete existing resource group - $groupName"
                $retryDeployment = 3
                $retValue = "False"
                $isServiceDeployed = "False"
            }
        }
    }
    return $retValue, $deployedGroups, $resourceGroupCount, $DeploymentElapsedTime
}

Function DeleteResourceGroup([string]$RGName, [switch]$KeepDisks)
{
    try
    {
        $ResourceGroup = Get-AzureResourceGroup -Name $RGName -ErrorAction Ignore
    }
    catch
    {
    }
    if ($ResourceGroup)
    {
        Remove-AzureResourceGroup -Name $RGName -Force -Verbose
        $retValue = $?
    }
    else
    {
        LogMsg "$RGName does not exists."
        $retValue = $true
    }
    return $retValue
}

Function CreateResourceGroup([string]$RGName, $location)
{
    $FailCounter = 0
    $retValue = "False"
    $ResourceGroupDeploymentName = $RGName + "-deployment"

    While(($retValue -eq $false) -and ($FailCounter -lt 5))
    {
        try
        {
            $FailCounter++
            if($location)
            {
                LogMsg "Using location : $location"
                $createRG = New-AzureResourceGroup -Name $RGName -Location $location.Replace('"','') -Force -Verbose
            }
            $operationStatus = $createRG.ProvisioningState
            if ($operationStatus  -eq "Succeeded")
            {
                LogMsg "Resource Group $RGName Created."
                $retValue = $true
            }
            else 
            {
                LogErr "Failed to Resource Group $RGName."
                $retValue = $false
            }
        }
        catch
        {
            $retValue = $false
        }
    }
    return $retValue
}

Function CreateResourceGroupDeployment([string]$RGName, $location, $setupType, $TemplateFile)
{
    $FailCounter = 0
    $retValue = "False"
    $ResourceGroupDeploymentName = $RGName + "-deployment"
    While(($retValue -eq $false) -and ($FailCounter -lt 1))
    {
        try
        {
            $FailCounter++
            if($location)
            {
                LogMsg "Creating Deployment using $TemplateFile ..."
                $createRGDeployment = New-AzureResourceGroupDeployment -Name $ResourceGroupDeploymentName -ResourceGroupName $RGName -TemplateFile $TemplateFile -Verbose
            }
            $operationStatus = $createRGDeployment.ProvisioningState
            if ($operationStatus  -eq "Succeeded")
            {
                LogMsg "Resource Group Deployment Created."
                $retValue = $true
            }
            else 
            {
                LogErr "Failed to Resource Group."
                $retValue = $false
            }
        }
        catch
        {
            $retValue = $false
        }
    }
    return $retValue
}


Function GenerateAzureDeployJSONFile ($RGName, $osImage, $osVHD, $RGXMLData, $Location, $azuredeployJSONFilePath)
{
LogMsg "Generating Template : $azuredeployJSONFilePath"
$jsonFile = $azuredeployJSONFilePath
$StorageAccountName = $xml.config.Azure.General.ARMStorageAccount
LogMsg "Getting Storage Account : $StorageAccountName details ..."
$StorageAccountType = (Get-AzureStorageAccount | where {$_.StorageAccountName -eq "$StorageAccountName"}).AccountType
if($StorageAccountType -match 'Premium')
{
    $StorageAccountType = "Premium_LRS"
}
else
{
	$StorageAccountType = "Standard_LRS"
}
LogMsg "Storage Account Type : $StorageAccountType"
$HS = $RGXMLData
$setupType = $Setup
$totalVMs = 0
$totalHS = 0
$extensionCounter = 0
$vmCount = 0
$indents = @()
$indent = ""
$singleIndent = ""
$indents += $indent
$RGRandomNumber = $((Get-Random -Maximum 999999 -Minimum 100000))
$RGrandomWord = ([System.IO.Path]::GetRandomFileName() -replace '[^a-z]')
$dnsNameForPublicIP = $($RGName.ToLower() -replace '[^a-z0-9]')
$virtualNetworkName = $($RGName.ToUpper() -replace '[^a-z]') + "VNET"
$defaultSubnetName = "Subnet1"
$availibilitySetName = $($RGName.ToUpper() -replace '[^a-z]') + "AvSet"
$LoadBalancerName =  $($RGName.ToUpper() -replace '[^a-z]') + "LoadBalancer"
$apiVersion = "2015-05-01-preview"
$PublicIPName = $($RGName.ToUpper() -replace '[^a-z]') + "PublicIP"
$sshPath = '/home/' + $user + '/.ssh/authorized_keys'
$sshKeyData = ""
if ( $CurrentTestData.ProvisionTimeExtensions )
{
	$extensionString = (Get-Content .\XML\Extensions.xml)
	foreach ($line in $extensionString.Split("`n"))
	{
		if ($line -imatch ">$($CurrentTestData.ProvisionTimeExtensions)<")
		{
			$ExecutePS = $true
		}
		if ($line -imatch '</Extension>')
		{
			$ExecutePS = $false
		}
		if ( ($line -imatch "EXECUTE-PS-" ) -and $ExecutePS)
		{
			$PSoutout = ""
			$line = $line.Trim()
			$line = $line.Replace("EXECUTE-PS-","")
			$line = $line.Split(">")
			$line = $line.Split("<")
			LogMsg "Executing Powershell command from Extensions.XML file : $($line[2])..."
			$PSoutout = Invoke-Expression -Command $line[2]
			$extensionString = $extensionString.Replace("EXECUTE-PS-$($line[2])",$PSoutout)
			sleep -Milliseconds 1
		}
	}
	$extensionXML = [xml]$extensionString
}

LogMsg "ARM Storage Account : $StorageAccountName"
LogMsg "Using API VERSION : $apiVersion"
$ExistingVnet = $null
if ($RGXMLData.ARMVnetName)
{
    $ExistingVnet = $RGXMLData.ARMVnetName
    LogMsg "Getting $ExistingVnet Virtual Netowrk info ..."
    $ExistingVnetResourceGroupName = ( Get-AzureResource | Where {$_.Name -eq $ExistingVnet}).ResourceGroupName
    LogMsg "ARM VNET : $ExistingVnet (ResourceGroup : $ExistingVnetResourceGroupName)"
    $virtualNetworkName = $ExistingVnet
}

#Generate Single Indent
for($i =0; $i -lt 4; $i++)
{
    $singleIndent += " "
}

#Generate Indent Levels
for ($i =0; $i -lt 30; $i++)
{
    $indent += $singleIndent
    $indents += $indent
}


#Check if the deployment Type is single VM deployment or multiple VM deployment
$numberOfVMs = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    $numberOfVMs += 1
}

$StorageProfileScriptBlock = {
                Add-Content -Value "$($indents[4])^storageProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^osDisk^ : " -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        if ( $osVHD )
                        {
                            if ( $osImage)
                            {
                                LogMsg "Overriding ImageName with user provided VHD."
                            }
                            LogMsg "Using VHD : $osVHD"
                            Add-Content -Value "$($indents[6])^image^: " -Path $jsonFile
                            Add-Content -Value "$($indents[6]){" -Path $jsonFile
                                Add-Content -Value "$($indents[7])^uri^: ^[concat('http://',variables('StorageAccountName'),'.blob.core.windows.net/vhds/','$osVHD')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[6])}," -Path $jsonFile
                            Add-Content -Value "$($indents[6])^osType^: ^Linux^," -Path $jsonFile
                        }
                        else
                        {
                            LogMsg "Using ImageName : $osImage"
                            Add-Content -Value "$($indents[6])^sourceImage^: " -Path $jsonFile
                            Add-Content -Value "$($indents[6]){" -Path $jsonFile
                                Add-Content -Value "$($indents[7])^id^: ^[variables('CompliedSourceImageName')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[6])}," -Path $jsonFile
                        }
                        Add-Content -Value "$($indents[6])^name^: ^$vmName-OSDisk^," -Path $jsonFile
                        #Add-Content -Value "$($indents[6])^osType^: ^Linux^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^vhd^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^uri^: ^[concat('http://',variables('StorageAccountName'),'.blob.core.windows.net/vhds/','$vmName-$RGrandomWord-osdisk.vhd')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^caching^: ^ReadWrite^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^createOption^: ^FromImage^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
}


#region Generate JSON file
Set-Content -Value "$($indents[0]){" -Path $jsonFile -Force
    Add-Content -Value "$($indents[1])^`$schema^: ^https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#^," -Path $jsonFile
    Add-Content -Value "$($indents[1])^contentVersion^: ^1.0.0.0^," -Path $jsonFile
    Add-Content -Value "$($indents[1])^parameters^: {}," -Path $jsonFile
    Add-Content -Value "$($indents[1])^variables^:" -Path $jsonFile
    Add-Content -Value "$($indents[1]){" -Path $jsonFile
        Add-Content -Value "$($indents[2])^StorageAccountName^: ^$StorageAccountName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^dnsNameForPublicIP^: ^$dnsNameForPublicIP^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^adminUserName^: ^$user^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^adminPassword^: ^$($password.Replace('"',''))^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^sshKeyPublicThumbPrint^: ^$sshPublicKeyThumbprint^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^sshKeyPath^: ^$sshPath^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^sshKeyData^: ^$sshKeyData^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^location^: ^$($Location.Replace('"',''))^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^publicIPAddressName^: ^$PublicIPName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^virtualNetworkName^: ^$virtualNetworkName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^nicName^: ^$nicName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^addressPrefix^: ^10.0.0.0/16^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vmSourceImageName^ : ^$osImage^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^CompliedSourceImageName^ : ^[concat('/',subscription().subscriptionId,'/services/images/',variables('vmSourceImageName'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^defaultSubnetPrefix^: ^10.0.0.0/24^," -Path $jsonFile
        #Add-Content -Value "$($indents[2])^subnet2Prefix^: ^10.0.1.0/24^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vmStorageAccountContainerName^: ^vhds^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^publicIPAddressType^: ^Dynamic^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^storageAccountType^: ^$storageAccountType^," -Path $jsonFile
    if ($ExistingVnet)
    {
        Add-Content -Value "$($indents[2])^virtualNetworkResourceGroup^: ^$ExistingVnetResourceGroupName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vnetID^: ^[resourceId(variables('virtualNetworkResourceGroup'), 'Microsoft.Network/virtualNetworks', '$virtualNetworkName')]^," -Path $jsonFile
    }
    else
    {
        Add-Content -Value "$($indents[2])^defaultSubnet^: ^$defaultSubnetName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^defaultSubnetID^: ^[concat(variables('vnetID'),'/subnets/', variables('defaultSubnet'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^vnetID^: ^[resourceId('Microsoft.Network/virtualNetworks',variables('virtualNetworkName'))]^," -Path $jsonFile
    }
        Add-Content -Value "$($indents[2])^availabilitySetName^: ^$availibilitySetName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbName^: ^$LoadBalancerName^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbID^: ^[resourceId('Microsoft.Network/loadBalancers',variables('lbName'))]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^frontEndIPConfigID^: ^[concat(variables('lbID'),'/frontendIPConfigurations/LoadBalancerFrontEnd')]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbPoolID^: ^[concat(variables('lbID'),'/backendAddressPools/BackendPool1')]^," -Path $jsonFile
        Add-Content -Value "$($indents[2])^lbProbeID^: ^[concat(variables('lbID'),'/probes/tcpProbe')]^" -Path $jsonFile
        #Add more variables here, if required..
        #Add more variables here, if required..
        #Add more variables here, if required..
        #Add more variables here, if required..
    Add-Content -Value "$($indents[1])}," -Path $jsonFile
    LogMsg "Added Variables.."

    #region Define Resources
    Add-Content -Value "$($indents[1])^resources^:" -Path $jsonFile
    Add-Content -Value "$($indents[1])[" -Path $jsonFile

    #region Common Resources for all deployments..

        #region publicIPAddresses
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/publicIPAddresses^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('publicIPAddressName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^publicIPAllocationMethod^: ^[variables('publicIPAddressType')]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^dnsSettings^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^domainNameLabel^: ^[variables('dnsNameForPublicIP')]^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added Public IP Address $PublicIPName.."
        #endregion

        #region virtualNetworks
    if (!$ExistingVnet)
    {
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/virtualNetworks^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('virtualNetworkName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                #AddressSpace
                Add-Content -Value "$($indents[4])^addressSpace^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^addressPrefixes^: " -Path $jsonFile
                    Add-Content -Value "$($indents[5])[" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^[variables('addressPrefix')]^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])]" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #Subnets
                Add-Content -Value "$($indents[4])^subnets^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^[variables('defaultSubnet')]^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^addressPrefix^: ^[variables('defaultSubnetPrefix')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    #Add-Content -Value "$($indents[5]){" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])^name^: ^[variables('subnet2Name')]^," -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                    #    Add-Content -Value "$($indents[6]){" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])^addressPrefix^: ^[variables('subnet2Prefix')]^" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    #Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added Virtual Network $virtualNetworkName.."
    }
        #endregion

    #endregion

    #region Multiple VM Deployment

    if ( $numberOfVMs -gt 1 )
    {     
        #region availabilitySets
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Compute/availabilitySets^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('availabilitySetName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added availabilitySet $availibilitySetName.."
        #endregion
       
        #region LoadBalancer
        LogMsg "Adding Load Balancer ..."
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/loadBalancers^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^[variables('lbName')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/publicIPAddresses/', variables('publicIPAddressName'))]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^frontendIPConfigurations^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^LoadBalancerFrontEnd^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^publicIPAddress^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[resourceId('Microsoft.Network/publicIPAddresses',variables('publicIPAddressName'))]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]," -Path $jsonFile
                Add-Content -Value "$($indents[4])^backendAddressPools^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^:^BackendPool1^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]," -Path $jsonFile
                #region Normal Endpoints

                Add-Content -Value "$($indents[4])^inboundNatRules^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
$LBPorts = 0
$EndPointAdded = $false
$role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( !($endpoint.LoadBalanced) -or ($endpoint.LoadBalanced -eq "False") )
        { 
            if ( $EndPointAdded )
            {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
            }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$vmName-$($endpoint.Name)^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^frontendIPConfiguration^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('frontEndIPConfigID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^: ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^frontendPort^: ^$($endpoint.PublicPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^backendPort^: ^$($endpoint.LocalPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^enableFloatingIP^: false" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added inboundNatRule Name:$vmName-$($endpoint.Name) frontendPort:$($endpoint.PublicPort) backendPort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol)."
                    $EndPointAdded = $true
        }
        else
        {
                $LBPorts += 1
        }
    }
                $role += 1
}
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
                #endregion
                
                #region LoadBalanced Endpoints
if ( $LBPorts -gt 0 )
{
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                Add-Content -Value "$($indents[4])^loadBalancingRules^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
$probePorts = 0
$EndPointAdded = $false
$addedLBPort = $null
$role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( ($endpoint.LoadBalanced -eq "True") -and !($addedLBPort -imatch "$($endpoint.Name)-$($endpoint.PublicPort)" ) )
        { 
            if ( $EndPointAdded )
            {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
            }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$RGName-LB-$($endpoint.Name)^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                       
                            Add-Content -Value "$($indents[7])^frontendIPConfiguration^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('frontEndIPConfigID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^backendAddressPool^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('lbPoolID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^: ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^frontendPort^: ^$($endpoint.PublicPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^backendPort^: ^$($endpoint.LocalPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^enableFloatingIP^: false," -Path $jsonFile

            if ( $endpoint.ProbePort )
            {
                            $probePorts += 1
                            Add-Content -Value "$($indents[7])^probe^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[concat(variables('lbID'),'/probes/$RGName-LB-$($endpoint.Name)-probe')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            LogMsg "Enabled Probe for loadBalancingRule Name:$RGName-LB-$($endpoint.Name) : $RGName-LB-$($endpoint.Name)-probe."
            }
            else
            {
                            Add-Content -Value "$($indents[7])^idleTimeoutInMinutes^: 5" -Path $jsonFile
            }
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added loadBalancingRule Name:$RGName-LB-$($endpoint.Name) frontendPort:$($endpoint.PublicPort) backendPort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol)."
                    if ( $addedLBPort )
                    {
                        $addedLBPort += "-$($endpoint.Name)-$($endpoint.PublicPort)"
                    }
                    else
                    {
                        $addedLBPort = "$($endpoint.Name)-$($endpoint.PublicPort)"
                    }
                    $EndPointAdded = $true
        }
    }
                $role += 1            
}
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
}
                #endregion

                #region Probe Ports
if ( $probePorts -gt 0 )
{
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                Add-Content -Value "$($indents[4])^probes^:" -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile

$EndPointAdded = $false
$addedProbes = $null
$role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( ($endpoint.LoadBalanced -eq "True") )
        { 
            if ( $endpoint.ProbePort -and !($addedProbes -imatch "$($endpoint.Name)-probe-$($endpoint.ProbePort)"))
            {
                if ( $EndPointAdded )
                {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
                }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$RGName-LB-$($endpoint.Name)-probe^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^ : ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^port^ : ^$($endpoint.ProbePort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^intervalInSeconds^ : ^15^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^numberOfProbes^ : ^$probePorts^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added probe :$RGName-LB-$($endpoint.Name)-probe Probe Port:$($endpoint.ProbePort) Protocol:$($endpoint.Protocol)."
                    if ( $addedProbes )
                    {
                        $addedProbes += "-$($endpoint.Name)-probe-$($endpoint.ProbePort)"
                    }
                    else
                    {
                        $addedProbes = "$($endpoint.Name)-probe-$($endpoint.ProbePort)"
                    }
                    $EndPointAdded = $true
            }
        }
    }

            $role += 1
}
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
}
                 #endregion

            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Addded Load Balancer."
    #endregion

    $vmAdded = $false
    $role = 0
foreach ( $newVM in $RGXMLData.VirtualMachine)
{
    $VnetName = $RGXMLData.VnetName
    $instanceSize = $newVM.ARMInstanceSize
    $ExistingSubnet = $newVM.ARMSubnetName
    $DnsServerIP = $RGXMLData.DnsServerIP
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-"+$role
    }
    $NIC = "NIC" + "-$vmName"

        if ( $vmAdded )
        {
            Add-Content -Value "$($indents[2])," -Path $jsonFile
        }

        #region networkInterfaces
        LogMsg "Adding Network Interface Card $NIC"
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/networkInterfaces^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$NIC^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/publicIPAddresses/', variables('publicIPAddressName'))]^," -Path $jsonFile
            if(!$ExistingVnet)
            {
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/virtualNetworks/', variables('virtualNetworkName'))]^," -Path $jsonFile
            }
                Add-Content -Value "$($indents[4])^[variables('lbID')]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile

            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^ipConfigurations^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^ipconfig1^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            
                            Add-Content -Value "$($indents[7])^loadBalancerBackendAddressPools^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7])[" -Path $jsonFile
                                Add-Content -Value "$($indents[8]){" -Path $jsonFile
                                    Add-Content -Value "$($indents[9])^id^: ^[concat(variables('lbID'), '/backendAddressPools/BackendPool1')]^" -Path $jsonFile
                                Add-Content -Value "$($indents[8])}" -Path $jsonFile
                            Add-Content -Value "$($indents[7])]," -Path $jsonFile

                                #region Enable InboundRules in NIC
                            Add-Content -Value "$($indents[7])^loadBalancerInboundNatRules^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7])[" -Path $jsonFile
    $EndPointAdded = $false
    foreach ( $endpoint in $newVM.EndPoints)
    {
        if ( !($endpoint.LoadBalanced) -or ($endpoint.LoadBalanced -eq "False") )
        {
            if ( $EndPointAdded )
            {
                                Add-Content -Value "$($indents[8])," -Path $jsonFile            
            }
                                Add-Content -Value "$($indents[8]){" -Path $jsonFile
                                    Add-Content -Value "$($indents[9])^id^:^[concat(variables('lbID'),'/inboundNatRules/$vmName-$($endpoint.Name)')]^" -Path $jsonFile
                                Add-Content -Value "$($indents[8])}" -Path $jsonFile
                                LogMsg "Enabled inboundNatRule Name:$vmName-$($endpoint.Name) frontendPort:$($endpoint.PublicPort) backendPort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol) to $NIC."
                                $EndPointAdded = $true
        }
    }

                            Add-Content -Value "$($indents[7])]," -Path $jsonFile
                                #endregion
                            
                            Add-Content -Value "$($indents[7])^subnet^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                            if ( $existingSubnet )
                            {
                                Add-Content -Value "$($indents[8])^id^: ^[concat(variables('vnetID'),'/subnets/', '$existingSubnet')]^" -Path $jsonFile
                            }
                            else
                            {
                                Add-Content -Value "$($indents[8])^id^: ^[variables('defaultSubnetID')]^" -Path $jsonFile
                            }
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^privateIPAllocationMethod^: ^Dynamic^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added NIC $NIC.."
        #endregion

        #region virtualMachines
        LogMsg "Adding Virtual Machine $vmName"
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Compute/virtualMachines^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$vmName^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Compute/availabilitySets/', variables('availabilitySetName'))]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/networkInterfaces/', '$NIC')]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile

            #region VM Properties
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                #region availabilitySet
                Add-Content -Value "$($indents[4])^availabilitySet^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^id^: ^[resourceId('Microsoft.Compute/availabilitySets',variables('availabilitySetName'))]^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region Hardware Profile
                Add-Content -Value "$($indents[4])^hardwareProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^vmSize^: ^$instanceSize^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region OSProfie
                Add-Content -Value "$($indents[4])^osProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^computername^: ^$vmName^," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^adminUsername^: ^[variables('adminUserName')]^," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^adminPassword^: ^[variables('adminPassword')]^" -Path $jsonFile
                    #Add-Content -Value "$($indents[5])^linuxConfiguration^:" -Path $jsonFile
                    #Add-Content -Value "$($indents[5]){" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])^ssh^:" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6]){" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])^publicKeys^:" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])[" -Path $jsonFile
                    #            Add-Content -Value "$($indents[8])[" -Path $jsonFile
                    #                Add-Content -Value "$($indents[9]){" -Path $jsonFile
                    #                    Add-Content -Value "$($indents[10])^path^:^$sshPath^," -Path $jsonFile
                    #                    Add-Content -Value "$($indents[10])^keyData^:^$sshKeyData^" -Path $jsonFile
                    #                Add-Content -Value "$($indents[9])}" -Path $jsonFile
                    #            Add-Content -Value "$($indents[8])]" -Path $jsonFile
                    #        Add-Content -Value "$($indents[7])]" -Path $jsonFile
                    #    Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    #Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region Storage Profile
                Invoke-Command -ScriptBlock $StorageProfileScriptBlock
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                #endregion
                
                LogMsg "Added Virtual Machine $vmName"

                #region Network Profile
                Add-Content -Value "$($indents[4])^networkProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^networkInterfaces^: " -Path $jsonFile
                    Add-Content -Value "$($indents[5])[" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^id^: ^[resourceId('Microsoft.Network/networkInterfaces','$NIC')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])]" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
                #endregion

            Add-Content -Value "$($indents[3])}" -Path $jsonFile
            LogMsg "Attached Network Interface Card `"$NIC`" to Virtual Machine `"$vmName`"."
            #endregion

        Add-Content -Value "$($indents[2])}" -Path $jsonFile
        #endregion
        
        $vmAdded = $true
        $role  = $role + 1
        $vmCount = $role
}
    Add-Content -Value "$($indents[1])]" -Path $jsonFile
    }
    #endregion
    
    #region Single VM Deployment...
if ( $numberOfVMs -eq 1)
{
    if($newVM.RoleName)
    {
        $vmName = $newVM.RoleName
    }
    else
    {
        $vmName = $RGName+"-role-0"
    }
    $vmAdded = $false
    $newVM = $RGXMLData.VirtualMachine    
    $vmCount = $vmCount + 1
    $VnetName = $RGXMLData.VnetName
    $instanceSize = $newVM.ARMInstanceSize
    $SubnetName = $newVM.ARMSubnetName
    $DnsServerIP = $RGXMLData.DnsServerIP
    $NIC = "NIC" + "-$vmName"
    $SecurityGroupName = "SG-$RGName"

            #region networkInterfaces
        LogMsg "Adding Network Interface Card $NIC.."
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/networkInterfaces^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$NIC^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/publicIPAddresses/', variables('publicIPAddressName'))]^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/virtualNetworks/', variables('virtualNetworkName'))]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile

            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^ipConfigurations^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^ipconfig1^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^privateIPAllocationMethod^: ^Dynamic^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^publicIPAddress^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[resourceId('Microsoft.Network/publicIPAddresses',variables('publicIPAddressName'))]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^subnet^:" -Path $jsonFile
                            Add-Content -Value "$($indents[7]){" -Path $jsonFile
                                Add-Content -Value "$($indents[8])^id^: ^[variables('defaultSubnetID')]^" -Path $jsonFile
                            Add-Content -Value "$($indents[7])}" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                Add-Content -Value "$($indents[4])]," -Path $jsonFile
                Add-Content -Value "$($indents[4])^networkSecurityGroup^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^id^: ^[resourceId('Microsoft.Network/networkSecurityGroups','$SecurityGroupName')]^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
		LogMsg "Added NIC $NIC.."
		#region multiple Nics
		[System.Collections.ArrayList]$NicNameList= @()
		foreach ($NetworkInterface in $newVM.NetworkInterfaces)
		{
			$NicName = $NetworkInterface.Name
			$NicNameList.add($NicName)
			Add-Content -Value "$($indents[2]){" -Path $jsonFile
				Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
				Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/networkInterfaces^," -Path $jsonFile
				Add-Content -Value "$($indents[3])^name^: ^$NicName^," -Path $jsonFile
				Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
				Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
				Add-Content -Value "$($indents[3])[" -Path $jsonFile
					Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/virtualNetworks/', variables('virtualNetworkName'))]^" -Path $jsonFile
				Add-Content -Value "$($indents[3])]," -Path $jsonFile

				Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
				Add-Content -Value "$($indents[3]){" -Path $jsonFile
					Add-Content -Value "$($indents[4])^ipConfigurations^: " -Path $jsonFile
					Add-Content -Value "$($indents[4])[" -Path $jsonFile
						Add-Content -Value "$($indents[5]){" -Path $jsonFile
							Add-Content -Value "$($indents[6])^name^: ^ipconfig1^," -Path $jsonFile
							Add-Content -Value "$($indents[6])^properties^: " -Path $jsonFile
							Add-Content -Value "$($indents[6]){" -Path $jsonFile
								Add-Content -Value "$($indents[7])^subnet^:" -Path $jsonFile
								Add-Content -Value "$($indents[7]){" -Path $jsonFile
									Add-Content -Value "$($indents[8])^id^: ^[variables('defaultSubnetID')]^" -Path $jsonFile
								Add-Content -Value "$($indents[7])}" -Path $jsonFile
							Add-Content -Value "$($indents[6])}" -Path $jsonFile
						Add-Content -Value "$($indents[5])}" -Path $jsonFile
					Add-Content -Value "$($indents[4])]," -Path $jsonFile
				Add-Content -Value "$($indents[3])}" -Path $jsonFile
			Add-Content -Value "$($indents[2])}," -Path $jsonFile
		}
		#endregion
        
        #endregion

            #region networkSecurityGroups
        LogMsg "Adding Security Group $SecurityGroupName.."
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Network/networkSecurityGroups^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$SecurityGroupName^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^securityRules^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile
                #region Add Endpoints...
                $securityRulePriority = 101
                $securityRuleAdded = $false
                foreach ( $endpoint in $newVM.EndPoints)
                {
                    if ( $securityRuleAdded )
                    {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile            
                    $securityRulePriority += 10
                    }
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^name^: ^$($endpoint.Name)^," -Path $jsonFile
                        Add-Content -Value "$($indents[6])^properties^:" -Path $jsonFile
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^: ^$($endpoint.Protocol)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^sourcePortRange^: ^*^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^destinationPortRange^: ^$($endpoint.PublicPort)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^sourceAddressPrefix^: ^*^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^destinationAddressPrefix^: ^*^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^access^: ^Allow^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^priority^: $securityRulePriority," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^direction^: ^Inbound^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
                    LogMsg "Added securityRule Name:$($endpoint.Name) destinationPortRange:$($endpoint.PublicPort) Protocol:$($endpoint.Protocol) Priority:$securityRulePriority."
                    $securityRuleAdded = $true
                }
                #endregion
                Add-Content -Value "$($indents[4])]," -Path $jsonFile
                Add-Content -Value "$($indents[4])^networkInterfaces^: " -Path $jsonFile
                Add-Content -Value "$($indents[4])[" -Path $jsonFile			
                    Add-Content -Value "$($indents[5]){" -Path $jsonFile
                        Add-Content -Value "$($indents[6])^id^:^[resourceId('Microsoft.Network/networkInterfaces','$NIC')]^" -Path $jsonFile
                    Add-Content -Value "$($indents[5])}" -Path $jsonFile
					#region configure multiple Nics 
					foreach($NicName in $NicNameList)
					{
						Add-Content -Value "$($indents[5])," -Path $jsonFile 
						Add-Content -Value "$($indents[5]){" -Path $jsonFile
							Add-Content -Value "$($indents[6])^id^:^[resourceId('Microsoft.Network/networkInterfaces','$NicName')]^" -Path $jsonFile
						Add-Content -Value "$($indents[5])}" -Path $jsonFile
						LogMsg "Added Nic $NicName to Security Group $SecurityGroupName"
					}
					#endregion
                Add-Content -Value "$($indents[4])]" -Path $jsonFile
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
			
        Add-Content -Value "$($indents[2])}," -Path $jsonFile
        LogMsg "Added Security Group $SecurityGroupName.."
        #endregion

        #region virtualMachines
        LogMsg "Adding Virtual Machine $vmName.."
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Compute/virtualMachines^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$vmName^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
				#region configure multiple Nics to virtualMachines 
				foreach($NicName in $NicNameList)
				{
					Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/networkInterfaces/', '$NicName')]^," -Path $jsonFile
					LogMsg "Added Nic $NicName to virtualMachines"
				}
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Network/networkInterfaces/', '$NIC')]^" -Path $jsonFile
				LogMsg "Added Nic $NIC to virtualMachines"
				#endregion		
            Add-Content -Value "$($indents[3])]," -Path $jsonFile
            #region VM Properties
            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                #region Hardware Profile
                Add-Content -Value "$($indents[4])^hardwareProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^vmSize^: ^$instanceSize^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region OSProfie
                Add-Content -Value "$($indents[4])^osProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^computername^: ^$vmName^," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^adminUsername^: ^[variables('adminUserName')]^," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^adminPassword^: ^[variables('adminPassword')]^" -Path $jsonFile
                Add-Content -Value "$($indents[4])}," -Path $jsonFile
                #endregion

                #region Storage Profile
                Invoke-Command -ScriptBlock $StorageProfileScriptBlock
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                #endregion
                
                #region Network Profile
                Add-Content -Value "$($indents[4])^networkProfile^: " -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                    Add-Content -Value "$($indents[5])^networkInterfaces^: " -Path $jsonFile
                    Add-Content -Value "$($indents[5])[" -Path $jsonFile
					#region configure multiple Nics to networkProfile
					if($NicNameList)
					{
						foreach($NicName in $NicNameList)
						{
							Add-Content -Value "$($indents[6]){" -Path $jsonFile
								Add-Content -Value "$($indents[7])^id^: ^[resourceId('Microsoft.Network/networkInterfaces','$NicName')]^," -Path $jsonFile
								Add-Content -Value "$($indents[7])^properties^: { ^primary^: false }" -Path $jsonFile
							Add-Content -Value "$($indents[6])}," -Path $jsonFile
						}							
						Add-Content -Value "$($indents[6]){" -Path $jsonFile
							Add-Content -Value "$($indents[7])^id^: ^[resourceId('Microsoft.Network/networkInterfaces','$NIC')]^," -Path $jsonFile
							Add-Content -Value "$($indents[7])^properties^: { ^primary^: true }" -Path $jsonFile
						Add-Content -Value "$($indents[6])}" -Path $jsonFile
					}
					else
					{
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^id^: ^[resourceId('Microsoft.Network/networkInterfaces','$NIC')]^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
					}	
					#endregion
                    Add-Content -Value "$($indents[5])]," -Path $jsonFile
                    Add-Content -Value "$($indents[5])^inputEndpoints^: " -Path $jsonFile
                    Add-Content -Value "$($indents[5])[" -Path $jsonFile
                    
                    #region Add Endpoints...
                    $EndPointAdded = $false
                    foreach ( $endpoint in $newVM.EndPoints)
                    {
                        if ( $EndPointAdded )
                        {
                            Add-Content -Value "$($indents[6])," -Path $jsonFile            
                        }
                        Add-Content -Value "$($indents[6]){" -Path $jsonFile
                            Add-Content -Value "$($indents[7])^enableDirectServerReturn^: ^False^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^endpointName^: ^$($endpoint.Name)^," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^privatePort^: $($endpoint.LocalPort)," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^publicPort^: $($endpoint.PublicPort)," -Path $jsonFile
                            Add-Content -Value "$($indents[7])^protocol^: ^$($endpoint.Protocol)^" -Path $jsonFile
                        Add-Content -Value "$($indents[6])}" -Path $jsonFile
                        LogMsg "Added input endpoint Name:$($endpoint.Name) PublicPort:$($endpoint.PublicPort) PrivatePort:$($endpoint.LocalPort) Protocol:$($endpoint.Protocol)."
                        $EndPointAdded = $true
                    }
                    #endregion 

                    Add-Content -Value "$($indents[5])]" -Path $jsonFile
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
                #endregion
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
            LogMsg "Added Network Profile."
            #endregion
        LogMsg "Added Virtual Machine $vmName"
        Add-Content -Value "$($indents[2])}" -Path $jsonFile
        #endregion

        #region Extensions
if ( $CurrentTestData.ProvisionTimeExtensions)
{
    foreach ( $extension in $CurrentTestData.ProvisionTimeExtensions.Split(",") )
    {
		$extension = $extension.Trim()
		foreach ( $newExtn in $extensionXML.Extensions.Extension )
		{
			if ($newExtn.Name -eq $extension)
			{
        Add-Content -Value "$($indents[2])," -Path $jsonFile
        Add-Content -Value "$($indents[2]){" -Path $jsonFile
            Add-Content -Value "$($indents[3])^apiVersion^: ^$apiVersion^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^type^: ^Microsoft.Compute/virtualMachines/extensions^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^name^: ^$vmName/$extension^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^location^: ^[variables('location')]^," -Path $jsonFile
            Add-Content -Value "$($indents[3])^dependsOn^: " -Path $jsonFile
            Add-Content -Value "$($indents[3])[" -Path $jsonFile
                Add-Content -Value "$($indents[4])^[concat('Microsoft.Compute/virtualMachines/', '$vmName')]^" -Path $jsonFile
            Add-Content -Value "$($indents[3])]," -Path $jsonFile

            Add-Content -Value "$($indents[3])^properties^:" -Path $jsonFile
            Add-Content -Value "$($indents[3]){" -Path $jsonFile
                Add-Content -Value "$($indents[4])^publisher^:^$($newExtn.Publisher)^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^type^:^$($newExtn.OfficialName)^," -Path $jsonFile
                Add-Content -Value "$($indents[4])^typeHandlerVersion^:^$($newExtn.LatestVersion)^" -Path $jsonFile
            if ($newExtn.PublicConfiguration)
            {
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                Add-Content -Value "$($indents[4])^settings^:" -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                $isConfigAdded = $false
                foreach ($extnConfig in $newExtn.PublicConfiguration.ChildNodes)
                {
                    if ( $isConfigAdded )
                    {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile
                    }
                    Add-Content -Value "$($indents[5])^$($extnConfig.Name)^ : ^$($extnConfig.'#text')^" -Path $jsonFile
                    LogMsg "Added $extension Extension : Public Configuration : $($extnConfig.Name) = $($extnConfig.'#text')"
                    $isConfigAdded = $true
                } 
                Add-Content -Value "$($indents[4])}" -Path $jsonFile

            }
                if ( $newExtn.PrivateConfiguration )
                {
                Add-Content -Value "$($indents[4])," -Path $jsonFile
                Add-Content -Value "$($indents[4])^protectedSettings^:" -Path $jsonFile
                Add-Content -Value "$($indents[4]){" -Path $jsonFile
                $isConfigAdded = $false
                foreach ($extnConfig in $newExtn.PrivateConfiguration.ChildNodes)
                {
                    if ( $isConfigAdded )
                    {
                    Add-Content -Value "$($indents[5])," -Path $jsonFile
                    }
                    Add-Content -Value "$($indents[5])^$($extnConfig.Name)^ : ^$($extnConfig.'#text')^" -Path $jsonFile
                    LogMsg "Added $extension Extension : Private Configuration : $($extnConfig.Name) = $( ( ( $extnConfig.'#text' -replace "\w","*") -replace "\W","*" ) )"
                    $isConfigAdded = $true
                } 
                Add-Content -Value "$($indents[4])}" -Path $jsonFile
                }
            Add-Content -Value "$($indents[3])}" -Path $jsonFile
        Add-Content -Value "$($indents[2])}" -Path $jsonFile
            }
        }   
    }
}
        #endregion extension
        
    Add-Content -Value "$($indents[1])]" -Path $jsonFile
    #endregion
}
Add-Content -Value "$($indents[0])}" -Path $jsonFile
Set-Content -Path $jsonFile -Value (Get-Content $jsonFile).Replace("^",'"') -Force
#endregion

    LogMsg "Template generated successfully."
    return $createSetupCommand,  $RGName, $vmCount
} 

Function DeployResourceGroups ($xmlConfig, $setupType, $Distro, $getLogsIfFailed = $false, $GetDeploymentStatistics = $false)
{
    if( (!$EconomyMode) -or ( $EconomyMode -and ($xmlConfig.config.Azure.Deployment.$setupType.isDeployed -eq "NO")))
    {
        try
        {
            $VerifiedGroups =  $NULL
            $retValue = $NULL
            #$ExistingGroups = RetryOperation -operation { Get-AzureResourceGroup } -description "Getting information of existing resource groups.." -retryInterval 5 -maxRetryCount 5
            $i = 0
            $role = 1
            $setupTypeData = $xmlConfig.config.Azure.Deployment.$setupType
            $isAllDeployed = CreateAllResourceGroupDeployments -setupType $setupType -xmlConfig $xmlConfig -Distro $Distro
            $isAllVerified = "False"
            $isAllConnected = "False"
            #$isAllDeployed = @("True","ICA-RG-IEndpointSingleHS-U1510-8-10-12-34-9","30")
            if($isAllDeployed[0] -eq "True")
            {
                $deployedGroups = $isAllDeployed[1]
                $resourceGroupCount = $isAllDeployed[2]
                $DeploymentElapsedTime = $isAllDeployed[3]
                $GroupsToVerify = $deployedGroups.Split('^')
                #if ( $GetDeploymentStatistics )
                #{
                #    $VMBooTime = GetVMBootTime -DeployedGroups $deployedGroups -TimeoutInSeconds 1800
                #    $verifyAll = VerifyAllDeployments -GroupsToVerify $GroupsToVerify -GetVMProvisionTime $GetDeploymentStatistics
                #    $isAllVerified = $verifyAll[0]
                #    $VMProvisionTime = $verifyAll[1]
                #}
                #else
                #{
                #    $isAllVerified = VerifyAllDeployments -GroupsToVerify $GroupsToVerify
                #}
                #if ($isAllVerified -eq "True")
                #{
                    $allVMData = GetAllDeployementData -ResourceGroups $deployedGroups
                    Set-Variable -Name allVMData -Value $allVMData -Force -Scope Global
                    $isAllConnected = isAllSSHPortsEnabledRG -AllVMDataObject $allVMData
                    if ($isAllConnected -eq "True")
                    {
                        $VerifiedGroups = $deployedGroups
                        $retValue = $VerifiedGroups
                        #$vnetIsAllConfigured = $false
                        $xmlConfig.config.Azure.Deployment.$setupType.isDeployed = $retValue
                        #Collecting Initial Kernel
                        $KernelLogOutput= GetAndCheckKernelLogs -allDeployedVMs $allVMData -status "Initial"
                    }
                    else
                    {
                        LogErr "Unable to connect Some/All SSH ports.."
                        $retValue = $NULL  
                    }
                #}
                #else
                #{
                #    Write-Host "Provision Failed for one or more VMs"
                #    $retValue = $NULL
                #}
                
            }
            else
            {
                LogErr "One or More Deployments are Failed..!"
                $retValue = $NULL
            }
            # get the logs of the first provision-failed VM
            #if ($retValue -eq $NULL -and $getLogsIfFailed -and $DebugOsImage)
            #{
            #    foreach ($service in $GroupsToVerify)
            #    {
            #        $VMs = Get-AzureVM -ServiceName $service
            #        foreach ($vm in $VMs)
            #        {
            #            if ($vm.InstanceStatus -ne "ReadyRole" )
            #            {
            #                $out = GetLogsFromProvisionFailedVM -vmName $vm.Name -serviceName $service -xmlConfig $xmlConfig
            #                return $NULL
            #            }
            #        }
            #    }
            #}
        }
        catch
        {
            LogMsg "Exception detected. Source : DeployVMs()"
            $retValue = $NULL
        }
    }
    else
    {
        $retValue = $xmlConfig.config.Azure.Deployment.$setupType.isDeployed
        $KernelLogOutput= GetAndCheckKernelLogs -allDeployedVMs $allVMData -status "Initial"
    }
    if ( $GetDeploymentStatistics )
    {
        return $retValue, $DeploymentElapsedTime, $VMBooTime, $VMProvisionTime
    }
    else
    {
        return $retValue
    }
}

Function isAllSSHPortsEnabledRG($AllVMDataObject)
{
    LogMsg "Trying to Connect to deployed VM(s)"
    $timeout = 0
    do
    {
        $WaitingForConnect = 0
        foreach ( $vm in $AllVMDataObject)
        {
            Write-Host "Connecting to  $($vm.PublicIP) : $($vm.SSHPort)" -NoNewline
            $out = Test-TCP  -testIP $($vm.PublicIP) -testport $($vm.SSHPort)
            if ($out -ne "True")
            { 
                Write-Host " : Failed"
                $WaitingForConnect = $WaitingForConnect + 1
            }
            else
            {
                Write-Host " : Connected"
            }
        }
        if($WaitingForConnect -gt 0)
        {
            $timeout = $timeout + 1
            Write-Host "$WaitingForConnect VM(s) still awaiting to open SSH port.." -NoNewline
            Write-Host "Retry $timeout/200"
            sleep 3
            $retValue = "False"
        }
        else
        {
            LogMsg "ALL VM's SSH port is/are open now.."
            $retValue = "True"
        }

    }
    While (($timeout -lt 200) -and ($WaitingForConnect -gt 0))

    return $retValue
}

#Deployment via template file and template parameters file
Function CreateRGDeploymentWithTempParameters([string]$RGName, $TemplateFile, $TemplateParameterFile)
{
    $FailCounter = 0
    $retValue = "False"
    $ResourceGroupDeploymentName = $RGName + "-deployment"
    While(($retValue -eq $false) -and ($FailCounter -lt 1))
    {
        try
        {
            $FailCounter++
            LogMsg "Creating Deployment using $TemplateFile $TemplateParameterFile..."
            $createRGDeployment = New-AzureResourceGroupDeployment -Name $ResourceGroupDeploymentName -ResourceGroupName $RGName -TemplateFile $TemplateFile -TemplateParameterFile $TemplateParameterFile -Verbose
            $operationStatus = $createRGDeployment.ProvisioningState
            if ($operationStatus  -eq "Succeeded")
            {
                LogMsg "Resource Group Deployment Created."
                $retValue = $true
            }
            else 
            {
                LogErr "Failed to create Resource Group Deployment."
                $retValue = $false
            }
        }
        catch
        {
            $retValue = $false
        }
    }
    return $retValue
}

Function CreateAllRGDeploymentsWithTempParameters($templateName, $location, $TemplateFile, $TemplateParameterFile)
{
    $resourceGroupCount = 0
    $curtime = Get-Date
    $isServiceDeployed = "False"
    $retryDeployment = 0
    $groupName = "ICA-RG-" + $templateName + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second

    while (($isServiceDeployed -eq "False") -and ($retryDeployment -lt 3))
    {
        LogMsg "Creating Resource Group : $groupName."
        LogMsg "Verifying that Resource group name is not in use."
        $isRGDeleted = DeleteResourceGroup -RGName $groupName
        if ($isRGDeleted)
        {    
            $isServiceCreated = CreateResourceGroup -RGName $groupName -location $location
            if ($isServiceCreated -eq "True")
            {
                $DeploymentStartTime = (Get-Date)
				$CreateRGDeployments = CreateRGDeploymentWithTempParameters -RGName $groupName -location $location -TemplateFile $TemplateFile -TemplateParameterFile $TemplateParameterFile
                $DeploymentEndTime = (Get-Date)
                $DeploymentElapsedTime = $DeploymentEndTime - $DeploymentStartTime
                if ( $CreateRGDeployments )
                {
                        $retValue = "True"
                        $isServiceDeployed = "True"
                        $resourceGroupCount = $resourceGroupCount + 1
                        $deployedGroups = $groupName

                }
                else
                {
                    LogErr "Unable to Deploy one or more VM's"
                    $retryDeployment = $retryDeployment + 1
                    $retValue = "False"
                    $isServiceDeployed = "False"
                }
            }
            else
            {
                LogErr "Unable to create $groupName"
                $retryDeployment = $retryDeployment + 1
                $retValue = "False"
                $isServiceDeployed = "False"
            }
        }    
        else
        {
            LogErr "Unable to delete existing resource group - $groupName"
            $retryDeployment = $retryDeployment + 1
            $retValue = "False"
            $isServiceDeployed = "False"
        }
    }
    return $retValue, $deployedGroups, $resourceGroupCount, $DeploymentElapsedTime
}