function Copy-FileToWebApp($ResourceGroupName, $WebAppName, $File, $Destination)
{

}

function Get-WebAppPublishingCredentials
{
    param(
        [Parameter(Mandatory)]
        [String]$ResourceGroupName,
                
        [Paramete(Mandatory)]
        [String]$WebAppName
    )
    
    $xml = [xml](Get-AzureRmWebAppPublishingProfile -Name $WebAppName -ResourceGroupName $ResourceGroupName -OutputFile null)

    $username = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value
    $password = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value
    $url = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value

    return @{
        "username" = $username
        "password" = $password
        "url" = $url
    }
}

