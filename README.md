Ensuring HTTP Strict Transport Security (HSTS) on Legacy Systems
-----------------------------------------------------------------

On June 8, 2015, the White House Office of Management and Budget issued memorandum M-15-13, “A Policy to Require Secure Connections across Federal Websites and Web Services” [https.cio.gov](https://https.cio.gov). This policy requires that federal agencies make all existing websites and services accessible through a secure connection (HTTPS-only, with HTTP Strict Transport Security, HSTS) by December 31, 2016. Furthermore DHS published the [DHS Binding Operational Directive 18-01](https://cyber.dhs.gov/), which requires all public facing websites/domains in many federal agencies to be in compliance by January 17, 2018.

It is not enough to simply close off port 80 on relevant sites to make sure all traffic goes to port 443. Each response from the server must explicitly include the `Strict-Transport-Security` header. You can [read more about that on Wikipedia](https://en.wikipedia.org/wiki/HTTP_Strict_Transport_Security). This can be problematic for some systems that cannot easily be modified without breaking compliance in some other way or operating them in a configuration state that is not officially supported. One such example is [ADFS](https://en.wikipedia.org/wiki/Active_Directory_Federation_Services) systems, that may [need upgrading to be in complicance](https://docs.microsoft.com/en-us/windows-server/identity/ad-fs/overview/ad-fs-faq).

You can test if a specific system is in comlicance using [SSL Labs](https://www.ssllabs.com/).

If it is not possibly to modify the system itself, it is possible to mitigate the problem by front-ending the system with a proxy. This repository includes scripts that add an Azure Web App in front of the system and configures this web app to act as proxy. Since Web Apps currently enable TLS 1.0 (which is also a compliance violation), an Azure Application Gateway is added in front. 

Setting up a Test Environent
----------------------------

For testing purposes we will use a Azure Web App as the backend test system. You can create this Web App with the command:

```
 .\CreateHSTSTestEnvironment.ps1 -ResourceGroupName <RESOURCE GROUP NAME> -WebAppName <BACKENDAPPNAME> -Location <LOCATION> 
 ```

If you browse to the website `https://<BACKENDAPPNAME>.azurewebsites.net`, you should see a simple test page. Use [SSL Labs]([SSL Labs](https://www.ssllabs.com/)) to test that this site is in fact not in compliance. Look for "Strict Transport Security (HSTS)" on the results page. 

Applying the Fix
----------------

The complete fix (proxy web app and App Gateway) is configured using this PowerShell script

```
 .\ApplyHSTSFix.ps1 -ResourceGroupName <RESOURCE GROUP NAME> -ProxyWebAppName <FRONTENDAPPNAME> -Location <LOCATION> -Endpoint "<BACKENDAPPNAME>.azurewebsites.net" -CertificatePath "<PATH TO PFX FILE>"
 ```

 You will be prompted for a password for the certificate and then the solution should automatically run. It will take a while, since provisioning a gateway takes some time. 

 After the deployment, you should point the CNAME for your application to the DNS name of the public IP associated with the gateway. Now repeat the test and you should be in compliance for both HSTS and TLS.