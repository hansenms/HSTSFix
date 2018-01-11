param(
    [Parameter(Mandatory)]
    [String]$ResourceGroupName,

    [Parameter(Mandatory)]
    [String]$Location,

    [Parameter(Mandatory)]
    [String]$WebAppName
)

. .\WebAppFiles.ps1

$azcontext = Get-AzureRmContext

if ([string]::IsNullOrEmpty($azcontext.Account)) {
    throw "You must be signed into Azure to run this script"
}


$rg = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location

$asp = New-AzureRmAppServicePlan -Name $WebAppName -Location $rg.Location -ResourceGroupName $rg.ResourceGroupName -Tier Free

$webApp = New-AzureRmWebApp -Name $WebAppName -Location $rg.Location -AppServicePlan $WebAppName -ResourceGroupName $rg.ResourceGroupName

Write-Host "Web App Deployed: " + $webApp.DefaultHostName

$creds = Copy-FileToWebApp -WebAppName $WebAppName -ResourceGroupName $rg.ResourceGroupName -File .\index.html -Destination "/index.html"
