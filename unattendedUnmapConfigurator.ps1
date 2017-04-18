#For use with the Unattended UNMAP Script found here: https://github.com/codyhosterman/powercli/blob/master/unmapsdkunattended.ps1
<#*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************#>

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
write-host 'Pure Storage FlashArray VMware ESXi UNMAP Credential Configurator v1.0'
write-host '----------------------------------------------------------------------------------------------------'
write-host ''
write-host ''
write-host "Please choose a directory to store the encrypted credential files"
function ChooseFolder([string]$Message, [string]$InitialDirectory)
{
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, $Message, 0, $InitialDirectory)
    $selectedDirectory = $folder.Self.Path 
    return $selectedDirectory
}
try
{
    $credentialfolder = ChooseFolder -Message "Please select a credential file directory" -InitialDirectory 'MyComputer' 
    $fapath = join-path -path $credentialfolder -childpath "faUnmapCreds.xml"
    $Host.ui.PromptForCredential("Need FlashArray Credentials", "Please enter your FlashArray username and password.", "","") | Export-Clixml -Path $fapath
    $vcpath = join-path -path $credentialfolder -childpath "vcUnmapCreds.xml"
    $Host.ui.PromptForCredential("Need vCenter Credentials", "Please enter your vCenter username and password.", "","") | Export-Clixml -Path $vcpath
    write-host "Created credential files successfully"
}
catch
{
    write-host $Error[0]
}
