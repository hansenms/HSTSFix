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

#Load shared functions
. .\WebAppFiles.ps1

$azcontext = Get-AzureRmContext
if ([string]::IsNullOrEmpty($azcontext.Account)) {
    throw "You must be logged into Azure to use this script"
}


$rg = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction 0 -ErrorVariable NotPresent
if ($NotPresent) {
    $rg = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

##
## 1. Create Proxy Web App
##

$asp = Get-AzureRmAppServicePlan -Name $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -ErrorAction 0 -ErrorVariable NotPresent
if ($NotPresent) {
    $asp = New-AzureRmAppServicePlan -Name $ProxyWebAppName -Location $rg.Location -ResourceGroupName $rg.ResourceGroupName -Tier $AppServicePlanTier
}

$webApp = Get-AzureRmWebApp -Name $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -ErrorAction 0 -ErrorVariable NotPresent

if ($NotPresent) {
    $webApp = New-AzureRmWebApp -Name $ProxyWebAppName -Location $rg.Location -AppServicePlan $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName
}

#Create a web config file with suitable endpoint
(Get-Content .\web.config).replace('@@HOSTNAME@@', $Endpoint) | Set-Content .\tmp.web.config

#Copy files to Proxy
$creds = Copy-FileToWebApp -WebAppName $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -File .\probe.html -Destination "/probe.html"
$creds = Copy-FileToWebApp -WebAppName $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -File .\applicationHost.xdt -Destination "../applicationHost.xdt" -PublishingCredentials $creds
$creds = Copy-FileToWebApp -WebAppName $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName -File .\tmp.web.config -Destination "/web.config" -PublishingCredentials $creds

Restart-AzureRmWebApp -Name $ProxyWebAppName -ResourceGroupName $rg.ResourceGroupName

##
## 2. Add Application Gateway.
##

$gwName = $rg.ResourceGroupName + "-gw"
$gwVnetName = $rg.ResourceGroupName + "-gwvnet"
$gwPublicIpName = $rg.ResourceGroupName + "-gwip"
$gwIpConfigName = $rg.ResourceGroupName + "-gwipconf"

$vnet = Get-AzureRmVirtualNetwork -Name $gwVnetName -ResourceGroupName $rg.ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0

if ($NotPresent) {
    # subnet for AG
    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name subnet01 -AddressPrefix 10.0.0.0/24

    # vnet for AG
    $vnet = New-AzureRmVirtualNetwork -Name  $gwVnetName -ResourceGroupName $rg.ResourceGroupName -Location $Location -AddressPrefix 10.0.0.0/16 -Subnet $subnet
}

# Retrieve the subnet object for AG config
$subnet=$vnet.Subnets[0]

$publicip = Get-AzureRmPublicIpAddress -Name $gwPublicIpName -ResourceGroupName $rg.ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0

if ($NotPresent) {
    # Create a public IP address
    $publicip = New-AzureRmPublicIpAddress -ResourceGroupName $rg.ResourceGroupName -name $gwPublicIpName -location $Location -AllocationMethod Dynamic
}

# Create a new IP configuration
$gipconfig = New-AzureRmApplicationGatewayIPConfiguration -Name $gwIpConfigName -Subnet $subnet

#Grab only the original URL for the app
$hostnames = $webApp.DefaultHostName

# Create a backend pool with the hostname of the web app
$pool = New-AzureRmApplicationGatewayBackendAddressPool -Name appGatewayBackendPool -BackendFqdns $hostnames

# Define the status codes to match for the probe
$match = New-AzureRmApplicationGatewayProbeHealthResponseMatch -StatusCode 200-399

# Create a probe with the PickHostNameFromBackendHttpSettings switch for web apps
$probeconfig = New-AzureRmApplicationGatewayProbeConfig -name webappprobe -Protocol Https -Path "/probe.html" -Interval 30 -Timeout 120 -UnhealthyThreshold 3 -PickHostNameFromBackendHttpSettings -Match $match

# Define the backend http settings
$poolSetting = New-AzureRmApplicationGatewayBackendHttpSettings -Name appGatewayBackendHttpSettings -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 -PickHostNameFromBackendAddress -Probe $probeconfig

# Create a new front-end port
$fp = New-AzureRmApplicationGatewayFrontendPort -Name frontendport01  -Port 443
$fp2 = New-AzureRmApplicationGatewayFrontendPort -Name frontendport02  -Port 80

# Create a new front end IP configuration
$fipconfig = New-AzureRmApplicationGatewayFrontendIPConfig -Name fipconfig01 -PublicIPAddress $publicip

$cert = New-AzureRmApplicationGatewaySSLCertificate -Name cert01 -CertificateFile $CertificatePath -Password $CertificatePassword

# Create a new listener using the front-end ip configuration and port created earlier
$listener = New-AzureRmApplicationGatewayHttpListener -Name listener01 -Protocol Https -FrontendIPConfiguration $fipconfig -FrontendPort $fp -SslCertificate $cert
$listener2 = New-AzureRmApplicationGatewayHttpListener -Name listener02 -Protocol Http -FrontendIPConfiguration $fipconfig -FrontendPort $fp2

# Create a new rule
$rule = New-AzureRmApplicationGatewayRequestRoutingRule -Name rule01 -RuleType Basic -BackendHttpSettings $poolSetting -HttpListener $listener -BackendAddressPool $pool 

# Add a redirection configuration using a permanent redirect and targeting the existing listener
$redirectconfig = New-AzureRmApplicationGatewayRedirectConfiguration -Name redirectHttptoHttps -RedirectType Permanent -TargetListener $listener -IncludePath $true -IncludeQueryString $true
$rule2 = New-AzureRmApplicationGatewayRequestRoutingRule -Name rule02 -RuleType Basic -HttpListener $listener2 -RedirectConfiguration $redirectconfig
        
# Define the application gateway SKU to use
$sku = New-AzureRmApplicationGatewaySku -Name $ApplicationGatewaySku -Tier Standard -Capacity $ApplicationGatewayInstances

#$sslpolicy = New-AzureRmApplicationGatewaySSLPolicy -PolicyType Custom -MinProtocolVersion TLSv1_2 -CipherSuite "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384", "TLS_RSA_WITH_AES_128_GCM_SHA256"

#Predefined policy with min TLS 1.1
$sslpolicy = New-AzureRmApplicationGatewaySslPolicy -PolicyType Predefined -PolicyName AppGwSslPolicy20170401

$appgw =  Get-AzureRmApplicationGateway -Name $gwName -ResourceGroupName $rg.ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0

if ($NotPresent) {
    # Create the application gateway
    $appgw = New-AzureRmApplicationGateway -Name $gwName -ResourceGroupName $rg.ResourceGroupName -Location $Location `
    -BackendAddressPools $pool -BackendHttpSettingsCollection $poolSetting -Probes $probeconfig `
    -FrontendIpConfigurations $fipconfig  -GatewayIpConfigurations $gipconfig `
    -FrontendPorts $fp,$fp2 -HttpListeners $listener,$listener2 -RequestRoutingRules $rule,$rule2 -Sku $sku `
    -SslPolicy $sslpolicy -SSLCertificates $cert -RedirectConfigurations $redirectconfig
}
