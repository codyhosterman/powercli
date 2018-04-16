<#
Optional parameters. Keep these values at default unless necessary and understood
For a different IO Operations limit beside the Pure Storage recommended value of 1, change $iopsvalue to another integer value 1-1000. 
To skip changing host-wide settings for XCOPY Transfer Size and In-Guest UNMAP change $hostwidesettings to $false
#>
$iopsvalue = 1

<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will:
-Set Disk.DiskMaxIOSize to 4 MB (if indicated)
-Check for a SATP rule for Pure Storage FlashArrays
-Create a SATP rule for Round Robin and IO Operations Limit of 1 only for FlashArrays
-Remove any incorrectly configured Pure Storage FlashArray rules
-Configure any existing devices properly (Pure Storage FlashArray devices only)
-Check all VMFS-6 volumes that automatic UNMAP is enabled

All change operations are logged to a file. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series, //m, and //x
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
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "setbestpractices.log"

write-host "Checking and setting Pure Storage FlashArray Best Practices for VMware on the ESXi hosts in this vCenter."
write-host ""

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
add-content $logfile 'Pure Storage FlashArray VMware ESXi Best Practices Script v 4.5 (APRIL-2018)'
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
    if ((!(Get-Module -Name VMware.VimAutomation.Core -ListAvailable -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable)))
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

write-host "The default behavior is to check and fix every host in vCenter."
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
$diskMaxIOSize = $false
write-host "If you are using vSphere Replication or intend to use UEFI boot for your VMs, Disk.DiskMaxIOSize must be set to 4096 KB from 32768."
$diskIOChoice = read-host "Would you like to make this host-wide change? (y/n)"

while (($diskIOChoice -ine "y") -and ($diskIOChoice -ine "n"))
{
    write-host "Invalid entry, please enter y or n"
    $diskIOChoice = read-host "Would you like to make this host-wide change? (y/n)"
}
if ($diskIOChoice -ieq "y")
{
    $diskMaxIOSize = $true
}
Write-Host ""
write-host "Script log information can be found at $logfile" -ForegroundColor green
Write-Host ""
write-host "Executing..."
add-content $logfile "Iterating through all ESXi hosts..."
$hosts | out-string | add-content $logfile

#Iterating through each host in the vCenter
foreach ($esx in $hosts) 
{
    $esxcli=get-esxcli -VMHost $esx -v2
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Working on the following ESXi host: $($esx.NetworkInfo.hostname)"
    add-content $logfile "-----------------------------------------------"
    if ($diskMaxIOSize -eq $true)
    {
        add-content $logfile "Checking Disk.DiskMaxIoSize setting."
        add-content $logfile "-------------------------------------------------------"
        $maxiosize = $esx |get-advancedsetting -Name Disk.DiskMaxIOSize
        if ($maxiosize.value -gt 4096)
        {
            add-content $logfile "The Disk.DiskMaxIOSize setting is set too high--currently set at $($maxiosize.value) KB "
            add-content $logfile "If your environment uses UEFI boot for VMs they will not boot unless this is set to 4096 (4 MB) or lower."
            add-content $logfile "https://docs.vmware.com/en/VMware-vSphere/6.5/com.vmware.vsphere.vm_admin.doc/GUID-898217D4-689D-4EB5-866C-888353FE241C.html"
            add-content $logfile "Setting to 4 MB..."
            $maxiosize |Set-AdvancedSetting -Value 4096 -Confirm:$false |out-null
        }
        else
        {
            add-content $logfile "Disk.DiskMaxIOSize is set properly."
        }
        add-content $logfile ""
        add-content $logfile "-------------------------------------------------------"
    }  
    #checking and setting FlashArray iSCSI targets for best practices (logintimeout of 30 seconds and delayedack to disabled)
    $targets = $esxcli.iscsi.adapter.target.portal.list.invoke()  | where-object {$_.Target -like "*purestorage*"}
    $iscsihba = $esx |Get-vmhosthba|where-object {$_.Model -eq "iSCSI Software Adapter"}
    $sendtgts = $iscsihba | Get-IScsiHbaTarget -type send
    add-content $logfile "Checking dynamic iSCSI targets that are FlashArray targets...Only ones that need to be fixed will be reported"
    foreach ($target in $targets)
    {
        foreach ($sendtgt in $sendtgts)
        {
            if ($target.IP -eq $sendtgt.Address)
            {
                $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.CreateArgs()
                $iscsiargs.adapter = $iscsihba.Device
                $iscsiargs.address = $target.IP
                $delayedAck = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "DelayedAck"}
                $loginTimeout = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "LoginTimeout"}
                if ($delayedAck.Current -eq "true")
                {
                    add-content $logfile "DelayedAck is not disabled on dynamic target $($target.target). Disabling... "
                    $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                    $iscsiargs.adapter = $iscsihba.Device
                    $iscsiargs.address = $target.IP
                    $iscsiargs.value = "false"
                    $iscsiargs.key = "DelayedAck"
                    $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
                }
                if ($loginTimeout.Current -ne "30")
                {
                    add-content $logfile "LoginTimeout is not set to 30 seconds on dynamic target $($target.target). It is set to $($loginTimeout.Current). Setting to 30... "
                    $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                    $iscsiargs.adapter = $iscsihba.Device
                    $iscsiargs.address = $target.IP
                    $iscsiargs.value = "30"
                    $iscsiargs.key = "LoginTimeout"
                    $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
                }
            }
        }
    } 
    add-content $logfile "Checking static iSCSI targets that are FlashArray targets...Only ones that need to be fixed will be reported"
    $statictgts = $iscsihba | Get-IScsiHbaTarget -type static
    foreach ($target in $targets)
    {
        foreach ($statictgt in $statictgts)
        {
            if ($target.IP -eq $statictgt.Address)
            {
                $iscsiargs = $esxcli.iscsi.adapter.target.portal.param.get.CreateArgs()
                $iscsiargs.adapter = $iscsihba.Device
                $iscsiargs.address = $target.IP
                $iscsiargs.name = $target.target
                $delayedAck = $esxcli.iscsi.adapter.target.portal.param.get.invoke($iscsiargs) |where-object {$_.name -eq "DelayedAck"}
                $loginTimeout = $esxcli.iscsi.adapter.target.portal.param.get.invoke($iscsiargs) |where-object {$_.name -eq "LoginTimeout"}
                if ($delayedAck.Current -eq "true")
                {
                    add-content $logfile "DelayedAck is not disabled on static target $($target.target). Disabling... "
                    $iscsiargs = $esxcli.iscsi.adapter.target.portal.param.set.CreateArgs()
                    $iscsiargs.adapter = $iscsihba.Device
                    $iscsiargs.address = $target.IP
                    $iscsiargs.name = $target.target
                    $iscsiargs.value = "false"
                    $iscsiargs.key = "DelayedAck"
                    $esxcli.iscsi.adapter.target.portal.param.set.invoke($iscsiargs) |out-null
                }
                if ($loginTimeout.Current -ne "30")
                {
                    add-content $logfile "LoginTimeout is not set to 30 seconds on static target $($target.target). It is set to $($loginTimeout.Current). Setting to 30... "
                    $iscsiargs = $esxcli.iscsi.adapter.target.portal.param.set.CreateArgs()
                    $iscsiargs.adapter = $iscsihba.Device
                    $iscsiargs.address = $target.IP
                    $iscsiargs.name = $target.target
                    $iscsiargs.value = "30"
                    $iscsiargs.key = "LoginTimeout"
                    $esxcli.iscsi.adapter.target.portal.param.set.invoke($iscsiargs) |out-null
                }
            }
        }
    } 
    #checking for correct multipathing SATP rules
    $rules = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
    $correctrule = 0
    $iopsoption = "iops=" + $iopsvalue
    if ($rules.Count -ge 1)
    {
        add-content $logfile "Found the following existing Pure Storage SATP rules"
        ($rules | out-string).TrimEnd() | add-content $logfile
        add-content $logfile "-----------------------------------------------"
        foreach ($rule in $rules)
        {
            add-content $logfile "-----------------------------------------------"
            add-content $logfile "Checking the following existing rule:"
            ($rule | out-string).TrimEnd() | add-content $logfile
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
            $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique 
            if ($lun.count -eq 1)
            {
                add-content $logfile ("The UUID for this volume is " + $datastore.ExtensionData.Info.Vmfs.Extent.DiskName)
                $esxcli=get-esxcli -VMHost $esx -v2
                if ($lun -like 'naa.624a9370*')
                {
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
                else 
                {
                    add-content $logfile "This is not a FlashArray datastore. Skipping."
                }
            }
        }
    }
}
 disconnect-viserver -Server $vcenter -confirm:$false
 add-content $logfile "Disconnected vCenter connection"