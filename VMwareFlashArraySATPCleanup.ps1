<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will:
-Looks for FlashArray SATP Rules of the Rule Group "system"
-Look for "user rules on those host for the FlashArray. If they are the same (model, vendor, PSP, PSP options) delete the user rule.

All change operations are logged to a file. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series and //m
-vCenter 5.5 and later
-PowerCLI 6.5 R1 or later required

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
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "satpcleanup.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green
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
add-content $logfile 'Pure Storage  FlashArray VMware ESXi SATP Cleanup Script v1.0'
add-content $logfile '----------------------------------------------------------------------------------------------------'


#Import PowerCLI. Requires PowerCLI version 6.3 or later. Will fail here if PowerCLI is not installed
#Will try to install PowerCLI with PowerShellGet if PowerCLI is not present.

if ((!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable))) {
    if (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
      . “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    elseif (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
        . “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    elseif (!(get-Module -Name VMware.PowerCLI -ListAvailable))
    {
        if (get-Module -name PowerShellGet -ListAvailable)
        {
            try
            {
                Get-PackageProvider -name NuGet -ListAvailable -ErrorAction stop
            }
            catch
            {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -Confirm:$false
            }
            Install-Module -Name VMware.PowerCLI –Scope CurrentUser -Confirm:$false -Force
        }
        else
        {
            write-host ("PowerCLI could not automatically be installed because PowerShellGet is not present. Please install PowerShellGet or PowerCLI") -BackgroundColor Red
            write-host "PowerShellGet can be found here https://www.microsoft.com/en-us/download/details.aspx?id=51451 or is included with PowerShell version 5"
            write-host "Terminating Script" -BackgroundColor Red
            return
        }
    }
    if ((!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable)))
    {
        write-host ("PowerCLI not found. Please verify installation and retry.") -BackgroundColor Red
        write-host "Terminating Script" -BackgroundColor Red
        return
    }
}
set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false  -confirm:$false|out-null
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
$deleteRules = Read-host "Delete unnecessary user rules? (if no, the script will just check for them) (y/n)"
while (($deleteRules -ine "y") -and ($deleteRules -ine "n"))
{
    write-host "Invalid entry, please enter y or n"
    $deleteRules = Read-host "Delete unnecessary user rules? (if no, the script will just check for them) (y/n)"
}
$hosts = Get-VMHost
foreach ($esx in $hosts) 
{
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Examining ESXi host $($esx.NetworkInfo.hostname)"
    $esxcli=get-esxcli -VMHost $esx -v2
    $rules = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
    $systemFound = $false
    foreach ($rule in $rules)
    {
        if ($rule.RuleGroup -eq "system")
        {
            add-content $logfile "Found a system rule for the FlashArray. Now looking for any user rules..."
            $systemFound = $true
            break
        }
    }
    if ($systemFound -eq $true)
    {
        $userFound = $false
        $userDeleted = 0
        $foundConflictingRule = $false
        $deleteError = $false
        foreach ($rule in $rules)
        {
            if ($rule.RuleGroup -eq "user")
            {
                add-content $logfile "Found a user rule for the FlashArray. Examining its configuration..."
                $userFound = $true
                if ($deleteRules -eq "y")
                {
                    if ($rule.PSPOptions -eq "iops=1")
                    {
                        add-content $logfile "NOTICE: Found a user rule that matches the system rule setting of an IO Operations Limit of 1. Deleting this rule... "
                        $satpArgs = $esxcli.storage.nmp.satp.rule.remove.createArgs()
                        $satpArgs.model = $rule.Model
                        $satpArgs.vendor = "PURE"
                        $satpArgs.satp = $rule.Name
                        $satpArgs.psp = $rule.DefaultPSP
                        $satpArgs.pspoption = $rule.PSPOptions
                        add-content $logfile "This rule is incorrect, deleting..."
                        try
                        {
                            $esxcli.storage.nmp.satp.rule.remove.invoke($satpArgs) |out-null
                            add-content $logfile "DELETED THE RULE."
                            $userDeleted++
                        }
                        catch
                        {
                            add-content $logfile "ERROR!!!: Could not delete this SATP Rule. Refer to the vmkernel log for details."
                            $deleteError =$true
                            continue
                        }
                    }
                    else
                    {
                        add-content $logfile "NOTICE: Found a FlashArray rule that differs from the system FlashArray rule setting of an IO Operations Limit of 1. Will not delete this rule."
                        add-content $logfile "This user rule is configured with $($rule.PSPoptions). Review and adjust if needed."
                        $foundConflictingRule = $true
                    }
                }
                else
                {
                    if ($rule.PSPOptions -eq "iops=1")
                    {
                        add-content $logfile "NOTICE: Found a FlashArray user rule that matches the system FlashArray rule setting of an IO Operations Limit of 1."
                        $userDeleted++
                    }
                    else
                    {
                        add-content $logfile "NOTICE: Found a rule that differs from the FlashArray system rule setting of an IO Operations Limit of 1."
                        add-content $logfile "This user rule is configured with $($rule.PSPoptions). Review and adjust if needed."
                        $foundConflictingRule = $true
                    }
                }
            
            }
        }
        if ($userFound -eq $false)
        {
            add-content $logfile "Found zero user rules for the FlashArray on this host"
        }
        elseif($userDeleted -gt 0)
        {
            if ($deleteRules -eq "y")
            {
                add-content $logfile "Deleted $($userDeleted) user rules for the FlashArray on this host"
            }
        }
        if ($foundConflictingRule -eq $true)
        {
            add-content $logfile "***WARNING***: This host has a conflicting FlashArray user rule that differs from the recommended system rule configuration. Verify this is expected."
        }
        elseif ($deleteError -eq $true)
        {
            add-content $logfile "***ERROR***: This host has an unnecessary FlashArray user rule but it could not be deleted!"
        }
        elseif (($deleteRules -eq "y") -and ($userDeleted -gt 0))
        {
            add-content $logfile "***SUCCESS***: Unnecessary FlashArray user rules have been removed and this host is now in a clean state!"
        }
        elseif (($deleteRules -eq "n") -and ($userDeleted -gt 0))
        {
            add-content $logfile "***WARNING***: This host has unnecessary FlashArray user rules!"
        }
        elseif ($userDeleted -eq 0)
        {
            add-content $logfile "***SUCCESS***: This host is in a clean state and no changes are required!"
        }

    }
    else
    {
        add-content $logfile "Did not find a FlashArray system rule. Skipping this host."
    }
}
add-content $logfile "-----------------------------------------------------------------------------------------------"
disconnect-viserver -Server $vcenter -confirm:$false
add-content $logfile "Disconnected vCenter connection"
write-host "Script complete. Refer to log for details."