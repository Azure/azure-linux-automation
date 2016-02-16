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
	$jsonfile =  Get-Content ..\azure-quickstart-templates\cloudera-on-centos\azuredeploy.parameters.json -Raw | ConvertFrom-Json
	$curtime = Get-Date
	$timestr = "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
	$jsonfile.parameters.storageAccountPrefix.value = $parameters.storageAccountPrefix + $curtime.Month + $curtime.Day + $curtime.Hour + $curtime.Minute + $curtime.Second
	$jsonfile.parameters.dnsNamePrefix.value = $parameters.dnsNamePrefix + $timestr
	$jsonfile.parameters.virtualNetworkName.value = $parameters.virtualNetworkName + $timestr
	$jsonfile.parameters.subnetName.value = $parameters.subnetName + $timestr
	$jsonfile.parameters.numberOfDataNodes.value = [int]$parameters.numberOfDataNodes
	$jsonfile.parameters.adminPassword.value = $password.Replace('"','')
	$jsonfile.parameters.cmPassword.value = $password.Replace('"','')
	if($env:GetRandomValue -eq $True)
	{
		$AllowedValue =  Get-Content ..\azure-quickstart-templates\cloudera-on-centos\azuredeploy.json -Raw | ConvertFrom-Json
		$jsonfile.parameters.location.value = $AllowedValue.parameters.location.allowedValues | Get-Random
		$jsonfile.parameters.tshirtSize.value = $AllowedValue.parameters.tshirtSize.allowedValues | Get-Random
	}
	else
	{
		$jsonfile.parameters.location.value = $location.Replace('"','').Replace(' ','').ToLower()	
		$jsonfile.parameters.vmSize.value = $parameters.vmSize
		if($env:RoleInstanceSize)
		{
			$jsonfile.parameters.vmSize.value = $env:RoleInstanceSize
		}
		if($jsonfile.parameters.vmSize.value -match 'DS' -or $jsonfile.parameters.vmSize.value -match 'DS')
		{
			$jsonfile.parameters.storageAccountType.value = 'Premium_LRS'
		}
		else
		{
			$jsonfile.parameters.storageAccountType.value = 'Standard_LRS'
		}
	}
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

	$isDeployed = CreateAllRGDeploymentsWithTempParameters -templateName $templateName -location $location -TemplateFile ..\azure-quickstart-templates\cloudera-on-centos\azuredeploy.json  -TemplateParameterFile .\azuredeploy.parameters.json


	if ($isDeployed[0] -eq $True)
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
