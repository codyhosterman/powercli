<#***************************************************************************************************
Requires only PowerShell 2.0 or later
***************************************************************************************************

For info, refer to www.codyhosterman.com

*****************************************************************
Enter the following parameters. 
Put all entries inside the quotes except $overwrite, that should be $true or $false
*****************************************************************#>
$flasharray = ""
$pureuser = ""
$purepass = ""
$overwrite = $false
$snapshot = ""
$pgrouptarget = ""
#*****************************************************************

<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will recover respective volumes in a FlashArray protection group from a specified snapshot

Supports:
-PowerShell 2.0 or later
-REST API 1.5 and later
-Purity 4.6 and later
-FlashArray 400 Series and //m
#>

write-host '             __________________________'
write-host '            /++++++++++++++++++++++++++\'           
write-host '           /++++++++++++++++++++++++++++\'           
write-host '          /++++++++++++++++++++++++++++++\'         
write-host '         /++++++++++++++++++++++++++++++++\'        
write-host '        /++++++++++++++++++++++++++++++++++\'       
write-host '       /++++++++++++/----------\++++++++++++\'     
write-host '      /++++++++++++/            \++++++++++++\'    
write-host '     /++++++++++++/              \++++++++++++\'   
write-host '    /++++++++++++/                \++++++++++++\'  
write-host '   /++++++++++++/                  \++++++++++++\' 
write-host '   \++++++++++++\                  /++++++++++++/' 
write-host '    \++++++++++++\                /++++++++++++/' 
write-host '     \++++++++++++\              /++++++++++++/'  
write-host '      \++++++++++++\            /++++++++++++/'    
write-host '       \++++++++++++\          /++++++++++++/'     
write-host '        \++++++++++++\'                   
write-host '         \++++++++++++\'                           
write-host '          \++++++++++++\'                          
write-host '           \++++++++++++\'                         
write-host '            \------------\'
write-host 'Pure Storage Protection Group Recovery v1.0'
write-host '----------------------------------------------------------------------------------------------------'

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$AuthAction = @{
    password = ${pureuser}
    username = ${purepass}
}
try
{
    write-host ("Connecting to the FlashArray at " + $flasharray +"...") 
    $ApiToken = Invoke-RestMethod -Method Post -Uri "https://$flasharray/api/1.5/auth/apitoken" -Body $AuthAction -ErrorAction stop
    $SessionAction = @{
        api_token = $ApiToken.api_token
    }
    Invoke-RestMethod -Method Post -Uri "https://${flasharray}/api/1.5/auth/session" -Body $SessionAction -SessionVariable Session -ErrorAction stop |out-null
    write-host "Connection successful!" -ForegroundColor Green
}
catch
{
    write-host
    write-host "Connection failed!" -backgroundColor Red
    write-host
    write-host $error[0] -ForegroundColor Red
    write-host
    return
}
$restbody = [ordered]@{
 source = $snapshot
 overwrite = $overwrite
 } | ConvertTo-Json
try
{
    write-host
    write-host ("Recovering the protection group " + $result.name + " from the specified Point-In-Time $snapshot...")
    $result = Invoke-RestMethod -Method Post -Uri "https://${flasharray}/api/1.5/pgroup/$pgrouptarget" -Body $restbody -WebSession $Session -ContentType "application/json" -ErrorAction stop
    write-host ("The protection group recovery on group " + $result.name + " succeeded from Point-In-Time $snapshot") -ForegroundColor Green
}
catch
{
    write-host
    write-host "Recovery failed!" -backgroundColor Red
    write-host
    write-host $error[0] -ForegroundColor Red
    write-host
}
Invoke-RestMethod -Method Delete -Uri "https://${flasharray}/api/1.5/auth/session" -WebSession $Session|out-null

 