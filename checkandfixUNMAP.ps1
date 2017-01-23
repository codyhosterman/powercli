<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will:
-Check and fix host setting EnableBlockDelete if not enabled
-Check and fix host setting EnableVMFS6Unmap if not enabled
-Check and fix datastore setting ReclaimPriority if not enabled

All change operations are logged to a file. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-vCenter 6.0 and later
-PowerCLI 6.3 R1 or later required

For info, refer to www.codyhosterman.com
#>
write-host "Please choose a directory to store the script log"
function ChooseFolder([string]$Message, [string]$InitialDirectory)
{
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, $Message, 0, $InitialDirectory)
    $selectedDirectory = $folder.Self.Path 
    return $selectedDirectory
}
$logfolder = ChooseFolder -Message "Please select a log file directory" -InitialDirectory 'MyComputer' 
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "configureunmap.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green

write-host "Checking and setting Automatic UNMAP Configuration for VMware on the ESXi hosts in this vCenter."
write-host "Script log information can be found at $logfile"

add-content $logfile '             __________________________'
add-content $logfile '            /++++++++++++++++++++++++++\'           
add-content $logfile '           /++++++++++++++++++++++++++++\'           
add-content $logfile '          /++++++++++++++++++++++++++++++\'         
add-content $logfile '         /++++++++++++++++++++++++++++++++\'        
add-content $logfile '        /++++++++++++++++++++++++++++++++++\'       
add-content $logfile '       /++++++++++++/----------\++++++++++++\'     
add-content $logfile '      /++++++++++++/            \++++++++++++\'    
add-content $logfile '     /++++++++++++/              \++++++++++++\'   
add-content $logfile '    /++++++++++++/                \++++++++++++\'  
add-content $logfile '   /++++++++++++/                  \++++++++++++\' 
add-content $logfile '   \++++++++++++\                  /++++++++++++/' 
add-content $logfile '    \++++++++++++\                /++++++++++++/' 
add-content $logfile '     \++++++++++++\              /++++++++++++/'  
add-content $logfile '      \++++++++++++\            /++++++++++++/'    
add-content $logfile '       \++++++++++++\          /++++++++++++/'     
add-content $logfile '        \++++++++++++\'                   
add-content $logfile '         \++++++++++++\'                           
add-content $logfile '          \++++++++++++\'                          
add-content $logfile '           \++++++++++++\'                         
add-content $logfile '            \------------\'
add-content $logfile 'VMware VMFS UNMAP Settings Script v1.0'
add-content $logfile '----------------------------------------------------------------------------------------------------'


if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
    if (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
      . “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    elseif (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
        . “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) 
    {
        write-host ("PowerCLI not found. Please verify installation and retry.") -BackgroundColor Red
        write-host "Terminating Script" -BackgroundColor Red
        add-content $logfile ("PowerCLI not found. Please verify installation and retry.")
        add-content $logfile "Terminating Script" 
        return
    }
        
}
set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
if ((Get-PowerCLIVersion).build -lt 3737840)
{
    write-host "This version of PowerCLI is too old, version 6.3 Release 1 or later is required (Build 3737840)" -BackgroundColor Red
    write-host "Found the following build number:"
    write-host (Get-PowerCLIVersion).build
    write-host "Terminating Script" -BackgroundColor Red
    write-host "Get it here: https://my.vmware.com/group/vmware/get-download?downloadGroup=PCLI630R1"
    add-content $logfile "This version of PowerCLI is too old, version 6.3 Release 1 or later is required (Build 3737840)"
    add-content $logfile "Found the following build number:"
    add-content $logfile (Get-PowerCLIVersion).build
    add-content $logfile "Terminating Script"
    add-content $logfile "Get it here: https://my.vmware.com/web/vmware/details?downloadGroup=PCLI650R1&productId=614"
    return
}
$vcenter = read-host "Please enter a vCenter IP or FQDN"
$Creds = $Host.ui.PromptForCredential("vCenter Credentials", "Please enter your vCenter username and password.", "","")
try
{
    connect-viserver -Server $vcenter -Credential $Creds -ErrorAction Stop |out-null
    add-content $logfile ('Connected to vCenter at ' + $vcenter)
    add-content $logfile '----------------------------------------------------------------------------------------------------'
}
catch
{
    write-host "Failed to connect to vCenter" -BackgroundColor Red
    write-host $vcenter
    write-host $Error[0]
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile "Failed to connect to vCenter"
    add-content $logfile $vcenter
    add-content $logfile $Error[0]
    add-content $logfile "Terminating Script"
    return
}
write-host ""
add-content $logfile '----------------------------------------------------------------------------------------------------'
$hosts= get-vmhost
add-content $logfile "Iterating through all ESXi hosts..."
#Iterating through each host in the vCenter
write-host "Checking hosts for host-wide UNMAP settings. Only listing hosts that need changed. Refer to the log for details."
foreach ($esx in $hosts) 
{
    add-content $logfile "--------------------------------------------------------------------------------------------------------"
    add-content $logfile "********************************************************************************************************"
    add-content $logfile "--------------------------------------------------------------------------------------------------------"
    add-content $logfile ("Examining the ESXi host named " + $esx.Name + " (" + $esx.ExtensionData.Config.Network.DnsConfig.HostName + '/' + $esx.ExtensionData.Config.Network.DnsConfig.Address + ")")
    if ($esx.Version -like "6.*")
    {
        add-content $logfile ""
        $enableblockdelete = $esx | Get-AdvancedSetting -Name VMFS3.EnableBlockDelete
        if ($enableblockdelete.Value -eq 0)
        {
            add-content $logfile "     EnableBlockDelete is currently disabled. Enabling..."
            $enableblockdelete |Set-AdvancedSetting -Value 1 -Confirm:$false |out-null
            add-content $logfile "     EnableBlockDelete has been set to enabled."
            write-host ("    FIXED: EnableBlockDelete is now enabled on " + $esx.Name + " (" + $esx.ExtensionData.Config.Network.DnsConfig.HostName + '/' + $esx.ExtensionData.Config.Network.DnsConfig.Address + ")")
        }
        else 
        {
            add-content $logfile "     EnableBlockDelete for this host is correctly enabled and will not be altered."
        }
        if ($esx.Version -like "6.5.*")
        {
            add-content $logfile "Current ESXi is version 6.5"
            $autounmap = $esx | Get-AdvancedSetting -Name VMFS3.EnableVMFS6Unmap
            if ($autounmap.Value -eq 0)
            {
                add-content $logfile "EnableVMFS6Unmap is currently disabled. Enabling..."
                $autounmap |Set-AdvancedSetting -Value 1 -Confirm:$false |out-null
                add-content $logfile "     EnableVMFS6Unmap has been set to enabled."
                write-host ("    FIXED: EnableVMFS6Unmap is now enabled on " + $esx.Name + " (" + $esx.ExtensionData.Config.Network.DnsConfig.HostName + '/' + $esx.ExtensionData.Config.Network.DnsConfig.Address + ")")
            }
            else 
            {
                add-content $logfile "     EnableVMFS6Unmap for this host is correctly enabled and will not be altered."
            }
        }
    }
    else
    {
        add-content $logfile "     The current host is not version 6.x. Skipping..."
    }
}
add-content $logfile "--------------------------------------------------------------------------------------------------------"
add-content $logfile "**********************Checking VMFS-6 datastores for Automatic UNMAP Setting...*************************"
add-content $logfile "--------------------------------------------------------------------------------------------------------"
write-host ""
write-host "Checking datastores for Automatic UNMAP setting. Only listing datastores that need changed. Refer to the log for details."
$datastores = get-datastore
foreach ($datastore in $datastores)
{
    if ($datastore.Type -eq 'VMFS')
    {
        if ($datastore.ExtensionData.info.vmfs.version -like "6.*")
        {
            $esx = $datastore | get-vmhost | where-object {($_.version -like '6.5.*')}| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1
            $esxcli=get-esxcli -VMHost $esx -v2
            add-content $logfile ""
            add-content $logfile ("The VMFS named " + $datastore.name + " is VMFS version six. Checking Automatic UNMAP configuration...")
            $unmapargs = $esxcli.storage.vmfs.reclaim.config.get.createargs()
            $unmapargs.volumelabel = $datastore.name
            $unmapresult = $esxcli.storage.vmfs.reclaim.config.get.invoke($unmapargs)
            if ($unmapresult.ReclaimPriority -ne "low")
            {
                add-content $logfile ("     Automatic Space Reclamation is not set to low. It is set to " + $unmapresult.ReclaimPriority)
                add-content $logfile "     Setting to low..."
                $unmapsetargs = $esxcli.storage.vmfs.reclaim.config.set.createargs()
                $unmapsetargs.volumelabel = $datastore.name
                $unmapsetargs.reclaimpriority = "low"
                $esxcli.storage.vmfs.reclaim.config.set.invoke($unmapsetargs) |Out-Null
                add-content $logfile ("Automatic UNMAP was enabled on " + $datastore.Name + " via ESXi host " + $esx.Name + " (" + $esx.ExtensionData.Config.Network.DnsConfig.HostName + '/' + $esx.ExtensionData.Config.Network.DnsConfig.Address + ")")
                write-host ("    FIXED: Automatic UNMAP is now enabled on datastore " + $datastore.Name)
            }
            elseif ($unmapresult.ReclaimPriority -eq "low")
            {
                add-content $logfile ("     Automatic Space Reclamation is correctly set to low.")
            }
        }
        else
        {
            add-content $logfile ("The VMFS named " + $datastore.name + " is not VMFS version 6. Skipping...")
        }
    }
    else
    {
        add-content $logfile ("The datastore named " + $datastore.name + " is not VMFS. Skipping...")
    }
}
 disconnect-viserver -Server $vcenter -confirm:$false
 add-content $logfile "Disconnected vCenter connection"