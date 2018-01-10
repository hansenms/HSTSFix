param(

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [String]$ProxyWebAppName,

    [Parameter(Mandatory=$true)]
    [String]$Endpoint,

    # Path to SSL (*.pfx) file to be used on the Application Gateways
    [Parameter(Mandatory = $true)]
    [String]$CertificatePath,

    # Password for SSL cert file
    [Parameter(Mandatory = $true)]
    [SecureString]$CertificatePassword,

    # App Service Plan Tier
    [Parameter(Mandatory=$false)]
    [String]$AppServicePlanTier = "Standard",

    # Application Gateway SKU
    [Parameter(Mandatory = $false)]
    [ValidateSet("Standard_Small", "Standard_Medium", "Standard_Large")]
    [String]$ApplicationGatewaySku = "Standard_Small",    

    # Number of Application Gateway Instances
    [Parameter(Mandatory = $false)]
    [Int]$ApplicationGatewayInstances = 2    
)

$azcontext = Get-AzureRmContext
if ([string]::IsNullOrEmpty($azcontext.Account)) {
    throw "You must be logged into Azure to use this script"
}


$rg = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction 0 -ErrorVariable NotPresent
if ($NotPresent) {
    $rg = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

$asp = Get-AzureRmAppServicePlan -Name $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -ErrorAction 0 -ErrorVariable NotPresent
if ($NotPresent) {
    $asp = New-AzureRmAppServicePlan -Name $ProxyWebAppName -Location $rg.Location -ResourceGroupName $rg.ResourceGroupName -Tier $AppServicePlanTier
}

$webApp = Get-AzureRmWebApp -Name $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -ErrorAction 0 -ErrorVariable NotPresent

if ($NotPresent) {
    $webApp = New-AzureRmWebApp -Name $ProxyWebAppName -Location $rg.Location -AppServicePlan $WebAppName -ResourceGroupName $rg.ResourceGroupName
}

#Create a web config file with suitable endpoint
(Get-Content .\web.config).replace('@@HOSTNAME@@', $Endpoint) | Set-Content .\tmp.web.config

#Copy files to Proxy
$creds = Copy-FileToWebApp -WebAppName $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -File .\probe.html -Destination "/probe.html"
$creds = Copy-FileToWebApp -WebAppName $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -File .\applicationHost.xdt -Destination "../applicationHost.xdt" -PublishingCredentials $creds
$creds = Copy-FileToWebApp -WebAppName $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -File .\tmp.web.config -Destination "/web.config" -PublishingCredentials $creds

Restart-AzureRmWebApp -Name $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName
