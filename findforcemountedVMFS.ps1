Write-Host '             __________________________'
Write-Host '            /++++++++++++++++++++++++++\'           
Write-Host '           /++++++++++++++++++++++++++++\'           
Write-Host '          /++++++++++++++++++++++++++++++\'         
Write-Host '         /++++++++++++++++++++++++++++++++\'        
Write-Host '        /++++++++++++++++++++++++++++++++++\'       
Write-Host '       /++++++++++++/----------\++++++++++++\'     
Write-Host '      /++++++++++++/            \++++++++++++\'    
Write-Host '     /++++++++++++/              \++++++++++++\'   
Write-Host '    /++++++++++++/                \++++++++++++\'  
Write-Host '   /++++++++++++/                  \++++++++++++\' 
Write-Host '   \++++++++++++\                  /++++++++++++/' 
Write-Host '    \++++++++++++\                /++++++++++++/' 
Write-Host '     \++++++++++++\              /++++++++++++/'  
Write-Host '      \++++++++++++\            /++++++++++++/'    
Write-Host '       \++++++++++++\          /++++++++++++/'     
Write-Host '        \++++++++++++\'                   
Write-Host '         \++++++++++++\'                           
Write-Host '          \++++++++++++\'                          
Write-Host '           \++++++++++++\'                         
Write-Host '            \------------\'
Write-Host
Write-Host
Write-host 'Find ESXi Force Mounted VMFS Volumes Script v1.0'
write-host '----------------------------------------------'
write-host
#For info, refer to www.codyhosterman.com 

#Enter the following parameters. Put all entries inside the quotes.
#**********************************
$vcenter = ''
$vcuser = ''
$vcpass = ''
$logfolder = 'C:\folder\folder\etc\'
$forcemountlogfile = 'forcemount.txt'
$powercliversion = 6 #only change if your PowerCLI version is earlier than 6.0
#End of parameters

<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will identify any Force Mounted Volumes in your vCenter environment

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-PowerShell 3.0 or later
-PowerCLI 6.0 Release 1 or later recommended (5.5/5.8 is likely fine, but not tested with this script version)
-vCenter 5.5 and later
-Each FlashArray datastore must be present to at least one ESXi version 5.5 or later host or it will not be reclaimed
#>

#Create log folder if non-existent
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + $forcemountlogfile

add-content $logfile 'Looking for Force Mounted Volumes'
#Important PowerCLI if not done and connect to vCenter. Adds PowerCLI Snapin if 5.8 and earlier. For PowerCLI no import is needed since it is a module
$snapin = Get-PSSnapin -Name vmware.vimautomation.core -ErrorAction SilentlyContinue
if ($snapin.Name -eq $null )
{
    if ($powercliversion -ne 6) {Add-PsSnapin VMware.VimAutomation.Core} 
}
Set-PowerCLIConfiguration -invalidcertificateaction 'ignore' -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -confirm:$false |out-null
connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
add-content $logfile 'Connected to vCenter:'
add-content $logfile $vcenter
$datastores = Get-Datastore
foreach ($datastore in $datastores)
{
    if ($datastore.ExtensionData.Info.Vmfs.ForceMountedInfo.Mounted -eq "True")
    {
        add-content $logfile '----------------------------------------------------------------'
        add-content $logfile 'The following datastore is force-mounted:'
        add-content $logfile $datastore.Name
        add-content $logfile 'The datastore is force-mounted on the following ESXi hosts'
        $hosts = $datastore |get-vmhost
        add-content $logfile $hosts
    }
}
#disconnecting sessions
disconnect-viserver -Server $vcenter -confirm:$false