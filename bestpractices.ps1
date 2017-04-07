<#
Optional parameters. Keep these values at default unless necessary and understood
For a different IO Operations limit beside the Pure Storage recommended value of 1, change $iopsvalue to another integer value 1-1000. 
To skip changing host-wide settings for XCOPY Transfer Size and In-Guest UNMAP change $hostwidesettings to $false
#>
$iopsvalue = 1
$hostwidesettings = $true

<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will:
-Check for a SATP rule for Pure Storage FlashArrays
-Create a SATP rule for Round Robin and IO Operations Limit of 1 only for FlashArrays
-Remove any incorrectly configured Pure Storage FlashArray rules
-Configure any existing devices properly (Pure Storage FlashArray devices only)
-Set VAAI XCOPY transfer size to 16MB
-Enable EnableBlockDelete on ESXi 6 hosts only
-Check all VMFS-6 volumes that automatic UNMAP is enabled

All change operations are logged to a file. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series and //m
-vCenter 5.5 and later
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
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "setbestpractices.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green

write-host "Checking and setting Pure Storage FlashArray Best Practices for VMware on the ESXi hosts in this vCenter."
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
add-content $logfile 'Pure Storage  FlashArray VMware ESXi Best Practices Script v4.0'
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
        add-content $logfile "Get it here: https://my.vmware.com/web/vmware/details?downloadGroup=PCLI650R1&productId=614"
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
foreach ($esx in $hosts) 
{
    $esxcli=get-esxcli -VMHost $esx -v2
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Working on the following ESXi host:"
    add-content $logfile $esx.NetworkInfo.hostname
    add-content $logfile "-----------------------------------------------"
    if ($hostwidesettings -eq $true)
    {
        add-content $logfile "Checking host-wide setting for XCOPY and In-Guest UNMAP"
        $xfersize = $esx | Get-AdvancedSetting -Name DataMover.MaxHWTransferSize
        if ($xfersize.value -ne 16384)
        {
            add-content $logfile "The VAAI XCOPY MaxHWTransferSize for this host is incorrect:"
            add-content $logfile $xfersize.value
            add-content $logfile "This should be set to 16386 (16 MB). Changing to 16384..."
            $xfersize |Set-AdvancedSetting -Value 16384 -Confirm:$false |out-null
            add-content $logfile "The VAAI XCOPY MaxHWTransferSize for this host is now 16 MB"
        }
        else 
        {
            add-content $logfile "The VAAI XCOPY MaxHWTransferSize for this host is correct at 16 MB and will not be altered."
        }
        if ($esx.Version -like "6.*")
        { 
            $enableblockdelete = $esx | Get-AdvancedSetting -Name VMFS3.EnableBlockDelete
            if ($enableblockdelete.Value -eq 0)
            {
                add-content $logfile "EnableBlockDelete is currently disabled. Enabling..."
                $enableblockdelete |Set-AdvancedSetting -Value 1 -Confirm:$false |out-null
                add-content $logfile "EnableBlockDelete has been set to enabled."
            }
            else 
            {
                add-content $logfile "EnableBlockDelete for this host is correctly enabled and will not be altered."
            }
        }
        else
        {
            add-content $logfile "The current host is not version 6.x. Skipping EnableBlockDelete check."
        }
    }
    else
    {
        add-content $logfile "Not checking host wide settings for XCOPY and In-Guest UNMAP due to in-script override"
    }
    add-content $logfile "-----------------------------------------------"
    $rules = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
    $correctrule = 0
    $iopsoption = "iops=" + $iopsvalue
    if ($rules.Count -ge 1)
    {
        add-content $logfile "Found the following existing Pure Storage SATP rules"
        $rules | out-string | add-content $logfile
        add-content $logfile "-----------------------------------------------"
        foreach ($rule in $rules)
        {
            add-content $logfile "-----------------------------------------------"
            add-content $logfile "Checking the following existing rule:"
            $rule | out-string | add-content $logfile
            $issuecount = 0
            if ($rule.DefaultPSP -eq "VMW_PSP_RR") 
            {
                add-content $logfile "The existing Pure Storage FlashArray rule is configured with the correct Path Selection Policy:"
                add-content $logfile $rule.DefaultPSP
            }
            else 
            {
                add-content $logfile "The existing Pure Storage FlashArray rule is NOT configured with the correct Path Selection Policy:"
                add-content $logfile $rule.DefaultPSP
                add-content $logfile "The rule should be configured to Round Robin (VMW_PSP_RR)"
                $issuecount = 1
            }
            if ($rule.PSPOptions -eq $iopsoption) 
            {
                add-content $logfile "The existing Pure Storage FlashArray rule is configured with the correct IO Operations Limit:"
                add-content $logfile $rule.PSPOptions
            }
            else 
            {
                add-content $logfile "The existing Pure Storage FlashArray rule is NOT configured with the correct IO Operations Limit:"
                add-content $logfile $rule.PSPOptions
                add-content $logfile "The rule should be configured to an IO Operations Limit of $iopsvalue"
                $issuecount = $issuecount + 1
            } 
            if ($rule.Model -eq "FlashArray") 
            {
                add-content $logfile "The existing Pure Storage FlashArray rule is configured with the correct model:"
                add-content $logfile $rule.Model
            }
            else 
            {
                add-content $logfile "The existing Pure Storage FlashArray rule is NOT configured with the correct model:"
                add-content $logfile $rule.Model
                add-content $logfile "The rule should be configured with the model of FlashArray"
                $issuecount = $issuecount + 1
            } 
            if ($issuecount -ge 1)
            {
                $satpArgs = $esxcli.storage.nmp.satp.rule.remove.createArgs()
                $satpArgs.model = $rule.Model
                $satpArgs.vendor = "PURE"
                $satpArgs.satp = $rule.Name
                $satpArgs.psp = $rule.DefaultPSP
                $satpArgs.pspoption = $rule.PSPOptions
                add-content $logfile "This rule is incorrect, deleting..."
                $esxcli.storage.nmp.satp.rule.remove.invoke($satpArgs)
                add-content $logfile "*****NOTE: Deleted the rule.*****"
                add-content $logfile "-----------------------------------------------"
            }
            else
            {
                add-content $logfile "This rule is correct"
                add-content $logfile "-----------------------------------------------"
                $correctrule = 1
            }
        }
    }
    if ($correctrule -eq 0)
    {  
        add-content $logfile "No correct SATP rule for the Pure Storage FlashArray is found. Creating a new rule to set Round Robin and an IO Operations Limit of $iopsvalue"
        $satpArgs = $esxcli.storage.nmp.satp.rule.remove.createArgs()
        $satpArgs.description = "Pure Storage FlashArray SATP Rule"
        $satpArgs.model = "FlashArray"
        $satpArgs.vendor = "PURE"
        $satpArgs.satp = "VMW_SATP_ALUA"
        $satpArgs.psp = "VMW_PSP_RR"
        $satpArgs.pspoption = $iopsoption
        $result = $esxcli.storage.nmp.satp.rule.add.invoke($satpArgs)
        if ($result -eq $true)
        {
            add-content $logfile "New rule created:"
            $newrule = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
            $newrule | out-string | add-content $logfile
        }
        else
        {
            add-content $logfile "ERROR: The rule failed to create. Manual intervention might be required."
        }
    }
    else 
    {
        add-content $logfile "A correct SATP rule for the FlashArray exists. No need to create a new one on this host."
    }
    $devices = $esx |Get-ScsiLun -CanonicalName "naa.624a9370*"
    add-content $logfile "-----------------------------------------------"
    if ($devices.count -ge 1) 
    {
        add-content $logfile "Looking for existing Pure Storage volumes on this host"
        add-content $logfile "Found the following number of existing Pure Storage volumes on this host."
        add-content $logfile $devices.count
        add-content $logfile "Checking and fixing their multipathing configuration now."
        add-content $logfile "-----------------------------------------------"
        foreach ($device in $devices)
        {
            add-content $logfile "Found and examining the following FlashArray device:" 
            add-content $logfile $device.CanonicalName
            if ($device.MultipathPolicy -ne "RoundRobin")
            {
                add-content $logfile "This device does not have the correct Path Selection Policy, it is set to:"
                add-content $logfile $device.MultipathPolicy
                add-content $logfile "Changing to Round Robin."
                Get-VMhost $esx |Get-ScsiLun $device |Set-ScsiLun -MultipathPolicy RoundRobin |out-null
            }
            else
            {
                add-content $logfile "This device's Path Selection Policy is correctly set to Round Robin. No need to change."
            }
            $deviceargs = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.createargs()
            $deviceargs.device = $device.CanonicalName
            $deviceconfig = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.invoke($deviceargs)
            $nmpargs =  $esxcli.storage.nmp.psp.roundrobin.deviceconfig.set.createargs()
            $nmpargs.iops = $iopsvalue
            $nmpargs.type = "iops"
            if ($deviceconfig.IOOperationLimit -ne $iopsvalue)
            {
                add-content $logfile "The current IO Operation limit for this device is:"
                add-content $logfile $deviceconfig.IOOperationLimit
                add-content $logfile "This device's IO Operation Limit is unset or is not set to the value of $iopsvalue. Changing..."
                $nmpargs.device = $device.CanonicalName
                $esxcli.storage.nmp.psp.roundrobin.deviceconfig.set.invoke($nmpargs) |out-null
            }
            else
            {
                add-content $logfile "This device's IO Operation Limit matches the value of $iopsvalue. No need to change."
            }
            add-content $logfile "-------------------"
        }
    }
    else
    {
        add-content $logfile "No existing Pure Storage volumes found on this host."
    }
    if ($esx.Version -like "6.5.*")
    {
        add-content $logfile "Current ESXi is version 6.5"
        add-content $logfile "Checking datastores for VMFS 6 Automatic UNMAP Setting"
        $datastores = $esx |get-datastore
        foreach ($datastore in $datastores)
        {
            add-content $logfile ""
            if ($datastore.ExtensionData.info.vmfs.version -like "6.*")
            {
                add-content $logfile ("The VMFS named " + $datastore.name + " is version six. Checking Automatic UNMAP configuration...")
                $unmapargs = $esxcli.storage.vmfs.reclaim.config.get.createargs()
                $unmapargs.volumelabel = $datastore.name
                $unmapresult = $esxcli.storage.vmfs.reclaim.config.get.invoke($unmapargs)
                if ($unmapresult.ReclaimPriority -ne "low")
                {
                    add-content $logfile ("Automatic Space Reclamation is not set to low. It is set to " + $unmapresult.ReclaimPriority)
                    add-content $logfile "Setting to low..."
                    $unmapsetargs = $esxcli.storage.vmfs.reclaim.config.set.createargs()
                    $unmapsetargs.volumelabel = $datastore.name
                    $unmapsetargs.reclaimpriority = "low"
                    $esxcli.storage.vmfs.reclaim.config.set.invoke($unmapsetargs)
                }
                elseif ($unmapresult.ReclaimPriority -eq "low")
                {
                    add-content $logfile ("Automatic Space Reclamation is correctly set to low.")
                }
            }
            else 
            {
                add-content $logfile ("The VMFS named " + $datastore.name + " is not version 6 so automatic UNMAP is not supported. Skipping.")
            }
        }
    }
}
 disconnect-viserver -Server $vcenter -confirm:$false
 add-content $logfile "Disconnected vCenter connection"