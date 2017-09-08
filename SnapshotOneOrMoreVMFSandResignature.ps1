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
Write-host "Pure Storage FlashArray and VMware VMFS Copy Script Script 1.0"
write-host "----------------------------------------------"
write-host
<#

Written by Cody Hosterman www.codyhosterman.com

*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script connects to a FlashArray and a vCenter and asks for a log location. It then asks for you to select VMFS volumes (filtered by ones only on that FlashArray
and optionally a snapshot name suffix. It then creates a snapshot of all of those VMFS volumes and then connects it to a VMware cluster and then rescans the hosts.
It will then resignature the volume(s). 


Requires:
-Pure Storage PowerShell SDK 1.8+
-VMware PowerCLI 6.3+
-Microsoft PowerShell 5+ is highly recommend, but can be used with older versions (3+)
-FlashArray Purity 4.7+
-vCenter 5.5+
#>
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "This script has not been run as an administrator."
    Write-Warning "Please re-run this script as an administrator!"
    write-host "Terminating Script" -BackgroundColor Red
    return
}
write-host "Please choose a directory to store the script log"
function ChooseFolder([string]$Message, [string]$InitialDirectory)
{
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, $Message, 0, $InitialDirectory)
    $selectedDirectory = $folder.Self.Path 
    return $selectedDirectory
}
$logfolder = ChooseFolder -Message "Please select a log file directory" -InitialDirectory 'MyComputer' 
If (!($logfolder))
{ 
    Write-Host 'No log folder selected. Terminating script.' -BackgroundColor Red 
    add-content $logfile 'No log folder selected. Terminating script.' 
    return
}
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "snapshotresults.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green
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

if (!(Get-Module -Name PureStoragePowerShellSDK -ErrorAction SilentlyContinue)) {
    if ( !(Get-Module -ListAvailable -Name PureStoragePowerShellSDK -ErrorAction SilentlyContinue) )
    {
        if (get-Module -name PowerShellGet -ListAvailable)
        {
            try
            {
                Get-PackageProvider -name NuGet -ListAvailable -ErrorAction stop |Out-Null
            }
            catch
            {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -Confirm:$false |Out-Null
            }
            try
            {
                Install-Module -Name PureStoragePowerShellSDK –Scope CurrentUser -Confirm:$false -Force
            }
            catch
            {
                write-host "Pure Storage PowerShell SDK cannot be installed. Please refer to the log file for details."
                add-content $logfile "Pure Storage PowerShell SDK cannot be installed."
                add-content $logfile $error[0]
            }
        }
        else
        {
            write-host ("Pure Storage PowerShell SDK could not automatically be installed because PowerShellGet is not present. Please manually install PowerShellGet or the Pure Storage PowerShell SDK") -BackgroundColor Red
            write-host "PowerShellGet can be found here https://www.microsoft.com/en-us/download/details.aspx?id=51451 or is included with PowerShell version 5"
            write-host "Pure Storage PowerShell SDK can be found here https://github.com/PureStorage-Connect/PowerShellSDK"
            add-content $logfile ("FlashArray PowerShell SDK not found. Please verify installation and retry.")
            add-content $logfile "Get it here: https://github.com/PureStorage-Connect/PowerShellSDK"
            add-content $logfile "Terminating Script" 
            write-host "Terminating Script" -BackgroundColor Red
            return
        }
    }
    if (!(Get-Module -Name PureStoragePowerShellSDK -ListAvailable -ErrorAction SilentlyContinue))
    {
        write-host ("Pure Storage PowerShell SDK not found. Please verify installation and retry.") -BackgroundColor Red
        write-host "Pure Storage PowerShell SDK can be found here https://github.com/PureStorage-Connect/PowerShellSDK"
        add-content $logfile ("FlashArray PowerShell SDK not found. Please verify installation and retry.")
        add-content $logfile "Get it here: https://github.com/PureStorage-Connect/PowerShellSDK"
        add-content $logfile "Terminating Script" 
        write-host "Terminating Script" -BackgroundColor Red
        return
    }
}
function disconnectServers{
    disconnect-viserver -Server $vcenter -confirm:$false
    Disconnect-PfaArray -Array $endpoint 
    add-content $logfile "Disconnected vCenter and FlashArray"
}
function cleanUp{
    add-content $logfile "Deleting any successfully created snapshots and volumes"
    foreach ($snapshot in $snapshots)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated snapshot $($snapshot.name)"
    }
    foreach ($hgroupConnection in $hgroupConnections)
    {
        Remove-PfaHostGroupVolumeConnection -Array $EndPoint -VolumeName $hgroupConnection.vol -HostGroupName $hostgroup -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Disconnected volume $($hgroupConnection.vol) from host group $($hostgroup)"
    }
    foreach ($newVol in $newVols)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated volume $($newVol.name)"
    }
    $hosts = $cluster |Get-VMHost
    foreach ($esxi in $hosts) 
    {
            $argList = @($vcenter, $Creds, $esxi)
            $job = Start-Job -ScriptBlock{ 
                Connect-VIServer -Server $args[0] -Credential $args[1]
                Get-VMHost -Name $args[2] | Get-VMHostStorage -RescanAllHba -RescanVMFS
                Disconnect-VIServer -Confirm:$false
            } -ArgumentList $argList
    }
    Get-Job | Wait-Job -Timeout 120|out-null
    return
}
write-host ""
$flasharray = read-host "Please enter a FlashArray IP or FQDN"
$Creds = $Host.ui.PromptForCredential("FlashArray Credentials", "Please enter your FlashArray username and password.", "$env:userdomain\$env:username","")
#Connect to FlashArray via REST with the SDK
try
{
    add-content $logfile "Connecting with username $($creds.username)"
    $EndPoint = New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError -ErrorAction stop
}
catch
{
    add-content $logfile ""
    add-content $logfile "Connection to FlashArray $($flasharray) failed."
    add-content $logfile $Error[0]
    add-content $logfile "Terminating Script"  
    write-host "Connection to FlashArray $($flasharray) failed. Please check log for details"
    write-host "Terminating Script" -BackgroundColor Red
    return
}
add-content $logfile 'Connected to the following FlashArray:'
add-content $logfile $flasharray
add-content $logfile '----------------------------------------------------------------------------------------------------'
$vcenter = read-host "Please enter a vCenter IP or FQDN"
$options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No", "&Quit")
[int]$defaultchoice = 1
$opt = $host.UI.PromptForChoice("vCenter Credentials" , "Use the same credentials as the FlashArray?" , $Options,$defaultchoice)
if ($opt -eq 2)
{
    return
}
elseif ($opt -eq 1)
{
    $Creds = $Host.ui.PromptForCredential("vCenter Credentials", "Please enter your vCenter username and password.", "$env:userdomain\$env:username","")
}
try
{
    add-content $logfile "Connecting with username $($creds.username)"
    connect-viserver -Server $vcenter -Credential $Creds -ErrorAction Stop |out-null
    add-content $logfile ('Connected to the following vCenter:')
    add-content $logfile $vcenter
    add-content $logfile '----------------------------------------------------------------------------------------------------'
}
catch
{
    write-host "Failed to connect to vCenter. Refer to log for details." -BackgroundColor Red
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile "Failed to connect to vCenter"
    add-content $logfile $vcenter
    add-content $logfile $Error[0]
    add-content $logfile "Terminating Script"
    Disconnect-PfaArray -Array $EndPoint
    return
}
write-host ""
#find VMFS datastores that are on the entered FlashArray. Create GUI entry form
$x = @()

[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 

$objForm = New-Object System.Windows.Forms.Form 
$objForm.Text = "Choose FlashArray Volumes"
$objForm.Size = New-Object System.Drawing.Size(600,320) 
$objForm.StartPosition = "CenterScreen"
$objForm.KeyPreview = $True
$objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
    {
        foreach ($objItem in $objListbox.SelectedItems)
            {$x += $objItem}
        $objForm.Close()
    }
    })
$objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
    {$objForm.Close()}})


#define OK button
$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location = New-Object System.Drawing.Size(400,250)
$OKButton.Size = New-Object System.Drawing.Size(75,23)
$OKButton.Text = "OK"
$OKButton.Enabled = $false
$OKButton.Add_Click(
{
    $script:selectedVolumes = $SelectListbox.Items
    $script:snapshotNameSuffix = $snapshotSuffix.Text
    $objForm.Close()
})
$objForm.Controls.Add($OKButton)
$script:endscript = $false
#define cancel button
$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Location = New-Object System.Drawing.Size(490,250)
$CancelButton.Size = New-Object System.Drawing.Size(75,23)
$CancelButton.Text = "Cancel"
$CancelButton.Add_Click({
    $script:endscript = $true
    $objForm.Close()
    })
$objForm.Controls.Add($CancelButton)

$snapshotSuffix = New-Object System.Windows.Forms.TextBox 
$snapshotSuffix.Location = New-Object System.Drawing.Size(90,250)
$snapshotSuffix.Size = New-Object System.Drawing.Size(150,20) 
$snapshotSuffix.add_TextChanged({isSnapshotSuffixTextChanged}) 
$objForm.Controls.Add($snapshotSuffix) 

#function to gray out ok button if invalid snapshot suffix is entered

function isSnapshotSuffixTextChanged{
    $LabelSnapshotSuffixError.Text = ""
    if (($snapshotSuffix.Text -notmatch "^[\w\-]+$") -and ($snapshotSuffix.Text -ne ""))
    {
        $LabelSnapshotSuffixError.ForeColor = "Red"
        $LabelSnapshotSuffixError.Text = "The suffix must only be letters, numbers or dashes"
        $OKButton.Enabled = $false
    }
    elseif ($snapshotSuffix.Text -eq "")
    {
        checkButton
    }
    else
    {
        checkButton
    }
}

#define add button
$AddButton = New-Object System.Windows.Forms.Button
$AddButton.Location = New-Object System.Drawing.Size(273,120)
$AddButton.Size = New-Object System.Drawing.Size(25,23)
$AddButton.Text = ">>"
$AddButton.Add_Click(
   {
        if ($objListbox.SelectedItems.Count -gt 0)
        {
            $script:selectedVolumes = $SelectListbox.Items
            foreach ($objItem in $objListbox.SelectedItems)
            {
                $script:selectedVolumes += $objItem
            }
            $SelectListbox.Items.Clear()
            foreach ($selectedVolume in $selectedVolumes)
            {
                $SelectListbox.Items.Add($selectedVolume)
            }
            $objListbox.Items.Clear()
            foreach ($volume in $volumes)
            {
                if ($script:selectedVolumes -notcontains $volume.name)
                {
                [void] $objListbox.Items.Add($volume.name)
                }
            }
            checkButton
        }
   })
$objForm.Controls.Add($AddButton)

#gray out ok button if no items are selected
function checkButton{
    if ($SelectListbox.Items.Count -lt 1)
    {
     $OKButton.Enabled = $false
    }
    else
    {
        $OKButton.Enabled = $true
    }
}

#define remove button
$RemoveButton = New-Object System.Windows.Forms.Button
$RemoveButton.Location = New-Object System.Drawing.Size(273,150)
$RemoveButton.Size = New-Object System.Drawing.Size(25,23)
$RemoveButton.Text = "<<"
$RemoveButton.Add_Click(
   {
        $removedVols = @()
        foreach ($objItem in $SelectListbox.SelectedItems)
        {
            $removedVols += $objItem
        }
        foreach ($removedVol in $removedVols)
        {
            $SelectListbox.Items.Remove($removedVol)
        }
        $script:selectedVolumes = $SelectListbox.Items
        $objListbox.Items.Clear()
        foreach ($volume in $volumes)
        {
            if ($script:selectedVolumes -notcontains $volume.name)
            {
            [void] $objListbox.Items.Add($volume.name)
            }
        }
        checkButton
   })
$objForm.Controls.Add($RemoveButton)

#label
$objLabel = New-Object System.Windows.Forms.Label
$objLabel.Location = New-Object System.Drawing.Size(10,20) 
$objLabel.Size = New-Object System.Drawing.Size(280,20) 
$objLabel.Text = "Choose one or more VMFS datastores:"
$objForm.Controls.Add($objLabel) 

$volLabel = New-Object System.Windows.Forms.Label
$volLabel.Location = New-Object System.Drawing.Size(301,20) 
$volLabel.Size = New-Object System.Drawing.Size(280,20) 
$volLabel.Text = "Selected FlashArray VMFS volumes:"
$objForm.Controls.Add($volLabel)

$LabelSnapshotSuffixError = New-Object System.Windows.Forms.Label
$LabelSnapshotSuffixError.Location = New-Object System.Drawing.Size(245,248) 
$LabelSnapshotSuffixError.Size = New-Object System.Drawing.Size(150,40) 
$LabelSnapshotSuffixError.Text = ""
$objForm.Controls.Add($LabelSnapshotSuffixError)

$LabelSnapshotSuffix = New-Object System.Windows.Forms.Label
$LabelSnapshotSuffix.Location = New-Object System.Drawing.Size(5,252) 
$LabelSnapshotSuffix.Size = New-Object System.Drawing.Size(100,40) 
$LabelSnapshotSuffix.Text = "Snapshot suffix:"
$objForm.Controls.Add($LabelSnapshotSuffix)

#Selection box
$objListbox = New-Object System.Windows.Forms.Listbox 
$objListbox.Location = New-Object System.Drawing.Size(10,40) 
$objListbox.Size = New-Object System.Drawing.Size(260,20) 
$objListbox.SelectionMode = "MultiExtended"

#selected box
$SelectListbox = New-Object System.Windows.Forms.Listbox 
$SelectListbox.Location = New-Object System.Drawing.Size(301,40) 
$SelectListbox.Size = New-Object System.Drawing.Size(260,20) 
$SelectListbox.SelectionMode = "MultiExtended"

#find FlashArray serial number
try
{
    $arraysn = Get-PfaArrayAttributes -Array $endpoint
    $arraysn = ($arraysn.id -replace "-","").substring(0,16)
}
catch
{
    add-content $logfile "Terminating Script. Could not retrieve FlashArray serial number."  
    write-host "Could not retrieve FlashArray serial number. Terminating Script" -BackgroundColor Red
    add-content $logfile $error[0]
    disconnectServers
    return
}
#get datastores that match the array SN only
try
{
    $volumes = Get-datastore -ErrorAction stop | where-object  {$_.Type -eq "VMFS" }|where-object {$_.ExtensionData.Info.Vmfs.Extent.diskname -like "*$($arraysn)*"}
}
catch
{
    add-content $logfile "Terminating Script. Could not retrieve VMFS datastores."  
    write-host "Could not retrieve VMFS datastores. Terminating Script. Refer to the log for details." -BackgroundColor Red
    add-content $logfile $error[0]
    disconnectServers
    return
}
if ($volumes.count -eq 0)
{
    add-content $logfile "Terminating Script. Could not find any VMFS datastores in this vCenter on entered FlashArray."  
    write-host "Could not find any VMFS datastores in this vCenter on entered FlashArray. Terminating Script" -BackgroundColor Red
    return
}
foreach ($volume in $volumes)
{
    [void] $objListbox.Items.Add($volume.name)
}

$objListbox.Height = 200
$SelectListbox.Height = 200
$objForm.Controls.Add($objListbox) 
$objForm.Controls.Add($SelectListbox) 
$objForm.Topmost = $True

$objForm.Add_Shown({$objForm.Activate()})
[void] $objForm.ShowDialog()

#end script if no volumes were selected
if ($endscript)
{
    add-content $logfile "Terminating Script. No volume(s) selected."  
    write-host "No volume(s) selected. Terminating Script" -BackgroundColor Red
    disconnectServers
    return
}
add-content $logfile "Selected volumes are: "
add-content $logfile $selectedVolumes

#find FlashArray volumes that host VMFS datastores
$selectedFAVolumes = @()
$FAVols = Get-PfaVolumes -Array $EndPoint
foreach ($selectedVolume in $selectedVolumes)
{
    $vmfs = get-datastore -name $selectedVolume
    $lun = $vmfs.ExtensionData.Info.Vmfs.Extent.DiskName 
    $volserial = ($lun.ToUpper()).substring(12)
    $purevol = $FAVols | where-object { $_.serial -eq $volserial }
    $selectedFAVolumes += $purevol.name
}

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

add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile "Selected cluster is $($clusterName)"
try
{
    $cluster = get-cluster -Name $clusterName
}
catch
{
    add-content $logfile "Terminating Script. Could not find entered cluster."  
    write-host "Could not find entered cluster. Terminating Script. Refer to the log for details." -BackgroundColor Red
    add-content $logfile $error[0]
    disconnectServers
    return
}
#identify host group for volume connection. Looks for the first FlashArray host that matches an ESXi by iSCSI initiators or FC and then finds its host group. If not in a host group the process fails.
try
    {
        $fcinitiators = @()
        $iscsiinitiators = @()
        $iscsiadapters = $cluster  |Get-VMHost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
        $fcadapters = $cluster  |Get-VMHost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        foreach ($iscsiadapter in $iscsiadapters)
        {
            $iqn = $iscsiadapter.ExtensionData.IScsiName
            $iscsiinitiators += $iqn.ToLower()
        }
        $fcadapters = (($fcadapters.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $fcadapters = &{for ($i = 0;$i -lt $fcadapters.length;$i += 16)
        {
                $fcadapters.substring($i,16)
        }}
        foreach ($fcadapter in $fcadapters)
        {
            $fcinitiators += $fcadapter.ToLower()
        }
        if ($iscsiinitiators.count -gt 0)
        {
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            add-content $logfile "Found the following iSCSI initiators in the cluster:"
            add-content $logfile $iscsiinitiators
        }
        if ($fcinitiators.count -gt 0)
        {
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            add-content $logfile "Found the following Fibre Channel initiators in the cluster:"
            add-content $logfile $fcinitiators
        }
        $fahosts = Get-PfaHosts -array $endpoint
        $script:hostgroup = $null
        foreach ($fahost in $fahosts)
        {
            foreach ($iscsiinitiator in $iscsiinitiators)
            {
                if ($fahost.iqn -contains $iscsiinitiator)
                {
                    add-content $logfile "Found a matching host called $($fahost.name)"
                    if ($fahost.hgroup -eq $null)
                    {
                        throw "The identified host is not in a host group. Terminating script"
                    }
                    $script:hostgroup = $fahost.hgroup
                    break
                }
            }
            if ($hostgroup -ne $null)
            {
                break
            }
            foreach ($fcinitiator in $fcinitiators)
            {
                if ($fahost.wwn -contains $fcinitiator)
                {
                    add-content $logfile "Found a matching host called $($fahost.name)"
                    if ($fahost.hgroup -eq $null)
                    {
                        throw "The identified host is not in a host group. Terminating script"
                    }
                    $script:hostgroup = $fahost.hgroup
                    break
                }
            }
            if ($hostgroup -ne $null)
            {
                break
            }
        }
        if ($hostgroup -eq $null)
        {
              throw "No matching host group could be found"
        }
        else
        {
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            add-content $logfile "The host group identified is named $($hostgroup)"
        }
    }
catch
{
        write-host "No matching host group could be found. See log for details." -BackgroundColor Red
        add-content $logfile $Error[0]
        disconnectServers
        return
}
add-content $logfile '----------------------------------------------------------------------------------------------------'
#start snapshot process
try
{
    if ($snapshotNameSuffix -ne "")
    {
        add-content $logfile "Snapshot suffix will be $($snapshotNameSuffix)"
        $snapshots = New-PfaVolumeSnapshots -Array $endpoint -Sources $selectedVolumes -Suffix $snapshotNameSuffix
    }
    else
    {
       $snapshots = New-PfaVolumeSnapshots -Array $endpoint -Sources $selectedVolumes
    }
}
catch
{
    add-content $logfile "Deleting any successfully created snapshots"
    foreach ($snapshot in $snapshots)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated snapshot $($snapshot.name)"
    }
    add-content $logfile "Terminating Script. Could not create snapshots."  
    write-host "Terminating Script. Could not create snapshots. Refer to the log for details." -BackgroundColor Red
    add-content $logfile $error[0]
    disconnectServers
    return
}
add-content $logfile "Created $($snapshots.count) snapshot(s):"
add-content $logfile $snapshots.name
#create volumes from snapshots
add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile "Creating $($snapshots.count) volume(s)..."
try
{
    $newVols = @()
    $randomNum = Get-Random -Maximum 99999 -Minimum 10000
    #create new vol from snapshot add a suffix to original name of -copy-<random 5 digit number>
    foreach ($snapshot in $snapshots)
    {
        $newVols += New-PfaVolume -Source $snapshot.name -VolumeName ("$($snapshot.source)-copy-$($randomNum)") -Array $EndPoint
        add-content $logfile "Created volume named $($snapshot.source)-copy-$($randomNum)"
    }
}
catch
{
    add-content $logfile "Failed to create new volumes."
    add-content $logfile $error[0]
    add-content $logfile "Deleting any successfully created snapshots and volumes"
    foreach ($snapshot in $snapshots)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated snapshot $($snapshot.name)"
    }
    foreach ($newVol in $newVols)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated volume $($newVol.name)"
    }
    add-content $logfile "Terminating Script."  
    write-host "Terminating Script. Could not create volume(s). Refer to the log for details." -BackgroundColor Red
    disconnectServers
    return
}
#connecting to host group
add-content $logfile '----------------------------------------------------------------------------------------------------'
try
{
    $hgroupConnections = @()
    add-content $logfile "Connecting volumes to host group"
    foreach ($newVol in $newVols)
    {
        $hgroupConnections += New-PfaHostGroupVolumeConnection -Array $EndPoint -VolumeName $newVol.name -HostGroupName $hostgroup
        add-content $logfile "Connected $($newVol.name) to host group $($hostgroup)"
    }
}
catch
{
    add-content $logfile "Failed to connect new volumes."
    add-content $logfile $error[0]
    cleanUp
    add-content $logfile "Terminating Script."  
    write-host "Terminating Script. Could not create volume(s). Refer to the log for details." -BackgroundColor Red
    disconnectServers
    return
}
#rescanning cluster. Spinning out jobs to rescan hosts in parallel. Waits for all to finish before moving on
$hosts = $cluster |Get-VMHost
foreach ($esxi in $hosts) 
{
        $argList = @($vcenter, $Creds, $esxi)
        $job = Start-Job -ScriptBlock{ 
            Connect-VIServer -Server $args[0] -Credential $args[1]
            Get-VMHost -Name $args[2] | Get-VMHostStorage -RescanAllHba -RescanVMFS
            Disconnect-VIServer -Confirm:$false
        } -ArgumentList $argList
}
Get-Job | Wait-Job -Timeout 120|out-null

#choose a host in the cluster that is online to resignature the volumes
$resigHost = $cluster |Get-VMHost |where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1

add-content $logfile '----------------------------------------------------------------------------------------------------'
#validate resignaturing process
try
{
    Start-sleep -s 10
    $esxcli = get-esxcli -VMHost $resigHost -v2
    $unresolvedvmfs = $esxcli.storage.vmfs.snapshot.list.invoke() | where-object {$selectedVolumes -contains $_.VolumeName}
    if (($unresolvedVMFS.canresignature|select-object -unique).count -ne 1)
    {
        foreach ($unresolved in $unresolvedVMFS)
        {
            if ($unresolved.canresignature -eq $false)
            {
                add-content $logfile "ERROR: Volume $($unresolved.volumeName) is cannot be resolved for the following reason:"
                add-content $logfile $unresolved.Reasonfornonresignaturability
            }
        }
        throw "Cannot resignature one or more volumes. Terminating script. See log for details."
    }
    if ($unresolvedvmfs.count -eq 0)
    {
        throw "Expected volumes to be resignatured were not found. Terminating script."
    }
}
catch
{
    write-host $error[0] -BackgroundColor Red
    add-content $logfile $error[0]
    cleanUp
    disconnectServers
    return
}

add-content $logfile '----------------------------------------------------------------------------------------------------'
#resignature volumes
try
{
    add-content $logfile "Resignaturing the VMFS volume(s) ..."
    foreach ($unresolved in $unresolvedvmfs)
    {
        $resigArgs = $esxcli.storage.vmfs.snapshot.resignature.CreateArgs()
        $resigArgs.volumelabel = $unresolved.volumename
        $resigArgs = $esxcli.storage.vmfs.snapshot.resignature.Invoke($resigArgs)
        add-content $logfile "Resignatured the VMFS volume $($unresolved.volumename)."
    }
}
catch
{
    add-content $logfile "Error resignaturing volumes."
    add-content $logfile $error[0]
    write-host "Error resignaturing volumes. See log for details." -BackgroundColor Red
    cleanUp
}
disconnectServers
add-content $logfile "Process completed successfully!"
write-host "Process completed successfully!" -ForegroundColor Green