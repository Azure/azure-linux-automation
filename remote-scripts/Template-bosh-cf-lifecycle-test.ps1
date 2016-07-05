<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

try
{
    $templateName = $currentTestData.testName
    $parameters = $currentTestData.parameters
    $location = $xmlConfig.config.Azure.General.Location

    if(Test-Path .\azuredeploy.parameters.json)
    {
        Remove-Item .\azuredeploy.parameters.json
    }

    # update template parameter file 
    LogMsg 'update template parameter file '
    $jsonfile =  Get-Content ..\azure-quickstart-templates\bosh-setup\azuredeploy.parameters.json -Raw | ConvertFrom-Json
    $curtime = Get-Date
    $timestr = "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
    $jsonfile.parameters.vmName.value = $parameters.vmName + $timestr
    $jsonfile.parameters.adminUsername.value = $parameters.adminUsername
    $jsonfile.parameters.sshKeyData.value = $parameters.sshKeyData
    $jsonfile.parameters.environment.value = $parameters.environment
    $jsonfile.parameters.tenantID.value = $parameters.tenantID
    $jsonfile.parameters.clientID.value = $parameters.clientID
    $jsonfile.parameters.clientSecret.value = $parameters.clientSecret
    $jsonfile.parameters.autoDeployBosh.value = $parameters.autoDeployBosh
    
    # save template parameter file
    $jsonfile | ConvertTo-Json | Out-File .\azuredeploy.parameters.json
    if(Test-Path .\azuredeploy.parameters.json)
    {
        LogMsg "successful save azuredeploy.parameters.json"
    }
    else
    {
        LogMsg "fail to save azuredeploy.parameters.json"
    }


    $isDeployed = CreateAllRGDeploymentsWithTempParameters -templateName $templateName -location $location -TemplateFile ..\azure-quickstart-templates\bosh-setup\azuredeploy.json  -TemplateParameterFile .\azuredeploy.parameters.json

    if ($isDeployed[0] -eq $True)
    {

        $testResult_deploy = "PASS"
    }
    else
    {
        $testResult_deploy = "Failed"
    }

    # connect to the devbox
    $subscription_id = $AzureSetup.SubscriptionID
    $storage = $(Find-AzureRmResource -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceGroupNameContains $isDeployed[1]).ResourceName
    $rgname = $isDeployed[1]
    $tenantid = $jsonfile.parameters.tenantID.value
    $clientid = $jsonfile.parameters.clientID.value
    $clientsecret = $jsonfile.parameters.clientSecret.value
    $sshpublickey = $jsonfile.parameters.sshKeyData.value
    $azureenv = $jsonfile.parameters.environment.value
    $dep_ssh_info = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['sshDevBox'].Value.Split(' ')[1]
    LogMsg $dep_ssh_info
    $port = 22
    $sshKey = "cf_devbox_privatekey.ppk"

    $prepare = @"
#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install -y git
retry=1
while [ `${retry} -lt 20 ]; do
    sudo rm -rf bosh-azure-cpi-release/
    echo 'clone cpi repo retry#'`${retry}
    sudo git clone https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release.git
    if [ `$? -eq 0 ]; then
        echo 'clone cpi repo successfully.'
        break
    else
        let retry=retry+1
    fi
done

function retryop()
{
    retry=1
    while [ `${retry} -lt 60 ]; do
        echo 'op:'`$1
        echo 'retry#'`${retry}
        eval `$1
        if [ `$? -eq 0 ]; then
            echo 'successfully.'
            break
        else
            let retry=retry+1
        fi
    done
}

which node
if [ `$? -eq 0 ]; then
    echo 'nodejs installed.'
else
    echo 'nodejs seems not installed failed, will be installed.'
    retryop 'sudo apt-get update'
    retryop 'curl -sL https://deb.nodesource.com/setup_5.x | sudo -E bash -'
    retryop 'sudo apt-get install -y nodejs'
fi

which azure
if [ `$? -eq 0 ]; then
    echo 'azure cli installed.'
else
    echo 'azure cli seems not installed, will be installed.'
    retryop 'sudo npm --registry https://registry.npm.taobao.org install azure-cli@0.9.18 -g'
fi

node_ver=``node -v``
node_ver_major=``echo `$node_ver | cut -b1-2``
azurecli_ver=``azure -v``
echo `$node_ver
echo `$node_ver_major
echo `$azurecli_ver

if [ `$node_ver_major = 'v5' ]; then
    echo 'node version check pass.'
else
    echo 'node version check failed. will remove and install again.'
    sudo apt-get remove nodejs -y
    retryop 'curl -sL https://deb.nodesource.com/setup_5.x | sudo -E bash -'
    retryop 'sudo apt-get install -y nodejs'
fi

if [ `$azurecli_ver = '0.9.18' ]; then
    echo 'azure cli version check pass.'
else
    echo 'azure cli version check failed. will remove and install again.'
    sudo npm remove azure-cli -g
    retryop 'sudo npm --registry https://registry.npm.taobao.org install azure-cli@0.9.18 -g'
fi

"@
   
    # generate the life cycle test script
    $src = @"
#!/usr/bin/env bash
cf_ip=``grep -i 'cf-ip' settings | awk {'print `$2'} | tr -d ',' | tr -d '"'``

export BOSH_AZURE_SUBSCRIPTION_ID=$subscription_id
export BOSH_AZURE_STORAGE_ACCOUNT_NAME=$storage
export BOSH_AZURE_RESOURCE_GROUP_NAME='$rgname'
export BOSH_AZURE_TENANT_ID=$tenantid
export BOSH_AZURE_CLIENT_ID=$clientid
export BOSH_AZURE_CLIENT_SECRET=$clientsecret
export BOSH_AZURE_VNET_NAME='boshvnet-crp'
export BOSH_AZURE_SUBNET_NAME='Bosh'
export BOSH_AZURE_SSH_PUBLIC_KEY='$sshpublickey'
export BOSH_AZURE_DEFAULT_SECURITY_GROUP='nsg-bosh'
export BOSH_AZURE_ENVIRONMENT='$azureenv'
export BOSH_AZURE_RESOURCE_GROUP_NAME_FOR_VMS='$rgname'
export BOSH_AZURE_RESOURCE_GROUP_NAME_FOR_NETWORK='$rgname'
export BOSH_AZURE_PRIMARY_PUBLIC_IP=`${cf_ip}
export BOSH_AZURE_SECONDARY_PUBLIC_IP=`${cf_ip}


if [ `${BOSH_AZURE_ENVIRONMENT} == 'AzureChinaCloud' ]; then
    export STEMCELL_DOWNLOAD_URL='https://cloudfoundry.blob.core.chinacloudapi.cn/stemcells/bosh-stemcell-3169-azure-hyperv-ubuntu-trusty-go_agent.tgz'
    echo ${STEMCELL_DOWNLOAD_URL}
fi

if [ `${BOSH_AZURE_ENVIRONMENT} == 'AzureCloud' ]; then
    export STEMCELL_DOWNLOAD_URL='https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3169'
    echo ${STEMCELL_DOWNLOAD_URL}
fi

azure login --service-principal -u `${BOSH_AZURE_CLIENT_ID} -p `${BOSH_AZURE_CLIENT_SECRET} --tenant `${BOSH_AZURE_TENANT_ID} -e `${BOSH_AZURE_ENVIRONMENT}
azure config mode arm
AZURE_STORAGE_ACCESS_KEY=`$(azure storage account keys list `${BOSH_AZURE_STORAGE_ACCOUNT_NAME} -g `${BOSH_AZURE_RESOURCE_GROUP_NAME} --json | jq '.key1' -r)

export BOSH_AZURE_STEMCELL_ID="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
export AZURE_STORAGE_ACCOUNT=`${BOSH_AZURE_STORAGE_ACCOUNT_NAME}
export AZURE_STORAGE_ACCESS_KEY

azure storage blob show stemcell `${BOSH_AZURE_STEMCELL_ID}.vhd
if [ `$? -eq 1 ]; then
    echo 'download stemcell'
    wget -q -O `${PWD}/stemcell.tgz `${STEMCELL_DOWNLOAD_URL}
    echo 'upload stemcell to storage'
    sudo tar -xf `${PWD}/stemcell.tgz -C /mnt/
    sudo tar -xf /mnt/image -C /mnt/
    azure storage blob upload -q --blobtype PAGE /mnt/root.vhd stemcell `${BOSH_AZURE_STEMCELL_ID}.vhd
fi

function retryop()
{
    retry=1
    while [ `${retry} -lt 200 ]; do
        echo 'op:'`$1
        echo 'retry#'`${retry}
        eval `$1
        if [ `$? -eq 0 ]; then
            echo 'successfully.'
            break
        else
            let retry=retry+1
        fi
    done
}

cd bosh-azure-cpi-release/src/bosh_azure_cpi

if [ `${BOSH_AZURE_ENVIRONMENT} = 'AzureChinaCloud' ]; then
  echo 'configure gem sources for mooncake.'
  gem sources --remove https://rubygems.org/
  gem sources --add https://ruby.taobao.org/
  gem sources --add https://gems.ruby-china.org/
fi

gem sources -l
gem sources -c
gem sources -u

retryop 'sudo gem install bundler --no-ri --no-rdoc'
sudo ln -s /usr/local/bin/bundle /usr/bin/bundle
retryop 'bundle install'
bundle exec rspec spec/integration
"@

    $src | Out-File .\run-lifecycletest.sh -Encoding utf8
    $prepare | Out-File .\prepare-lifecycletest.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\run-lifecycletest.sh
    .\tools\dos2unix.exe -q .\prepare-lifecycletest.sh
    
    # uploading script to devbox
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\run-lifecycletest.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\prepare-lifecycletest.sh ${dep_ssh_info}:

    # kickoff test
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x *.sh"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./prepare-lifecycletest.sh &> preparetest.log"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./run-lifecycletest.sh &> lifecycletest.log"
    $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "cat lifecycletest.log"

    if ($out -match "0 failure")
    {
        $testResult_life_cycle_test = "PASS"
        LogMsg "life cycle test successfully"
    }
    else
    {
        $testResult_life_cycle_test = "Failed"
        LogMsg "life cycle test failed, please ssh to devbox check details from lifecycletest.log"
    }

    if ($testResult_deploy -eq "PASS" -and $testResult_life_cycle_test -eq "PASS")
    {
        $testResult = "PASS"
    }
    else
    {
        $testResult = "Failed"
    }


    $testStatus = "TestCompleted"
    LogMsg "Test result : $testResult"

    if ($testStatus -eq "TestCompleted")
    {
        LogMsg "Test Completed"
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

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed[1] -ResourceGroups $isDeployed[1]

#Return the result and summery to the test suite script..
return $result
