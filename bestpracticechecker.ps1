<#
Optional parameters. Keep these values at default unless necessary and understood
For a different IO Operations limit beside the Pure Storage recommended value of 1, change $iopsvalue to another integer value 1-1000. 
To skip changing host-wide settings for XCOPY Transfer Size and In-Guest UNMAP change $hostwidesettings to $false
For a different minimum path count, change from 4 to another integer. 1-32 (1 is HIGHLY discouraged)
#>
$iopsvalue = 1
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
-FlashArray 400 Series, //m and //x
-vCenter 5.5 and later
-PowerCLI 6.3 R1 or later required


For info, refer to www.codyhosterman.com
#>

#Create log folder if non-existent
write-host ""
write-host "Please choose a directory to store the script log"
write-host ""
function ChooseFolder([string]$Message, [string]$InitialDirectory)
{
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, $Message, 0, $InitialDirectory)
    $selectedDirectory = $folder.Self.Path 
    return $selectedDirectory
}
$logfolder = ChooseFolder -Message "Please select a log file directory" -InitialDirectory 'MyComputer' 
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "checkbestpractices.log"

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
add-content $logfile 'Pure Storage FlashArray VMware ESXi Best Practices Checker Script v4.5 (APRIL-2018)'
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Import PowerCLI. Requires PowerCLI version 6.3 or later. Will fail here if PowerCLI cannot be installed
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
#connect to vCenter
$vcenter = read-host "Please enter a vCenter IP or FQDN"
$Creds = $Host.ui.PromptForCredential("vCenter Credentials", "Please enter your vCenter username and password.", "","")
try
{
    connect-viserver -Server $vcenter -Credential $Creds -ErrorAction Stop |out-null
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
write-host ""
write-host "Script result log can be found at $logfile" -ForegroundColor Green
write-host ""
add-content $logfile "Connected to vCenter at $($vcenter)"
add-content $logfile '----------------------------------------------------------------------------------------------------'

write-host "The default behavior is to check every host in vCenter."
$clusterChoice = read-host "Would you prefer to limit this to hosts in a specific cluster? (y/n)"

while (($clusterChoice -ine "y") -and ($clusterChoice -ine "n"))
{
    write-host "Invalid entry, please enter y or n"
    $clusterChoice = "Would you like to limit this check to a single cluster? (y/n)"
}
if ($clusterChoice -ieq "y")
{
    write-host "Please choose the cluster in the dialog box that popped-up." -ForegroundColor Yellow
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 

    #create form to choose recovery cluster
    $ClusterForm = New-Object System.Windows.Forms.Form
    $ClusterForm.width = 300
    $ClusterForm.height = 100
    $ClusterForm.Text = ”Choose a Cluster”

    $DropDown = new-object System.Windows.Forms.ComboBox
    $DropDown.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $DropDown.Location = new-object System.Drawing.Size(10,10)
    $DropDown.Size = new-object System.Drawing.Size(250,30)
    $clusters = get-cluster
    if ($clusters.count -lt 1)
    {
        add-content $logfile "Terminating Script. No VMware cluster(s) found."  
        write-host "No VMware cluster(s) found. Terminating Script" -BackgroundColor Red
        disconnectServers
        return
    }
    ForEach ($cluster in $clusters) {
        $DropDown.Items.Add($cluster.Name) |out-null
    }
    $ClusterForm.Controls.Add($DropDown)

    #okay button
    $OkClusterButton = new-object System.Windows.Forms.Button
    $OkClusterButton.Location = new-object System.Drawing.Size(60,40)
    $OkClusterButton.Size = new-object System.Drawing.Size(70,20)
    $OkClusterButton.Text = "OK"
    $OkClusterButton.Add_Click({
        $script:clusterName = $DropDown.SelectedItem.ToString()
        $ClusterForm.Close()
        })
    $ClusterForm.Controls.Add($OkClusterButton)

    #cancel button
    $CancelClusterButton = new-object System.Windows.Forms.Button
    $CancelClusterButton.Location = new-object System.Drawing.Size(150,40)
    $CancelClusterButton.Size = new-object System.Drawing.Size(70,20)
    $CancelClusterButton.Text = "Cancel"
    $CancelClusterButton.Add_Click({
        $script:endscript = $true
        $ClusterForm.Close()
        })
    $ClusterForm.Controls.Add($CancelClusterButton)
    $DropDown.SelectedIndex = 0
    $ClusterForm.Add_Shown({$ClusterForm.Activate()})
    [void] $ClusterForm.ShowDialog()

    add-content $logfile "Selected cluster is $($clusterName)"
    add-content $logfile ""
    $cluster = get-cluster -Name $clusterName
    $hosts= $cluster |get-vmhost
    write-host ""
}
else 
{
    write-host ""
    $hosts= get-vmhost
}

$errorHosts = @()
write-host "Executing..."
add-content $logfile "Iterating through all ESXi hosts..."
$hosts | out-string | add-content $logfile

#Iterating through each host in the vCenter
foreach ($esx in $hosts) 
{
    $esxError = $false
    $esxcli=get-esxcli -VMHost $esx -v2
    add-content $logfile "***********************************************************************************************"
    add-content $logfile "**********************************NEXT ESXi HOST***********************************************"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Working on the following ESXi host: $($esx.NetworkInfo.hostname), version $($esx.Version)"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Checking Disk.DiskMaxIoSize setting."
    add-content $logfile "-------------------------------------------------------"
    $maxiosize = $esx |get-advancedsetting -Name Disk.DiskMaxIOSize
    if ($maxiosize.value -gt 4096)
    {
        $esxError = $true
        add-content $logfile "[****NEEDS ATTENTION****]The Disk.DiskMaxIOSize setting is set too high--currently set at $($maxiosize.value) KB "
        add-content $logfile "If your environment uses UEFI boot for VMs they will not boot unless this is set to 4096 (4 MB) or lower."
        add-content $logfile "https://docs.vmware.com/en/VMware-vSphere/6.5/com.vmware.vsphere.vm_admin.doc/GUID-898217D4-689D-4EB5-866C-888353FE241C.html"
        add-content $logfile "This can be safely ignored if you only use BIOS boot for VMs"
    }
    else
    {
        add-content $logfile "Disk.DiskMaxIOSize is set properly."
    }
    add-content $logfile ""
    add-content $logfile "-------------------------------------------------------"
    add-content $logfile "Checking host-wide settings for VAAI."
    add-content $logfile "-------------------------------------------------------"
    $vaaiIssues = $false
    $xcopy = $esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedMove
    if ($xcopy.value -eq 0)
    {
        $esxError = $true
        add-content $logfile "[****NEEDS ATTENTION****]The VAAI XCOPY (Full Copy) feature is not enabled on this host, it should be enabled."
        $vaaiIssues = $true
    }
    $writesame = $esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedInit
    if ($writesame.value -eq 0)
    {
        $esxError = $true
        add-content $logfile "[****NEEDS ATTENTION****]The VAAI WRITESAME (Block Zero) feature is not enabled on this host, it should be enabled."
        $vaaiIssues = $true
    }
    $atslocking = $esx | Get-AdvancedSetting -Name VMFS3.HardwareAcceleratedLocking
    if ($atslocking.value -eq 0)
    {
        $esxError = $true
        add-content $logfile "[****NEEDS ATTENTION****]The VAAI ATOMIC TEST & SET (Assisted Locking) feature is not enabled on this host, it should be enabled."
        $vaaiIssues = $true
    }
    if (($datastore -ne $null) -and (($esx.version -like ("5.5.*")) -or ($esx.version -like ("6.*"))))
    { 
        $atsheartbeat = $esx | Get-AdvancedSetting -Name VMFS3.useATSForHBOnVMFS5
        if ($atsheartbeat.value -eq 0)
        {
            $esxError = $true
            add-content $logfile "[****NEEDS ATTENTION****]Datastore Heartbeating is not configured to use the VAAI ATOMIC TEST & SET (Assisted Locking) feature, it should be enabled."
            $vaaiIssues = $true
        }
    }
    if ($vaaiIssues -eq $false)
    {
        add-content $logfile "No issues with VAAI configuration found on this host"
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
        $esxError = $true
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
                if (($iSCSInic.CompliantStatus -eq "compliant") -and (($iSCSInic.PathStatus -eq "active") -or ($iSCSInic.PathStatus -eq "unused")))
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
                $esxError = $true
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
                    add-content $logfile "The following are NICs that are bound to the iSCSI Adapter but are either NON-COMPLIANT, INACTIVE or both. Or there is less than 2."
                    $nicstofix | Format-Table -property $tableofbadnics -autosize| out-string | add-content $logfile
                }
            }
            else 
            {
                add-content $logfile ("Found " + $goodnics.Count + " NICs that are bound to the iSCSI Adapter and are COMPLIANT and ACTIVE. No action needed.")
            }
        }
        else
        {
            $esxError = $true
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
        if ($rules.Count -gt 1)
        {
            $esxError = $true
            add-content $logfile "[****NEEDS ATTENTION****]There is more than one rule. The last rule found will be the one in use. Ensure this is intentional."
        }
        foreach ($rule in $rules)
        {
            add-content $logfile "-----------------------------------------------"
            add-content $logfile ""
            add-content $logfile "Checking the following existing rule:"
            ($rule | out-string).TrimEnd() | add-content $logfile
            add-content $logfile ""
            $issuecount = 0
            if ($rule.DefaultPSP -ne "VMW_PSP_RR") 
            {
                $esxError = $true
                add-content $logfile "[****NEEDS ATTENTION****]This Pure Storage FlashArray rule is NOT configured with the correct Path Selection Policy: $($rule.DefaultPSP)"
                add-content $logfile "The rule should be configured to Round Robin (VMW_PSP_RR)"
                $issuecount = 1
            }
            if ($rule.PSPOptions -ne $iopsoption) 
            {
                $esxError = $true
                add-content $logfile "[****NEEDS ATTENTION****]This Pure Storage FlashArray rule is NOT configured with the correct IO Operations Limit: $($rule.PSPOptions)"
                add-content $logfile "The rule should be configured to an IO Operations Limit of $($iopsvalue)"
                $issuecount = $issuecount + 1
            } 
            if ($rule.Model -ne "FlashArray") 
            {
                $esxError = $true
                add-content $logfile "[****NEEDS ATTENTION****]This Pure Storage FlashArray rule is NOT configured with the correct model: $($rule.Model)"
                add-content $logfile "The rule should be configured with the model of FlashArray"
                $issuecount = $issuecount + 1
            } 
            if ($issuecount -ge 1)
            {
                $esxError = $true
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
        $esxError = $true 
        add-content $logfile "[****NEEDS ATTENTION****]No correct SATP rule for the Pure Storage FlashArray is found. You should create a new rule to set Round Robin and an IO Operations Limit of $iopsvalue"
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
        add-content $logfile "Checking their configuration now. Only listing devices with issues."
        add-content $logfile "Checking for Path Selection Policy, Path Count, IO Operations Limit, and AutoUnmap Settings"
        add-content $logfile ""
        $devstofix = @()
        foreach ($device in $devices)
        {
            $devpsp = $false
            $deviops = $false
            $devpaths = $false
            $devATS = $false
            $datastore = $null
            $autoUnmap = $false
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
            if (($datastore -ne $null) -and ($esx.version -like ("6.*")))
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
                if ($datastore.ExtensionData.info.vmfs.version -like "6.*")
                {
                    $unmapargs = $esxcli.storage.vmfs.reclaim.config.get.createargs()
                    $unmapargs.volumelabel = $datastore.name
                    $unmapresult = $esxcli.storage.vmfs.reclaim.config.get.invoke($unmapargs)
                    if ($unmapresult.ReclaimPriority -ne "low")
                    {
                        $autoUnmap = $true
                        $autoUnmapPriority = "$($unmapresult.ReclaimPriority)*"
                    }
                    elseif ($unmapresult.ReclaimPriority -eq "low")
                    {
                        $autoUnmapPriority = "$($unmapresult.ReclaimPriority)"
                    }
                }
                else 
                {
                    
                }
            }
            if ($deviops -or $devpsp -or $devpaths -or $devATS -or $autoUnmap)
            {
                 $devtofix = new-object psobject -Property @{
                    NAA = $device.CanonicalName
                    PSP = $psp 
                    IOPSValue  = if ($device.MultipathPolicy -eq "RoundRobin"){$iops}else {"N/A"}
                    PathCount  = $paths
                    DatastoreName = if ($datastore -ne $null) {$datastore.Name}else{"N/A"}
                    VMFSVersion = if ($datastore -ne $null) {$datastore.ExtensionData.info.vmfs.version}else{"N/A"}
                    ATSMode = if (($datastore -ne $null) -and ($esx.version -like ("6.*"))) {$ATS}else{"N/A"}
                    AutoUNMAP = if (($datastore -ne $null) -and ($datastore.ExtensionData.info.vmfs.version -like "6.*")) {$autoUnmapPriority}else{"N/A"}
                   }
                $devstofix += $devtofix
            }
        }
        if ($devstofix.count -ge 1)
        {
            $esxError = $true
            add-content $logfile ("[****NEEDS ATTENTION****]A total of " + $devstofix.count + " FlashArray devices have one or more errors.")
            add-content $logfile ""
            add-content $logfile "Each device listed has an issue with at least one of the following configurations:"
            add-content $logfile "  --Path Selection Policy is not set to Round Robin (VMW_PSP_RR)"
            add-content $logfile ("  --IO Operations Limit (IOPS) is not set to the recommended value (" + $iopsvalue + ")")
            add-content $logfile ("  --The device has less than the minimum recommended logical paths (" + $minpaths + ")")
            add-content $logfile ("  --The VMFS on this device does not have ATSonly mode enabled.")
            add-content $logfile ("  --The VMFS-6 datastore on this device does not have Automatic UNMAP enabled. It should be set to low.")
            add-content $logfile ""
            add-content $logfile "Settings that need to be fixed are marked with an asterisk (*)"

            $tableofdevs = @(
                            'NAA' 
                                @{Label = 'PSP'; Expression = {$_.PSP}; Alignment = 'Left'}
                                @{Label = 'PathCount'; Expression = {$_.PathCount}; Alignment = 'Left'}
                                @{Label = 'IOPSValue'; Expression = {$_.IOPSValue}; Alignment = 'Left'}
                                @{Label = 'DatastoreName'; Expression = {$_.DatastoreName}; Alignment = 'Left'}
                                @{Label = 'VMFSVersion'; Expression = {$_.VMFSVersion}; Alignment = 'Left'}
                                @{Label = 'ATSMode'; Expression = {$_.ATSMode}; Alignment = 'Left'}
                                @{Label = 'AutoUNMAP'; Expression = {$_.AutoUNMAP}; Alignment = 'Left'}
                            )
            ($devstofix | Format-Table -property $tableofdevs -autosize| out-string).TrimEnd() | add-content $logfile
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
    add-content $logfile "Done with the following ESXi host: $($esx.NetworkInfo.hostname)"
    add-content $logfile "***********************************************************************************************"
    add-content $logfile "**********************************DONE WITH ESXi HOST******************************************"
    add-content $logfile "***********************************************************************************************"
    add-content $logfile ""
    if ($esxError -eq $true)
    {
        $errorHosts += $esx
    }
}
if ($errorHosts.count -gt 0)
{
    $tempText = Get-Content $logfile
    "The following hosts have errors. Search for ****NEEDS ATTENTION**** for details" |Out-File $logfile
    add-content $logfile $errorHosts
    add-content $logfile $tempText
    add-content $logfile ""
    add-content $logfile ""
}
 disconnect-viserver -Server $vcenter -confirm:$false
 add-content $logfile "Disconnected vCenter connection"
 write-host "Check complete."
 write-host ""
 if ($errorHosts.count -gt 0)
 {
    Write-Host "Errors on the following hosts were found:"
    write-host "==========================================="
    Write-Host $errorHosts
 }
 else 
 {
    write-host "No errors were found."    
 }
 write-host ""
 write-host "Refer to log file for detailed results." -ForegroundColor Green
 