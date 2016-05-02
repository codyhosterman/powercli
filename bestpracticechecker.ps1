#Enter the following required parameters. Log folder directory is just and example, change as needed.
#Put all entries inside the quotes:
#**********************************
$vcenter = ''
$vcuser = ''
$vcpass = ''
$logfolder = "C:\folder\folder\etc\"
#**********************************

<#
Optional parameters. Keep these values at default unless necessary and understood
For a different IO Operations limit beside the Pure Storage recommended value of 1, change $iopsvalue to another integer value 1-1000. 
To skip changing host-wide settings for XCOPY Transfer Size and In-Guest UNMAP change $hostwidesettings to $false
For a different minimum path count, change from 4 to another integer. 1-32 (1 is HIGHLY discouraged)
#>
$iopsvalue = 1
$hostwidesettings = $true
$minpaths = 4


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
-Report correct and incorrect FlashArray rules
-Check for individual devices that are not configured properly

All information logged to a file. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series and //m
-vCenter 5.0 and later
-PowerCLI 6.3 R1 or later required


For info, refer to www.codyhosterman.com
#>

#Create log folder if non-existent
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ":", "."}) + "checkbestpractices.txt"
write-host "Checking Pure Storage FlashArray Best Practices for VMware on the ESXi hosts in this vCenter. "
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
add-content $logfile 'Pure Storage FlashArray VMware ESXi Best Practices Checker Script v3.0'
add-content $logfile '----------------------------------------------------------------------------------------------------'

if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
}
set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null

if ((Get-PowerCLIVersion).build -lt 3737840)
{
    write-host "This version of PowerCLI is too old, version 6.3 Release 1 or later is required (Build 3737840)" -BackgroundColor Red
    write-host "Found the following build number:"
    write-host (Get-PowerCLIVersion).build
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile "This version of PowerCLI is too old, version 6.3 Release 1 or later is required (Build 3737840)"
    add-content $logfile "Found the following build number:"
    add-content $logfile (Get-PowerCLIVersion).build
    add-content $logfile "Terminating Script"
    return
}

try
{
    connect-viserver -Server $vcenter -username $vcuser -password $vcpass -ErrorAction Stop |out-null
}
catch
{
    write-host "Failed to connect to vCenter" -BackgroundColor Red
    write-host $Error
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile "Failed to connect to vCenter"
    add-content $logfile $Error
    add-content $logfile "Terminating Script"
    return
}

write-host "No further information is printed to the screen."
add-content $logfile ('Connected to vCenter at ' + $vcenter)
add-content $logfile '----------------------------------------------------------------------------------------------------'

$hosts= get-vmhost

add-content $logfile "Iterating through all ESXi hosts..."
$hosts | out-string | add-content $logfile

#Iterating through each host in the vCenter
foreach ($esx in $hosts) 
{
    $esxcli=get-esxcli -VMHost $esx -v2
    add-content $logfile "***********************************************************************************************"
    add-content $logfile "**********************************NEXT ESXi HOST***********************************************"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Working on the following ESXi host:"
    add-content $logfile $esx.NetworkInfo.hostname
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    if ($hostwidesettings -eq $true)
    {
        add-content $logfile "Checking host-wide settings for VAAI and In-Guest UNMAP"
        add-content $logfile "-------------------------------------------------------"
        $xcopy = $esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedMove
        if ($xcopy.value -eq 0)
        {
            add-content $logfile "[****NEEDS ATTENTION****]The VAAI XCOPY (Full Copy) feature is not enabled on this host, it should be enabled."
        }
        else 
        {
            add-content $logfile "The VAAI XCOPY (Full Copy) feature is correctly enabled on this host."
        }
        $writesame = $esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedInit
        if ($writesame.value -eq 0)
        {
            add-content $logfile "[****NEEDS ATTENTION****]The VAAI WRITESAME (Block Zero) feature is not enabled on this host, it should be enabled."
        }
        else 
        {
            add-content $logfile "The VAAI WRITESAME (Block Zero) feature is correctly enabled on this host."
        }
        $atslocking = $esx | Get-AdvancedSetting -Name VMFS3.HardwareAcceleratedLocking
        if ($atslocking.value -eq 0)
        {
            add-content $logfile "[****NEEDS ATTENTION****]The VAAI ATOMIC TEST & SET (Assisted Locking) feature is not enabled on this host, it should be enabled."
        }
        else 
        {
            add-content $logfile "The VAAI ATOMIC TEST & SET (Assisted Locking) feature is correctly enabled on this host."
        }
        if ($esx.Build -ge 2068190)
        { 
            $atsheartbeat = $esx | Get-AdvancedSetting -Name VMFS3.useATSForHBOnVMFS5
            if ($atsheartbeat.value -eq 0)
            {
                add-content $logfile "[****NEEDS ATTENTION****]Datastore Heartbeating is not configured to use the VAAI ATOMIC TEST & SET (Assisted Locking) feature, it should be enabled."
            }
            else 
            {
                add-content $logfile "Datastore Heartbeating is correctly configured to use the VAAI ATOMIC TEST & SET (Assisted Locking) feature."
            }
        }
        $xfersize = $esx | Get-AdvancedSetting -Name DataMover.MaxHWTransferSize
        if ($xfersize.value -ne 16384)
        {
            add-content $logfile "[****NEEDS ATTENTION****]The VAAI XCOPY MaxHWTransferSize for this host is incorrect:"
            add-content $logfile $xfersize.value
            add-content $logfile "This should be set to 16386 (16 MB)."
        }
        else 
        {
            add-content $logfile "The VAAI XCOPY MaxHWTransferSize for this host is correct at 16 MB."
        }
        if ($esx.Version -like "6.0.*")
        { 
            $enableblockdelete = ($esx | Get-AdvancedSetting -Name VMFS3.EnableBlockDelete).Value
            if ($enableblockdelete.Value -eq 0)
            {
                add-content $logfile "[****NEEDS ATTENTION****]EnableBlockDelete is currently disabled but is recommended to be enabled."
            }
            else 
            {
                add-content $logfile "EnableBlockDelete for this host is correctly enabled."
            }
        }
        else
        {
            add-content $logfile "The current host is not version 6.0. Skipping EnableBlockDelete check as it is not applicable at this version."
        }
    }
    else
    {
        add-content $logfile "Not checking host wide settings for VAAI and In-Guest UNMAP due to in-script override"
    }
    add-content $logfile ""
    add-content $logfile ""
    add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
    add-content $logfile "Checking for FlashArray iSCSI targets and verifying their configuration on the host. Only misconfigured iSCSI targets will be reported."
    add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
    $iscsitofix = @()
    $flasharrayiSCSI = $false
    $targets = $esxcli.iscsi.adapter.target.portal.list.invoke()
    $iscsihba = $esx |Get-vmhosthba|where-object {$_.Model -eq "iSCSI Software Adapter"}
    $statictgts = $iscsihba | Get-IScsiHbaTarget -type static
    foreach ($target in $targets)
    {
        if ($target.Target -like "*purestorage*")
        {
            $flasharrayiSCSI = $true
            foreach ($statictgt in $statictgts)
            {
                if ($target.IP -eq $statictgt.Address)
                {
                    $iscsioptions = $statictgt.ExtensionData.AdvancedOptions
                    foreach ($iscsioption in $iscsioptions)
                    {
                        if ($iscsioption.key -eq "DelayedAck")
                        {
                            $iscsiack = $iscsioption.value
                        }
                        if ($iscsioption.key -eq "LoginTimeout")
                        {
                            $iscsitimeout = $iscsioption.value
                        }
                    }
                    if (($iscsiack -eq $true) -or ($iscsitimeout -ne 30))
                    {
                        if ($iscsiack -eq $true)
                        {
                            $iscsiack = "Enabled"
                        }
                        else
                        {
                            $iscsiack = "Disabled"
                        }
                        $iscsitgttofix = new-object psobject -Property @{
                            TargetIP = $target.IP
                            TargetIQN = $target.Target
                            DelayedAck = $iscsiack 
                            LoginTimeout  = $iscsitimeout
                            }
                        $iscsitofix += $iscsitgttofix
                    }
                }
            }
        }
    }
    if ($iscsitofix.count -ge 1)
    {
        add-content $logfile ("[****NEEDS ATTENTION****]A total of " + ($iscsitofix | select-object -unique).count + " FlashArray iSCSI targets have one or more errors.")
        add-content $logfile "Each target listed has an issue with at least one of the following configurations:"
        add-content $logfile ("  --The target does not have DelayedAck disabled")
        add-content $logfile ("  --The target does not have the iSCSI Login Timeout set to 30")
        $tableofiscsi = @(
                        'TargetIP'
                            @{Label = 'TargetIQN'; Expression = {$_.TargetIQN}; Alignment = 'Left'} 
                            @{Label = 'DelayedAck'; Expression = {$_.DelayedAck}; Alignment = 'Left'}
                            @{Label = 'LoginTimeout'; Expression = {$_.LoginTimeout}; Alignment = 'Left'}
                        )
        $iscsitofix | ft -property $tableofiscsi -autosize| out-string | add-content $logfile
    }
    else
    {
        add-content $logfile "No FlashArray iSCSI targets were found with configuration issues."
    }
    add-content $logfile ""
    add-content $logfile ""
    add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
    add-content $logfile "Checking for Software iSCSI Network Port Bindings."
    add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
    if ($flasharrayiSCSI -eq $true)
    {
        $iSCSInics = $esxcli.iscsi.networkportal.list.invoke()
        $goodnics = @()
        $badnics = @()
        if ($iSCSInics.Count -gt 0)
        {
            foreach ($iSCSInic in $iSCSInics)
            {
                if (($iSCSInic.CompliantStatus -eq "compliant") -and ($iSCSInic.PathStatus -eq "active"))
                {
                    $goodnics += $iSCSInic
                }
                else
                {
                    $badnics += $iSCSInic
                }
            }
        
            if ($goodnics.Count -lt 2)
            {
                add-content $logfile ("Found " + $goodnics.Count + " COMPLIANT AND ACTIVE NICs out of a total of " + $iSCSInics.Count + "NICs bound to this adapter")
                $nicstofix = @()
                add-content $logfile "[****NEEDS ATTENTION****]There are less than two COMPLIANT and ACTIVE NICs bound to the iSCSI software adapter. It is recommended to have two or more."
                if ($badnics.count -ge 1)
                {
                    foreach ($badnic in $badnics)
                    {
                        $nictofix = new-object psobject -Property @{
                                    vmkName = $badnic.Vmknic
                                    CompliantStatus = $badnic.CompliantStatus
                                    PathStatus = $badnic.PathStatus 
                                    vSwitch  = $badnic.Vswitch
                                    }
                        $nicstofix += $nictofix
                    }
                    $tableofbadnics = @(
                                    'vmkName'
                                        @{Label = 'ComplianceStatus'; Expression = {$_.CompliantStatus}; Alignment = 'Left'} 
                                        @{Label = 'PathStatus'; Expression = {$_.PathStatus}; Alignment = 'Left'}
                                        @{Label = 'vSwitch'; Expression = {$_.vSwitch}; Alignment = 'Left'}
                                    )
                    add-content $logfile "The following are NICs that are bound to the iSCSI Adapter but are either NON-COMPLIANT, INACTIVE or both"
                    $nicstofix | ft -property $tableofbadnics -autosize| out-string | add-content $logfile
                }
            }
            else 
            {
                add-content $logfile ("Found " + $goodnics.Count + " NICs that are bound to the iSCSI Adapter and are COMPLIANT and ACTIVE. No action needed.")
            }
        }
        else
        {
            add-content $logfile "[****NEEDS ATTENTION****]There are zero NICs bound to the software iSCSI adapter. This is strongly discouraged. Please bind two or more NICs"
        }
    }
    if ($flasharrayiSCSI -eq $false)
    {
        add-content $logfile "No FlashArray iSCSI targets found on this host"
    }
    add-content $logfile ""
    add-content $logfile ""
    add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
    add-content $logfile "Checking VMware NMP Multipathing configuration for FlashArray devices."
    add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
    $rules = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
    $correctrule = 0
    $iopsoption = "iops=" + $iopsvalue
    if ($rules.Count -ge 1)
    {
        add-content $logfile ("Found " + $rules.Count + " existing Pure Storage SATP rule(s)")
        foreach ($rule in $rules)
        {
            add-content $logfile "-----------------------------------------------"
            add-content $logfile "Checking the following existing rule:"
            $rule | out-string | add-content $logfile
            $issuecount = 0
            if ($rule.DefaultPSP -eq "VMW_PSP_RR") 
            {
                add-content $logfile "This Pure Storage FlashArray rule is configured with the correct Path Selection Policy."
            }
            else 
            {
                add-content $logfile "[****NEEDS ATTENTION****]This Pure Storage FlashArray rule is NOT configured with the correct Path Selection Policy:"
                add-content $logfile $rule.DefaultPSP
                add-content $logfile "The rule should be configured to Round Robin (VMW_PSP_RR)"
                $issuecount = 1
            }
            if ($rule.PSPOptions -eq $iopsoption) 
            {
                add-content $logfile "This Pure Storage FlashArray rule is configured with the correct IO Operations Limit."
            }
            else 
            {
                add-content $logfile "[****NEEDS ATTENTION****]This Pure Storage FlashArray rule is NOT configured with the correct IO Operations Limit:"
                add-content $logfile $rule.PSPOptions
                add-content $logfile "The rule should be configured to an IO Operations Limit of $iopsvalue"
                $issuecount = $issuecount + 1
            } 
            if ($rule.Model -eq "FlashArray") 
            {
                add-content $logfile "This Pure Storage FlashArray rule is configured with the correct model."
            }
            else 
            {
                add-content $logfile "[****NEEDS ATTENTION****]This Pure Storage FlashArray rule is NOT configured with the correct model:"
                add-content $logfile $rule.Model
                add-content $logfile "The rule should be configured with the model of FlashArray"
                $issuecount = $issuecount + 1
            } 
            if ($issuecount -ge 1)
            {
                add-content $logfile "[****NEEDS ATTENTION****]This rule is incorrect and should be removed."
                add-content $logfile "-----------------------------------------------"
            }
            else
            {
                add-content $logfile "This rule is correct."
                add-content $logfile "-----------------------------------------------"
                $correctrule = 1
            }
        }
    }
    if ($correctrule -eq 0)
    {  
        add-content $logfile "[****NEEDS ATTENTION****]No correct SATP rule for the Pure Storage FlashArray is found. You should create a new rule to set Round Robin and an IO Operations Limit of $iopsvalue"
    }
    else 
    {
        add-content $logfile "A correct SATP rule for the FlashArray exists. No need to create a new one on this host."
    }
    $devices = $esx |Get-ScsiLun -CanonicalName "naa.624a9370*"
    if ($devices.count -ge 1) 
    {
        add-content $logfile ""
        add-content $logfile ""
        add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
        add-content $logfile "Checking for existing Pure Storage FlashArray devices and their multipathing configuration."
        add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
        add-content $logfile ("Found " + $devices.count + " existing Pure Storage volumes on this host.")
        add-content $logfile "Checking their multipathing configuration now. Only listing devices with issues."
        add-content $logfile "Checking for Path Selection Policy, Path Count and IO Operations Limit"
        add-content $logfile ""
        $devstofix = @()
        foreach ($device in $devices)
        {
            $devpsp = $false
            $deviops = $false
            $devpaths = $false
            $devATS = $false
            $datastore = $null
            if ($device.MultipathPolicy -ne "RoundRobin")
            {
                $devpsp = $true
                $psp = $device.MultipathPolicy
                $psp = "$psp" + "*"
            }
            else
            {
                $psp = $device.MultipathPolicy
            }
            $deviceargs = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.createargs()
            $deviceargs.device = $device.CanonicalName
            if ($device.MultipathPolicy -eq "RoundRobin")
            {
                $deviceconfig = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.invoke($deviceargs)
                if ($deviceconfig.IOOperationLimit -ne $iopsvalue)
                {
                    $deviops = $true
                    $iops = $deviceconfig.IOOperationLimit
                    $iops = $iops + "*"
                }
                else
                {
                    $iops = $deviceconfig.IOOperationLimit
                }
            }
            if (($device |get-scsilunpath).count -lt $minpaths)
            {
                $devpaths = $true
                $paths = ($device |get-scsilunpath).count
                $paths = "$paths" + "*"
            }
            else
            {
                $paths = ($device |get-scsilunpath).count
            }
            $datastore = $esx |Get-Datastore |where-object { $_.ExtensionData.Info.Vmfs.Extent.DiskName -eq $device.CanonicalName }
            if ($datastore -ne $null)
            {
                $vmfsargs = $esxcli.storage.vmfs.lockmode.list.CreateArgs()
                $vmfsargs.volumelabel = $datastore.name
                $vmfsconfig = $esxcli.storage.vmfs.lockmode.list.invoke($vmfsargs)
                if ($vmfsconfig.LockingMode -ne "ATS")
                {
                    $devATS = $true
                    $ATS = $vmfsconfig.LockingMode
                    $ATS = $ATS + "*" 
                }
                else
                {
                    $ATS = $vmfsconfig.LockingMode
                }
            }
            if ($deviops -or $devpsp -or $devpaths -or $devATS)
            {
                 $devtofix = new-object psobject -Property @{
                    NAA = $device.CanonicalName
                    PSP = $psp 
                    IOPSValue  = if ($device.MultipathPolicy -eq "RoundRobin"){$iops}else {"N/A"}
                    PathCount  = $paths
                    ATSMode = if ($datastore -ne $null) {$ATS}else{"N/A"}
                   }
                $devstofix += $devtofix
            }
        }
        if ($devstofix.count -ge 1)
        {
            add-content $logfile ("[****NEEDS ATTENTION****]A total of " + $devstofix.count + " FlashArray devices have one or more errors.")
            add-content $logfile ""
            add-content $logfile "Each device listed has an issue with at least one of the following configurations:"
            add-content $logfile "  --Path Selection Policy is not set to Round Robin (VMW_PSP_RR)"
            add-content $logfile ("  --IO Operations Limit (IOPS) is not set to the recommended value (" + $iopsvalue + ")")
            add-content $logfile ("  --The device has less than the minimum recommended logical paths (" + $minpaths + ")")
            add-content $logfile ("  --The VMFS on this device does not have ATSonly mode enabled.")
            add-content $logfile ""
            add-content $logfile "Settings that need to be fixed are marked with an asterisk (*)"

            $tableofdevs = @(
                            'NAA' 
                                @{Label = 'PSP'; Expression = {$_.PSP}; Alignment = 'Left'}
                                @{Label = 'PathCount'; Expression = {$_.PathCount}; Alignment = 'Left'}
                                @{Label = 'IOPSValue'; Expression = {$_.IOPSValue}; Alignment = 'Left'}
                                @{Label = 'ATSMode'; Expression = {$_.ATSMode}; Alignment = 'Left'}
                            )
            $devstofix | ft -property $tableofdevs -autosize| out-string | add-content $logfile
        }
        else
        {
            add-content $logfile "No devices were found with configuration issues."
        }
    }
    else
    {
        add-content $logfile "No existing Pure Storage volumes found on this host."
    }
    add-content $logfile ""
    add-content $logfile "Done with the following ESXi host:"
    add-content $logfile $esx.NetworkInfo.hostname
    add-content $logfile "***********************************************************************************************"
    add-content $logfile "**********************************DONE WITH ESXi HOST******************************************"
    add-content $logfile "***********************************************************************************************"
    add-content $logfile ""
    add-content $logfile ""
}
 disconnect-viserver -Server $vcenter -confirm:$false
 add-content $logfile "Disconnected vCenter connection"
