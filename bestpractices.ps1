Write-Host "             __________________________"
Write-Host "            /++++++++++++++++++++++++++\"           
Write-Host "           /++++++++++++++++++++++++++++\"           
Write-Host "          /++++++++++++++++++++++++++++++\"         
Write-Host "         /++++++++++++++++++++++++++++++++\"        
Write-Host "        /++++++++++++++++++++++++++++++++++\"       
Write-Host "       /++++++++++++/----------\++++++++++++\"     
Write-Host "      /++++++++++++/            \++++++++++++\"    
Write-Host "     /++++++++++++/              \++++++++++++\"   
Write-Host "    /++++++++++++/                \++++++++++++\"  
Write-Host "   /++++++++++++/                  \++++++++++++\" 
Write-Host "   \++++++++++++\                  /++++++++++++/" 
Write-Host "    \++++++++++++\                /++++++++++++/" 
Write-Host "     \++++++++++++\              /++++++++++++/"  
Write-Host "      \++++++++++++\            /++++++++++++/"    
Write-Host "       \++++++++++++\          /++++++++++++/"     
Write-Host "        \++++++++++++\"                   
Write-Host "         \++++++++++++\"                           
Write-Host "          \++++++++++++\"                          
Write-Host "           \++++++++++++\"                         
Write-Host "            \------------\"
Write-Host
Write-host "Pure Storage VMware Set Best Practices Script v2.0"
write-host "----------------------------------------------"
write-host

#Enter the following parameters. Put all entries inside the quotes:
#**********************************
$vcenter = ""
$vcuser = ""
$vcpass = ""
$logfolder = "C:\folder\folder\etc\"
#**********************************


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
-Fix a rule if an incorrect one is found
-If multiple rules are found it will skip. Manual fixing is needed
-Configure any existing devices properly (Pure Storage FlashArray devices only)
-Set VAAI XCOPY transfer size to 16MB
-Enable EnableBlockDelete on ESXi 6 hosts only

All change operations are logged to a file and also 
output to the screen. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series and //m
-vCenter 5.0 and later

#>

#Create log folder if non-existent
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ":", "."}) + "setbestpractices.txt"

#Important PowerCLI if not done and connect to vCenter
if ( (Get-PSSnapin -Name VMware.* -ErrorAction SilentlyContinue) -eq $null )
{
    Add-PsSnapin VMware.VimAutomation.Core
}
set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
add-content $logfile "Connected to vCenter:"
add-content $logfile $vcenter
add-content $logfile "-------------------------"

$hosts= get-cluster |get-vmhost
$iops = 1 
$iopsnumber=$iops
$iops = "iops=" + $iops  

write-host "Iterating through all ESXi hosts..."
write-host 

#Iterating through each host in the vCenter
foreach ($esx in $hosts) 
 {
    $esxcli=get-esxcli -VMHost $esx
    add-content $logfile "-----------------------------------------------"
    add-content $logfile "-----------------------------------------------"
    add-content $logfile "Working on the following ESXi host:"
    add-content $logfile $esx.NetworkInfo.hostname
    write-host
    write-host
    write-host "==================================================================================="
    write-host "******************************Next ESXi host***************************************"
    write-host "==================================================================================="
    write-host "Working on the following ESXi host:"
    write-host $esx.NetworkInfo.HostName
    write-host 
    write-host "----------------------------------------------------------------------------------" 
    write-host "Checking the VMware VAAI XCOPY Transfer size setting (recommended size is 16 MB)"
    write-host 
    $xfersize = $esx | Get-AdvancedSetting -Name DataMover.MaxHWTransferSize
    write-host "The transfer size is currently set to " ($xfersize.value/1024) "MB."
    if ($xfersize.value -ne 16384)
        {
            write-host "The transfer size is set to an amount that differs from best practices. Changing setting to 16 MB..."
            $xfersize |Set-AdvancedSetting -Value 16384 -Confirm:$false |out-null
            write-host "XCOPY transfer size is now 16 MB."
            write-host 
            add-content $logfile "The transfer size for this host is now 16 MB"
        }
    else 
        {
            write-host "The XCOPY transfer size is set correctly and will not be altered."
            write-host 
            add-content $logfile "The transfer size for this host is correct at 16 MB and will not be altered"
        }
    write-host "----------------------------------------------------------------------------------" 
    write-host 
    write-host "----------------------------------------------------------------------------------" 
    write-host "Checking that the vSphere 6.0 In-Guest UNMAP setting EnableBlockDelete is enabled"
    write-host
    if ($esx.Version -like "6.0.*")
    { 
        $enableblockdelete = $esx | Get-AdvancedSetting -Name VMFS3.EnableBlockDelete
        if ($enableblockdelete.value -eq 1)
        {
            $ebdboolean = "enabled"
        }
        else
        {
            $ebdboolean = "disabled"
        }

        write-host "EnableBlockDelete is currently set to" $ebdboolean
        if ($enableblockdelete.value -ne 1)
            {
                write-host "Changing setting to enabled..."
                $enableblockdelete |Set-AdvancedSetting -Value 1 -Confirm:$false |out-null
                write-host "EnableBlockDelete is now enabled."
                write-host 
                add-content $logfile "EnableBlockDelete has been set to enabled."
            }
        else 
            {
                write-host "No change to EnableBlockDelete is necessary."
                write-host 
                add-content $logfile "No change to EnableBlockDelete is necessary."
            }
    }
    else
    {
        write-host "The current host is not version 6.0. Skipping EnableBlockDelete check."
        add-content $logfile "The current host is not version 6.0. Skipping EnableBlockDelete check."
    }
    write-host "----------------------------------------------------------------------------------" 
    write-host 
    write-host "Looking for Storage Array Type Plugin (SATP) rules for Pure Storage FlashArray devices..."
    $rule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
    if ($rule.Count -eq 1) 
        {
            write-host "An existing SATP rule for the Pure Storage FlashArray has been found."
            write-host 
            $issuecount = 0
            if ($rule.DefaultPSP -eq "VMW_PSP_RR") 
                {
                    write-host "The existing Pure/FlashArray rule is configured with the correct Path Selection Policy (Round Robin)"
                    add-content $logfile "The existing Pure/FlashArray rule is configured with the correct Path Selection Policy (Round Robin)"
                }
            else 
                {
                    write-host "The existing Pure/FlashArray rule is NOT configured with the correct Path Selection Policy"
                    write-host "The existing rule should be configured to Round Robin"
                    add-content $logfile "The existing Pure/FlashArray rule is NOT configured with the correct Path Selection Policy"
                    add-content $logfile "The existing rule should be configured to Round Robin"
                    $issuecount = 1
                }
            if ($rule.PSPOptions -like "*$iops*") 
                {
                    write-host "The existing Pure/FlashArray rule is configured with the correct IO Operations Limit"
                    add-content $logfile "The existing Pure/FlashArray rule is configured with the correct IO Operations Limit"
                }
            else 
                {
                    write-host "The existing Pure/FlashArray rule is NOT configured with the proper IO Operations Limit (should be 1)"
                    write-host "The current rule has the following PSP options:"
                    write-host $rule.PSPOptions
                    add-content $logfile "The existing Pure/FlashArray rule is NOT configured with the as-entered IO Operations Limit (should be 1)"
                    add-content $logfile "The current rule has the following PSP options:"
                    add-content $logfile $rule.PSPOptions
                    $issuecount = $issuecount + 1
                    write-host 
                } 
            if ($issuecount -ge 1)
                {

                    $esxcli.storage.nmp.satp.rule.remove($null, $null, $rule.Description, $null, $null, $rule.Model, $null, $rule.DefaultPSP, $rule.PSPOptions, "VMW_SATP_ALUA", $null, $null, "PURE") |Out-Null
                    write-host "Rule deleted."
                    $esxcli.storage.nmp.satp.rule.add($null, $null, "PURE FlashArray IO Operation Limit Rule", $null, $null, $null, "FlashArray", $null, "VMW_PSP_RR", $iops, "VMW_SATP_ALUA", $null, $null, "PURE") |out-null
                    write-host "New rule created:"
                    add-content $logfile "New rule created:"
                    $newrule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
                    $newrule
                    $newrule | out-file tempfile.file
                    $temprule = get-content tempfile.file
                    rm tempfile.file
                    add-content $logfile $temprule
                 }
        }
            elseif ($rule.Count -ge 2)
                {
                    write-host "-------------------------------------------------------------------------------------------------------------------------------------------"
                    write-host "***NOTICE***: Multiple Pure Storage rules or multiple errors in one rule have been found and this will require manual cleanup."
                    write-host
                    write-host "Please examine your rules and delete unnecessary ones. No rule will be created. Doing per-volume check only."
                    write-host "-------------------------------------------------------------------------------------------------------------------------------------------" 
                    add-content $logfile "***NOTICE***: Multiple Pure Storage rules or multiple errors in one rule have been found and this will require manual cleanup."
                    add-content $logfile "Please examine your rules and delete unnecessary ones. No rule will be created. Doing per-volume check only."
                }
            else
                {  
                    write-host "No default SATP rule for the Pure Storage FlashArray found. Creating a new rule to set Round Robin and a IO Operation Limit of" $iops 
                    add-content $logfile "No default SATP rule for the Pure Storage FlashArray found. Creating a new rule to set Round Robin and the entered IO Operations Limit"
                    $esxcli.storage.nmp.satp.rule.add($null, $null, "PURE FlashArray IO Operation Limit Rule", $null, $null, $null, "FlashArray", $null, "VMW_PSP_RR", $iops, "VMW_SATP_ALUA", $null, $null, "PURE") |out-null
                    write-host "New rule created:"
                    add-content $logfile "New rule created:"
                    $newrule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
                    $newrule
                    $newrule | out-file tempfile.file
                    $temprule = get-content tempfile.file
                    rm tempfile.file
                    add-content $logfile $temprule
 }
                write-host "----------------------------------------------------------------------------------" 
                
                $devices = $esx |Get-ScsiLun -CanonicalName "naa.624a9370*"
                if ($devices.count -ge 1) 
                   {
                        write-host
                        write-host "Looking for existing Pure Storage volumes on this host"
                        add-content $logfile "Looking for existing Pure Storage volumes on this host"
                        write-host "Found " $devices.count " existing Pure Storage volumes on this host. Checking and fixing their multipathing configuration now."
                        add-content $logfile "Found the following number of existing Pure Storage volumes on this host. Checking and fixing their multipathing configuration now."
                        add-content $logfile $devices.count
                        foreach ($device in $devices)
                           {
                               write-host
                               write-host "----------------------------------"
                               write-host "Checking device " $device "..."
                               write-host
                               if ($device.MultipathPolicy -ne "RoundRobin")
                                    {
                                       write-host "This device does not have the correct Path Selection Policy. Setting to Round Robin..."
                                       add-content $logfile "This device does not have the correct Path Selection Policy. Setting to Round Robin..."
                                       add-content $logfile $device.CanonicalName
                                       Get-VMhost $esx |Get-ScsiLun $device |Set-ScsiLun -MultipathPolicy RoundRobin 
                                    }
                               else
                                    {
                                       write-host "This device's Path Selection Policy is correctly set to Round Robin already. No need to change."
                                    }
                               $deviceconfig = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get($device)
                               if ($deviceconfig.IOOperationLimit -ne $iopsnumber)
                                    {
                                        write-host "This device's IO Operation Limit is not set to the entered value."
                                        write-host "The IO Operation Limit for this device is currently set to " $deviceconfig.IOOperationLimit " Setting it to " $iopsnumber " now..."
                                        add-content $logfile $device.CanonicalName
                                        add-content $logfile "This device's IO Operation Limit is not set to the entered value. Changing..."
                                        $esxcli.storage.nmp.psp.roundrobin.deviceconfig.set($null,$null,$device.CanonicalName,$iopsnumber,”iops”,$null) |out-null
                                    }
                               else
                                    {
                                        write-host "This device's IO Operation Limit matches the value entered. No need to change."
                                    }
                            }
                 }
              else
                  {
                      write-host "No existing Pure Storage volumes found on this host."
                      add-content $logfile "No existing Pure Storage volumes found on this host."
                  }
     }
 disconnect-viserver -Server $vcenter -confirm:$false