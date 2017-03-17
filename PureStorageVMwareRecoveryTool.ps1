<#
***************************************************************************************************
VMWARE POWERCLI AND PURE STORAGE POWERSHELL SDK MUST BE INSTALLED ON THE MACHINE THIS IS RUNNING ON
***************************************************************************************************

For info, refer to www.codyhosterman.com

*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-PowerShell 3.0 or later
-Pure Storage PowerShell SDK 1.7 or later
-PowerCLI 6.3 Release 1+
-Purity 4.1 and later
-FlashArray 400 Series and //m
-vCenter 5.5 and later

'Pure Storage FlashArray VMware Snapshot Recovery Tool v1.0.1'
#>

#Import PowerCLI. Requires PowerCLI version 6.3 or later. Will fail here if PowerCLI is not installed
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
        return
    }
}
#Set
Set-PowerCLIConfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -confirm:$false |out-null
$EndPoint = $null
$ErrorActionPreference = "Stop"
#Connection Functions
function connectServer{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try 
    {
        $connect = Connect-VIServer -Server $serverTextBox.Text -User $usernameTextBox.Text -Password $passwordTextBox.Text -ErrorAction stop
        $buttonConnect.Enabled = $false #Disable controls once connected
        $serverTextBox.Enabled = $false
        $usernameTextBox.Enabled = $false
        $passwordTextBox.Enabled = $false
        $buttonDisconnect.Enabled = $true #Enable Disconnect button
        $outputTextBox.text = ("Successfully connected to vCenter $($serverTextBox.Text)`r`n$($outputTextBox.text)")
        if ($EndPoint.Disposed -eq $false)
        {
            $RadioButtonVMFS.Enabled=$true
            $RadioButtonVMFS.Checked=$true
            $RadioButtonVM.Enabled=$true
            $RadioButtonVMDK.Enabled=$true
            $RadioButtonRDM.Enabled=$true
            $nameFilterTextBox.Enabled = $true
            $buttonDatastores.Enabled = $true
            $DatastoreDropDownBox.Items.Clear()
            getClusters
        }
    }
    catch 
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}

function disconnectServer{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try 
    {
        $disconnect = Disconnect-VIServer -Server $serverTextBox.Text -Confirm:$false -Force:$true -ErrorAction stop
        $buttonConnect.Enabled = $true #Enable login controls once disconnected
        $serverTextBox.Enabled = $true
        $usernameTextBox.Enabled = $true
        $passwordTextBox.Enabled = $true
        $buttonDisconnect.Enabled = $false #Disable Disconnect button
        $ClusterDropDownBox.Items.Clear() #Remove all items from DropDown boxes
        $ClusterDropDownBox.Enabled=$false #Disable DropDown boxes since they are empty
        $DatastoreDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Enabled=$false #Disable DropDown boxes since they are empty
        $SnapshotDropDownBox.Items.Clear()
        $DatastoreDropDownBox.Enabled=$false
        $VMDropDownBox.Items.Clear()
        $VMDropDownBox.Enabled=$false
        $VMDKDropDownBox.Items.Clear()
        $VMDKDropDownBox.Enabled=$false
        $RDMDropDownBox.Items.Clear()
        $RDMDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Items.Clear()
        $RecoveryClusterDropDownBox.Enabled=$false
        $buttonRecover.Enabled = $false
        $buttonSnapshots.Enabled = $false
        $buttonDatastores.Enabled = $false
        $buttonNewSnapshot.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $buttonVMs.Enabled = $false
        $RadioButtonVMFS.Enabled=$false
        $RadioButtonVM.Enabled=$false
        $RadioButtonVMDK.Enabled=$false
        $RadioButtonRDM.Enabled=$false
        $outputTextBox.text = "Successfully disconnected from vCenter $($serverTextBox.Text)`r`n" + $outputTextBox.text
    }
    catch 
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function connectFlashArray{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
     try
        {
            $FApassword = convertto-securestring $flasharrayPasswordTextBox.Text -asplaintext -force
            $script:EndPoint = New-PfaArray -EndPoint $flasharrayTextBox.Text -Username $flasharrayUsernameTextBox.Text -Password $FApassword -IgnoreCertificateError -ErrorAction stop
            $outputTextBox.text = "Successfully connected to FlashArray $($flasharrayTextBox.Text)" + ("`r`n") + $outputTextBox.text
            $flasharrayButtonConnect.enabled = $false
            $flasharrayButtonDisconnect.enabled = $true
            $flasharrayTextBox.Enabled = $false
            $flasharrayUsernameTextBox.Enabled = $false
            $flasharrayPasswordTextBox.Enabled = $false
            if ($buttonDisconnect.Enabled -eq $true)
            {
                $RadioButtonVMFS.Enabled=$true
                $RadioButtonVMFS.Checked=$true
                $RadioButtonVM.Enabled=$true
                $RadioButtonVMDK.Enabled=$true
                $RadioButtonRDM.Enabled=$true
                $nameFilterTextBox.Enabled = $true
                $buttonDatastores.Enabled = $true
                $DatastoreDropDownBox.Items.Clear()
                getClusters
            }
        }
        catch
        {
            $outputTextBox.text = ("Connection to FlashArray " + $flasharrayTextBox.Text + " failed. Please check credentials or IP/FQDN") + ("`r`n") + $outputTextBox.text
            $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
        }
}
function disconnectFlashArray{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try
    {
        Disconnect-PfaArray -Array $EndPoint -ErrorAction stop
        $flasharrayButtonDisconnect.enabled = $false
        $flasharrayButtonConnect.enabled = $true
        $flasharrayTextBox.Enabled = $true
        $flasharrayUsernameTextBox.Enabled = $true
        $flasharrayPasswordTextBox.Enabled = $true
        $buttonSnapshots.Enabled = $false
        $buttonNewSnapshot.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $SnapshotDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Enabled=$false
        $buttonRecover.Enabled = $false
        $outputTextBox.text = ("Successfully disconnected from FlashArray " + $flasharrayTextBox.Text) + ("`r`n") + $outputTextBox.text
    }
    catch
    {
        $outputTextBox.text = ("Disconnection from FlashArray " + $flasharrayTextBox.Text + " failed.") + ("`r`n") + $outputTextBox.text
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}

#Inventory Functions
function getDatastores{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try 
    {
        $DatastoreDropDownBox.Items.Clear()
        if ($ClusterDropDownBox.SelectedItem.ToString() -eq "<All Clusters>")
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $datastores = get-datastore -Name ("*" + $nameFilterTextBox.Text + "*")
            }
            else
            {
                $datastores = get-datastore
            }
        }
        else
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $datastores = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() |get-datastore -Name ("*" + $nameFilterTextBox.Text + "*")
            }
            else
            {
                $datastores = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() |get-datastore
            }
        }
        if ($datastores.count -ge 1)
        {
            $DatastoreDropDownBox.Enabled=$true
            foreach ($datastore in $datastores) 
            {
                $DatastoreDropDownBox.Items.Add($datastore.Name) #Add Datastores to DropDown List
            }
            getRecoveryClusters
            $DatastoreDropDownBox.SelectedIndex = 0
            if ($endpoint.Disposed -eq $false)
            {
	            $buttonSnapshots.Enabled = $true
                $newSnapshotTextBox.Enabled = $true
            }
            else
            {
	            $buttonSnapshots.Enabled = $false
                $newSnapshotTextBox.Enabled = $false
            }
        }
        elseif ($datastores.count -eq 0)
        {
            $DatastoreDropDownBox.Enabled=$false
            $DatastoreDropDownBox.Items.Add("<No Datastores Found>") #Add Datastores to DropDown List
            $DatastoreDropDownBox.SelectedIndex = 0
            $buttonSnapshots.Enabled = $false
            $newSnapshotTextBox.Enabled = $false
        }
    }
    catch 
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}

function getClusters{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try 
    {
        $clusters = Get-Cluster #Returns all clusters
        $ClusterDropDownBox.Items.Clear()
        $ClusterDropDownBox.Items.Add("<All Clusters>")
        foreach ($cluster in $clusters) 
        {
            $ClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
            $ClusterDropDownBox.Enabled = $true
        } 
    }
    catch 
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
    $ClusterDropDownBox.SelectedIndex = 0
}
function getRecoveryClusters{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try 
    {
        $clusters = Get-Cluster #Returns all clusters
        $RecoveryClusterDropDownBox.Items.Clear()
        foreach ($cluster in $clusters) 
        {
            $RecoveryClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
            $RecoveryClusterDropDownBox.Enabled = $true
        } 
    }
    catch 
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
    $RecoveryClusterDropDownBox.SelectedIndex = 0
}
function getSnapshots{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try
    {
        $SnapshotDropDownBox.Items.Clear()
        if ($RadioButtonVMFS.Checked -eq $true)
        {
                    $datastore = get-datastore $DatastoreDropDownBox.SelectedItem.ToString()
                    $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        if ($RadioButtonVM.Checked -eq $true)
        {
            $datastore = get-vm -Name $VMDropDownBox.SelectedItem.ToString() |Get-Datastore
            $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
            if ($datastore.count -gt 1)
            {
                throw "This VM uses more than one datastore and is not supported in this tool"
            }
        }
        if ($RadioButtonVMDK.Checked -eq $true)
        {
            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
            $datastore = get-datastore (($VMDKDropDownBox.SelectedItem.ToString() |foreach { $_.Split("]")[0] }).substring(1))
            $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        if ($RadioButtonRDM.Checked -eq $true)
        {
            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
            $lun = ($RDMDropDownBox.SelectedItem.ToString()).substring(0,36)
        }
        if ($lun -like 'naa.624a9370*')
        {
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $script:purevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($purevol -eq $null)
            {
                $outputTextBox.text =  "ERROR: Volume not found on connected FlashArray." + ("`r`n") + $outputTextBox.text
            }
            else
            {
                $script:snapshots = $null
                $script:snapshots = Get-PfaVolumeSnapshots -array $endpoint -VolumeName $purevol.name
                if ($snapshots -ne $null)
                {
                    foreach ($snapshot in $snapshots) 
                    {
                        $SnapshotDropDownBox.Items.Add("$($snapshot.Name) ($($snapshot.Created))") #Add snapshots to drop down List
                        $SnapshotDropDownBox.Enabled=$true
                        $SnapshotDropDownBox.SelectedIndex = 0
                        $buttonRecover.Enabled = $true
                    }
                }
                else
                {
                    $SnapshotDropDownBox.Items.Add("No snapshots found")
                    $SnapshotDropDownBox.SelectedIndex = 0
                    $buttonRecover.Enabled = $false
                    $SnapshotDropDownBox.Enabled=$false
                }
            }
        }
        else
        {
            $outputTextBox.text = "Selected datastore is not a FlashArray volume." + ("`r`n") + $outputTextBox.text
            $buttonRecover.Enabled = $false
        }
    }
    catch
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getHostGroup{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try
    {
        $fcinitiators = @()
        $iscsiinitiators = @()
        if ($RadioButtonVMFS.Checked -eq $true)
        {
            $iscsiadapters = get-cluster -Name $RecoveryClusterDropDownBox.SelectedItem.ToString()  |Get-VMHost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
            $fcadapters = get-cluster -Name $RecoveryClusterDropDownBox.SelectedItem.ToString()  |Get-VMHost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        }
        else
        {
            $iscsiadapters = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  |Get-VMHost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
            $fcadapters = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  |Get-VMHost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        }
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
        $fahosts = Get-PfaHosts -array $endpoint
        $script:hostgroup = $null
        foreach ($fahost in $fahosts)
        {
            foreach ($iscsiinitiator in $iscsiinitiators)
            {
                if ($fahost.iqn -contains $iscsiinitiator)
                {
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
            $outputTextBox.text = ("No matching host group could be found") + ("`r`n") + $outputTextBox.text
        }
        else
        {
           $outputTextBox.text = ("The host group identified is named $($hostgroup)`r`n$($outputTextBox.text)") 
        }
    }
    catch
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getVMs{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try 
    {
        $VMDropDownBox.Items.Clear()
        if ($ClusterDropDownBox.SelectedItem.ToString() -eq "<All Clusters>")
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $vms = get-vm -Name ("*" + $nameFilterTextBox.Text + "*")
            }
            else
            {
                $vms = get-vm
            }
        }
        else
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $vms = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() |get-vm -Name ("*" + $nameFilterTextBox.Text + "*")
            }
            else
            {
                $vms = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() |get-vm
            }
        }
        if ($vms.count -eq 0)
        {
            $VMDropDownBox.Items.Add("No VMs found")
            $VMDropDownBox.SelectedIndex = 0
            $VMDropDownBox.Enabled=$false
            $newSnapshotTextBox.Enabled = $false
            $deleteCheckBox.Enabled = $false
            $deleteCheckBox.Checked = $false
            $migrateCheckBox.Checked = $false
            $migrateCheckBox.Enabled = $false
        }
        else
        {
            foreach ($vm in $vms) 
            {
                $VMDropDownBox.Items.Add($vm.Name) #Add VMs to DropDown List                
            }
            $VMDropDownBox.Enabled=$true
            $VMDropDownBox.SelectedIndex = 0
            if ($endpoint.Disposed -eq $false)
            {
	            $buttonSnapshots.Enabled = $true
                $newSnapshotTextBox.Enabled = $true
            }
            else
            {
	            $buttonSnapshots.Enabled = $false
                $newSnapshotTextBox.Enabled = $false
            }
            if ($RadioButtonVM.Checked -eq $false)
            {
                getDisks
            }
        }
    }
    catch 
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getDisks{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    $SnapshotDropDownBox.Items.Clear()
    $SnapshotDropDownBox.Enabled = $false
    $newSnapshotTextBox.Enabled = $false
    $deleteCheckBox.Enabled = $false
    $deleteCheckBox.Checked = $false
    $migrateCheckBox.Checked = $false
    $migrateCheckBox.Enabled = $false
    try
    {
        if (($VMDropDownBox.text -ne "No VMs found") -and ($RadioButtonVM.Checked -ne $true))
        {
            if ($RadioButtonVMDK.Checked -eq $true)
            {
                $VMDKDropDownBox.Items.Clear()
                $atLeastOnevdisk = $false
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
                $vmdevices = $vm.ExtensionData.Config.Hardware.Device 
                foreach ($vmdevice in $vmdevices)
                {
                    if ($vmdevice.gettype().Name -eq "VirtualDisk")
                    {
                        if ( $vmdevice.Backing.gettype().Name -eq "VirtualDiskFlatVer2BackingInfo")
                        {
                            $atLeastOnevdisk = $true
                            $VMDKDropDownBox.Items.Add(("$($vmdevice.Backing.fileName) ($($vmdevice.CapacityInKB/1024/1024) GB)"))
                        }
                    } 
                }
                if ($atLeastOnevdisk -eq $true)
                {
                    $VMDKDropDownBox.Enabled = $true
                    $VMDKDropDownBox.SelectedIndex = 0
                    $migrateCheckBox.Checked = $false
                    $migrateCheckBox.Enabled = $true
                    $deleteCheckBox.Checked = $false
                    $deleteCheckBox.Enabled = $true
                    $newSnapshotTextBox.Enabled = $true
                }
                else
                {
                    $VMDKDropDownBox.Items.Add("No virtual disks found")
                    $VMDKDropDownBox.SelectedIndex = 0
                    $VMDKDropDownBox.Enabled = $false
                    $newSnapshotTextBox.Enabled = $false
                    $buttonSnapshots.Enabled = $false
                }
            }
            elseif ($RadioButtonRDM.Checked -eq $true)
            {
                $RDMDropDownBox.Items.Clear()
                $atLeastOnevdisk = $false
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
                $vmdevices = $vm.ExtensionData.Config.Hardware.Device 
                foreach ($vmdevice in $vmdevices)
                {
                    if ($vmdevice.gettype().Name -eq "VirtualDisk")
                    {
                        if ( $vmdevice.Backing.gettype().Name -eq "VirtualDiskRawDiskMappingVer1BackingInfo")
                        {
                            $atLeastOnerdm = $true
                            $RDMname = ("naa.$($vmdevice.Backing.DeviceName.substring(14,32)) ($($vmdevice.CapacityInKB/1024/1024) GB)")
                            $RDMDropDownBox.Items.Add($RDMname)
                            $deleteCheckBox.Enabled = $true
                        }
                    } 
                }
                if ($atLeastOnerdm -eq $true)
                {
                    $RDMDropDownBox.Enabled = $true
                    $RDMDropDownBox.SelectedIndex = 0
                    $migrateCheckBox.Checked = $false
                    $migrateCheckBox.Enabled = $false
                    $deleteCheckBox.Checked = $false
                    $deleteCheckBox.Enabled = $true
                    $newSnapshotTextBox.Enabled = $true
                    $buttonSnapshots.Enabled = $true
                }
                else
                {
                    $RDMDropDownBox.Items.Add("No raw device mappings found")
                    $RDMDropDownBox.SelectedIndex = 0
                    $RDMDropDownBox.Enabled = $false
                    $newSnapshotTextBox.Enabled = $false
                    $buttonSnapshots.Enabled = $false
                }
            }
        }
        else
        {
            $deleteCheckBox.Checked = $false
            $deleteCheckBox.Enabled = $true
            $migrateCheckBox.Checked = $false
            $migrateCheckBox.Enabled = $true
            $newSnapshotTextBox.Enabled = $true
        }
    }
    catch
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}
#Context change functions
function isSnapshotTextChanged{
    $LabelNewSnapError.Text = ""
    if (($newSnapshotTextBox.Text -notmatch "^[\w\-]+$") -and ($newSnapshotTextBox.Text -ne ""))
    {
        $LabelNewSnapError.ForeColor = "Red"
        $LabelNewSnapError.Text = "The snapshot name must only be letters, numbers or dashes"
    }
    else
    {
        $buttonNewSnapshot.Enabled = $true
    }
}
function isVCTextChanged{
    if (($passwordTextBox.Text.Length  -gt 0) -and ($usernameTextBox.Text.Length  -gt 0) -and ($ServerTextBox.Text.Length  -gt 0) ) 
    {
        $buttonConnect.enabled = $true
    } 
    else 
    {
        $buttonConnect.enabled = $false
    }
}
function isFATextChanged{
    if (($flasharrayPasswordTextBox.Text.Length  -gt 0) -and ($flasharrayUsernameTextBox.Text.Length  -gt 0) -and ($flasharrayTextBox.Text.Length  -gt 0) ) 
    {
        $flasharrayButtonConnect.enabled = $true
    } 
    else 
    {
        $flasharrayButtonConnect.enabled = $false
    }
}
function datastoreSelectionChanged{
    $SnapshotDropDownBox.Enabled=$false
    $buttonRecover.Enabled = $false
    $SnapshotDropDownBox.Items.Clear()
}
function clusterSelectionChanged{
    $DatastoreDropDownBox.Enabled=$false
    $DatastoreDropDownBox.Items.Clear()
    $DatastoreDropDownBox.Items.Clear()
    $VMDropDownBox.Items.Clear()
    $VMDKDropDownBox.Items.Clear()
    $RDMDropDownBox.Items.Clear()
}
function nameFilterChanged{
    $DatastoreDropDownBox.Items.Clear()
    $DatastoreDropDownBox.Enabled=$false
}

function radioSelect{
    if ($RadioButtonVMFS.Checked -eq $true)
    {
        $SnapshotDropDownBox.Items.Clear()
        $VMDropDownBox.Items.Clear()
        $VMDKDropDownBox.Items.Clear()
        $RDMDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Enabled=$false
        $buttonVMs.Enabled = $false
        $DatastoreDropDownBox.Enabled=$false
        $VMDKDropDownBox.Enabled=$false
        $RDMDropDownBox.Enabled=$false
        $buttonDatastores.Enabled = $true
        $DatastoreDropDownBox.Items.Clear()
        $VMDropDownBox.Enabled=$false
        $DatastoreDropDownBox.Items.Clear()
        $buttonSnapshots.Enabled = $false
        $buttonNewSnapshot.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $newSnapshotTextBox.Text = ""
        $buttonRecover.Enabled = $false
        $deleteCheckBox.Checked = $false
        $deleteCheckBox.Enabled = $false
        $migrateCheckBox.Checked = $false
        $migrateCheckBox.Enabled = $false
    }
    if ($RadioButtonVM.Checked -eq $true)
    {
        $buttonVMs.Enabled = $true
        $VMDropDownBox.Enabled=$false
        $VMDKDropDownBox.Enabled=$false
        $RDMDropDownBox.Enabled=$false
        $VMDropDownBox.Items.Clear()
        $VMDKDropDownBox.Items.Clear()
        $RDMDropDownBox.Items.Clear()
        $buttonDatastores.Enabled = $false
        $RDMDropDownBox.Items.Clear()
        $DatastoreDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Enabled=$false
        $SnapshotDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Items.Clear()
        $DatastoreDropDownBox.Items.Clear()
        $VMDropDownBox.Items.Clear()
        $buttonSnapshots.Enabled = $false
        $buttonNewSnapshot.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $newSnapshotTextBox.Text = ""
        $buttonRecover.Enabled = $false
        $DatastoreDropDownBox.Items.Clear()
        $deleteCheckBox.Checked = $false
        $deleteCheckBox.Enabled = $false
        $migrateCheckBox.Checked = $false
        $migrateCheckBox.Enabled = $false
    }
    if ($RadioButtonVMDK.Checked -eq $true)
    {
        $buttonVMs.Enabled = $true
        $VMDropDownBox.Enabled=$false
        $buttonDatastores.Enabled = $false
        $DatastoreDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Enabled=$false
        $VMDropDownBox.Items.Clear()
        $VMDKDropDownBox.Items.Clear()
        $RDMDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Items.Clear()
        $VMDropDownBox.Items.Clear()
        $VMDKDropDownBox.Items.Clear()
        $DatastoreDropDownBox.Items.Clear()
        $RDMDropDownBox.Enabled = $false
        $VMDKDropDownBox.Enabled = $false
        $RDMDropDownBox.Items.Clear()
        $buttonSnapshots.Enabled = $false
        $buttonNewSnapshot.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $newSnapshotTextBox.Text = ""
        $buttonRecover.Enabled = $false
        $deleteCheckBox.Checked = $false
        $deleteCheckBox.Enabled = $false
        $migrateCheckBox.Checked = $false
        $migrateCheckBox.Enabled = $false
    }
    if ($RadioButtonRDM.Checked -eq $true)
    {
        $buttonVMs.Enabled = $true
        $VMDropDownBox.Enabled=$false
        $buttonDatastores.Enabled = $false
        $DatastoreDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Enabled=$false
        $SnapshotDropDownBox.Enabled=$false
        $RecoveryClusterDropDownBox.Items.Clear()
        $DatastoreDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Items.Clear()
        $VMDropDownBox.Items.Clear()
        $RDMDropDownBox.Items.Clear()
        $VMDropDownBox.Items.Clear()
        $VMDKDropDownBox.Items.Clear()
        $RDMDropDownBox.Items.Clear()
        $VMDKDropDownBox.Enabled = $false
        $VMDKDropDownBox.Items.Clear()
        $buttonSnapshots.Enabled = $false
        $RDMDropDownBox.Enabled = $false
        $buttonNewSnapshot.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $newSnapshotTextBox.Text = ""
        $buttonRecover.Enabled = $false
        $deleteCheckBox.Checked = $false
        $deleteCheckBox.Enabled = $false
        $migrateCheckBox.Checked = $false
        $migrateCheckBox.Enabled = $false
    }
}
#Recover Function
function newSnapshot{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    try
    {
        $LabelNewSnapError.Text = ""
        if ($RadioButtonVMFS.Checked -eq $true)
        {
                    $datastore = get-datastore $DatastoreDropDownBox.SelectedItem.ToString()
                    $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        if ($RadioButtonVM.Checked -eq $true)
        {
            $datastore = get-vm -Name $VMDropDownBox.SelectedItem.ToString() |Get-Datastore
            $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
            if ($datastore.count -gt 1)
            {
                throw "This VM uses more than one datastore and is not supported in this tool"
            }
        }
        if ($RadioButtonVMDK.Checked -eq $true)
        {
            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
            $datastore = get-datastore (($VMDKDropDownBox.SelectedItem.ToString() |foreach { $_.Split("]")[0] }).substring(1))
            $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        if ($RadioButtonRDM.Checked -eq $true)
        {
            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
            $lun = ($RDMDropDownBox.SelectedItem.ToString()).substring(0,36)
        }
        if ($lun -like 'naa.624a9370*')
        {
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $script:purevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($purevol -eq $null)
            {
                $outputTextBox.text =  "ERROR: Volume not found on connected FlashArray." + ("`r`n") + $outputTextBox.text
            }
            else
            {
                    $newSnapshot = New-PfaVolumeSnapshots -Array $EndPoint -Sources $purevol.name -Suffix $newSnapshotTextBox.Text -ErrorAction stop
                    $newSnapshotTextBox.Text = ""
                    $LabelNewSnapError.ForeColor = "Black"
                    $LabelNewSnapError.Text = "$($newSnapshot.Name) ($($newSnapshot.Created))"
                    $buttonNewSnapshot.Enabled = $false
                    
            }
        }
        else
        {
            $outputTextBox.text = "Selected datastore is not a FlashArray volume." + ("`r`n") + $outputTextBox.text
        }
    }
    catch
    {
        $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function recoverObject{
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    if ($RadioButtonRDM.Checked -eq $false)
    {
        getHostGroup
        try
        {
            $snapshotchoice = $SnapshotDropDownBox.SelectedIndex
            $volumename = $purevol.name + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
            $newvol =New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $volumename
            $outputTextBox.text = ("New FlashArray volume is $($newvol.name)`r`n$($outputTextBox.text)")
            New-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
            $outputTextBox.text = ("Connected volume to host group $($hostgroup)`r`n$($outputTextBox.text)")
            $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
            if ($RadioButtonVMFS.Checked -eq $true)
            {
                get-cluster -Name $RecoveryClusterDropDownBox.SelectedItem.ToString() | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
                $cluster =  get-cluster -Name $RecoveryClusterDropDownBox.SelectedItem.ToString()
                $esxi = $cluster | Get-VMHost -ErrorAction stop
                $esxcli=get-esxcli -VMHost $esxi[0] -v2 -ErrorAction stop
                $resigargs =$esxcli.storage.vmfs.snapshot.list.createargs()
                $sourceds = get-datastore $DatastoreDropDownBox.SelectedItem.ToString()
                $resigargs.volumelabel = $sourceds.Name
            }
            else
            {
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
                $cluster =  $vm |get-cluster
                $esxi = $cluster | Get-VMHost -ErrorAction stop
                $esxcli=get-esxcli -VMHost $esxi[0] -v2 -ErrorAction stop
                $resigargs =$esxcli.storage.vmfs.snapshot.list.createargs()
                $sourceds = $vm |get-datastore
                if ($sourceds.count -eq 1)
                {
                    $resigargs.volumelabel = $sourceds.Name
                }
                elseif ($RadioButtonVMDK.Checked -eq $true)
                {
                    $vmdkpath = ($VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                    $resigargs.volumelabel = ($vmdkpath.Split("]")[0]).substring(1)
                }
                elseif ($sourceds.count -gt 1)
                {
                    throw "This VM has more than one datastore and is not a supported configuration for this tool" 
                }
            }
            Start-sleep -s 10
            $unresolvedvmfs = $esxcli.storage.vmfs.snapshot.list.invoke($resigargs) 
            if ($unresolvedvmfs.UnresolvedExtentCount -ge 2)
            {
                throw ("ERROR: There is more than one unresolved copy of the source VMFS named " + $sourceds.Name)
            }
            else
            {
                $resigOp = $esxcli.storage.vmfs.snapshot.resignature.createargs()
                $resigOp.volumelabel = $resigargs.volumelabel
                $outputTextBox.text = ("Resignaturing the VMFS...`r`n$($outputTextBox.text)")
                $esxcli.storage.vmfs.snapshot.resignature.invoke($resigOp)
                Start-sleep -s 10
                $cluster | Get-VMHost | Get-VMHostStorage -RescanVMFS -ErrorAction stop 
                $datastores = $esxi[0] | Get-Datastore -ErrorAction stop
                $recoverylun = ("naa.624a9370" + $newvol.serial)
                foreach ($ds in $datastores)
                {
                    $naa = $ds.ExtensionData.Info.Vmfs.Extent.DiskName
                    if ($naa -eq $recoverylun.ToLower())
                    {
                        $resigds = $ds
                    }
                } 
                $resigds = $resigds | Set-Datastore -Name $volumename -ErrorAction stop
                $outputTextBox.text = "Presented copied VMFS named " + $resigds.name + ("`r`n") + $outputTextBox.text
            }
        }
        catch
        {
            $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)")
            if (($sourceds.count -eq 1) -or ($RadioButtonVMDK.Checked -eq $true))
            {
                $outputTextBox.text = ("Attempting to cleanup recovered datastore...`r`n$($outputTextBox.text)")
                if ($vms.count -eq 0)
                {
                    if ($unresolvedvmfs.UnresolvedExtentCount -eq 1)
                    {
                        $esxihosts = $resigds |get-vmhost
                        foreach ($esxihost in $esxihosts)
                        {
                            $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                        $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                            $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                        }
                    }
                    Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                    Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                    $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                    $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                    $outputTextBox.text = ("The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                    
                }  
            }
            return 
        }
        if ($RadioButtonVM.Checked -eq $true)
        {
            if ($deleteCheckBox.Checked -eq $false)
            {
                try
                {
                    $vmpath = $vm.extensiondata.Config.Files.VmPathName
                    $oldname = ($vmpath.Split("]")[0]).substring(1)
                    $vmpath = $vmpath -replace $oldname, $resigds.name 
                    $outputTextBox.text = ("Registering VM from copied datastore...`r`n$($outputTextBox.text)")
                    $newvm = New-VM -VMHost ($vm |Get-VMHost) -VMFilePath $vmpath -Name ("$($vm.Name)-copy") -ErrorAction stop
                    if ($migrateCheckBox.Checked -eq $false)
                    {
                        $outputTextBox.text = ("COMPLETE: A copy of the VM has been `r`n$($outputTextBox.text)")
                    }
                }
                catch
                {
                    $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)")
                    $outputTextBox.text = ("Attempting to cleanup copied datastore...`r`n$($outputTextBox.text)")
                    if ($vms.count -eq 0)
                    {
                        $esxihosts = $resigds |get-vmhost
                        foreach ($esxihost in $esxihosts)
                        {
                            $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                        $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                            $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                        }
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name
                        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                        $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                        $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ("The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                    } 
                    return 
                }
                if ($migrateCheckBox.Checked -eq $true)
                {
                    try
                    {
                        $outputTextBox.text = ("Moving the VM to the original datastore...`r`n$($outputTextBox.text)")
                        Move-vm -vm $newvm -Datastore (get-datastore $oldname) -Confirm:$false -ErrorAction stop
                        $vms = $resigds |get-vm
                        if ($vms.count -eq 0)
                        {
                            $esxihosts = $resigds |get-vmhost
                            foreach ($esxihost in $esxihosts)
                            {
                                $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                            $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                                $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                            }
                            $outputTextBox.text = ("Removing temporary datastore...`r`n$($outputTextBox.text)")
                            Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                            $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                            $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                            $outputTextBox.text = ("COMPLETE: The VM has been moved and the temporary datastore has been deleted`r`n$($outputTextBox.text)")
                        }
                    }
                    catch
                    {
                        $outputTextBox.text = (" $($Error[0])`r`n$($outputTextBox.text)")
                        return
                    }
                }
            }
            elseif ($deleteCheckBox.Checked -eq $true)
            {
                try
                {
                    $vmpath = $vm.extensiondata.Config.Files.VmPathName
                    $oldname = ($vmpath.Split("]")[0]).substring(1)
                    $vmpath = $vmpath -replace $oldname, $resigds.name 
                    if ($vm.ExtensionData.summary.runtime.powerState -eq "poweredOn")
                    {
                        throw "The source VM is powered-on. Please shut it down prior to recovery"
                    }
                    else
                    {
                        $outputTextBox.text = ("Registering VM from copied datastore...`r`n$($outputTextBox.text)")
                        $newvm = New-VM -VMHost ($vm |Get-VMHost) -VMFilePath $vmpath -Name ("$($vm.Name)-copy") -ErrorAction stop
                    }
                    $outputTextBox.text = ("Powering on recovered VM...`r`n$($outputTextBox.text)")
                    $newvm | start-vm -runasync -ErrorAction stop
                    Start-Sleep -Seconds 20
                    $newvm | Get-VMQuestion | Set-VMQuestion -DefaultOption -confirm:$false
                    $outputTextBox.text = ("Removing original VM permanently...`r`n$($outputTextBox.text)")
                    Start-Sleep -Seconds 4
                    $vm |remove-vm -DeletePermanently -Confirm:$false -ErrorAction stop
                    Start-Sleep -Seconds 4
                    $newvm = $newvm | set-vm -name $vm.name -Confirm:$false  -ErrorAction stop
                    $outputTextBox.text = ("COMPLETE: The VM has been recovered and the old VM has been deleted`r`n$($outputTextBox.text)")
                }
                catch
                {
                    $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)")
                    $outputTextBox.text = ("Attempting to cleanup copied datastore...`r`n$($outputTextBox.text)")
                    if ((!$newvm) -ne $true)
                    {
                        $cluster = $newvm |get-cluster
                        $newvm  |remove-vm -DeletePermanently -Confirm:$false
                    }
                    if ($vms.count -eq 0)
                    {
                        $esxihosts = $resigds |get-vmhost
                        foreach ($esxihost in $esxihosts)
                        {
                            $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                        $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                            $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                        }
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name
                        $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                        $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ("The recovery datastore has been deleted`r`n$($outputTextBox.text)") 
                    } 
                    return
                }
                if ($migrateCheckBox.Checked -eq $true)
                {
                    try
                    {
                        $outputTextBox.text = ("Moving the VM to the original datastore...`r`n$($outputTextBox.text)")
                        Move-vm -vm $newvm -Datastore (get-datastore $oldname) -Confirm:$false -ErrorAction stop
                        $vms = $resigds |get-vm
                        if ($vms.count -eq 0)
                        {
                            $esxihosts = $resigds |get-vmhost
                            foreach ($esxihost in $esxihosts)
                            {
                                $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                            $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                                $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                            }
                            Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                            $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                            $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                            $outputTextBox.text = ("COMPLETE: The VM has been moved and the temporary datastore has been deleted`r`n$($outputTextBox.text)")
                        }
                    }
                    catch
                    {
                        $outputTextBox.text = (" $($Error[0])`r`n$($outputTextBox.text)")
                        return
                    }
                }
            }
        }
        if ($RadioButtonVMDK.Checked -eq $true)
        {
            if ($deleteCheckBox.Checked -eq $false)
            {
                try
                {
                    Start-Sleep -Seconds 6
                    $filepath = ($VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                    $filepath = $filepath.Substring(0,$filepath.Length-1)
                    $disk = $vm | get-harddisk |where-object { $_.Filename -eq $filepath } -ErrorAction stop
                    $controller = $disk |Get-ScsiController -ErrorAction stop
                    $oldname = ($filepath.Split("]")[0]).substring(1)
                    $filepath = $filepath -replace $oldname, $resigds.name
                    $outputTextBox.text = ("$($filepath)`r`n$($outputTextBox.text)")
                    $outputTextBox.text = ("Adding VMDK from copied datastore...`r`n$($outputTextBox.text)")
                    $oldUUID = $vdm = get-view -id (get-view serviceinstance).content.virtualdiskmanager
                    $dc=$vm |get-datacenter 
                    $oldUUID=$vdm.queryvirtualdiskuuid($filePath, $dc.id)
                    $firstHalf = $oldUUID.split("-")[0]
                    $testguid=[Guid]::NewGuid()
                    $strGuid=[string]$testguid
                    $arrGuid=$strGuid.split("-")
                    $secondHalfTemp=$arrGuid[3]+$arrGuid[4]
                    $halfUUID=$secondHalfTemp[0]+$secondHalfTemp[1]+" "+$secondHalfTemp[2]+$secondHalfTemp[3]+" "+$secondHalfTemp[4]+$secondHalfTemp[5]+" "+$secondHalfTemp[6]+$secondHalfTemp[7]+" "+$secondHalfTemp[8]+$secondHalfTemp[9]+" "+$secondHalfTemp[10]+$secondHalfTemp[11]+" "+$secondHalfTemp[12]+$secondHalfTemp[13]+" "+$secondHalfTemp[14]+$secondHalfTemp[15]
                    $vdm.setVirtualDiskUuid($filePath, $dc.id, $firstHalf+"-"+$halfUUID)
                    $newDisk = $vm | new-harddisk -DiskPath $filepath -Controller $controller -ErrorAction stop
                    $outputTextBox.text = ("COMPLETE: VMDK copy added to VM.`r`n$($outputTextBox.text)")
                }
                catch
                {
                    $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)")
                    $outputTextBox.text = ("Attempting to cleanup copied datastore...`r`n$($outputTextBox.text)")
                    if ($vms.count -eq 0)
                    {
                        $esxihosts = $resigds |get-vmhost
                        foreach ($esxihost in $esxihosts)
                        {
                            $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                        $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                            $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                        }
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                        $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                        $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ("The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                    } 
                    return
                }
                if ($migrateCheckBox.Checked -eq $true)
                {
                    try
                    {
                        $outputTextBox.text = ("Moving the VMDK to the original datastore...`r`n$($outputTextBox.text)")
                        Move-HardDisk -HardDisk $newDisk -Datastore (get-datastore $oldname) -Confirm:$false -ErrorAction stop
                        $vms = $resigds |get-vm
                        if ($vms.count -eq 0)
                        {
                            $esxihosts = $resigds |get-vmhost
                            foreach ($esxihost in $esxihosts)
                            {
                                $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                            $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                                $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                            }
                            $outputTextBox.text = ("Removing copied datastore...`r`n$($outputTextBox.text)")
                            Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                            $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                            $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                            $outputTextBox.text = ("COMPLETE: The VMDK has been moved and the temporary datastore has been deleted`r`n$($outputTextBox.text)")
                        }
                    }
                    catch
                    {
                        $outputTextBox.text = (" $($Error[0])`r`n$($outputTextBox.text)")
                        return
                    }
                }
            }
            elseif ($deleteCheckBox.Checked -eq $true)
            {
                try
                {
                    $filepath = ($VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                    $filepath = $filepath.Substring(0,$filepath.Length-1)
                    $disk = $vm | get-harddisk |where-object { $_.Filename -eq $filepath } -ErrorAction stop
                    $controller = $disk |Get-ScsiController -ErrorAction stop
                    $oldname = ($filepath.Split("]")[0]).substring(1)
                    $filepath = $filepath -replace $oldname, $resigds.name
                    $outputTextBox.text = ("Removing old VMDK from VM...`r`n$($outputTextBox.text)")
                    $disk | remove-harddisk -DeletePermanently -Confirm:$false -ErrorAction stop
                    $outputTextBox.text = ("Replacing VMDK from copied datastore...`r`n$($outputTextBox.text)")
                    $newDisk = $vm | new-harddisk -DiskPath $filepath -Controller $controller -ErrorAction stop
                    $outputTextBox.text = ("COMPLETE: VMDK replaced and restored.`r`n$($outputTextBox.text)")
                }
                catch
                {
                    $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)")
                    $outputTextBox.text = ("Attempting to cleanup recovered datastore...`r`n$($outputTextBox.text)")
                    if ($vms.count -eq 0)
                    {
                        $esxihosts = $resigds |get-vmhost
                        foreach ($esxihost in $esxihosts)
                        {
                            $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                        $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                            $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                        }
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                        $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                        $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ("The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                    } 
                    return
                }
                if ($migrateCheckBox.Checked -eq $true)
                {
                    try
                    {
                        $outputTextBox.text = ("Moving the VM to the original datastore...`r`n$($outputTextBox.text)")
                        Move-HardDisk -HardDisk $newDisk -Datastore (get-datastore $oldname) -Confirm:$false -ErrorAction stop
                        $vms = $resigds |get-vm
                        if ($vms.count -eq 0)
                        {
                            $esxihosts = $resigds |get-vmhost
                            foreach ($esxihost in $esxihosts)
                            {
                                $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	                            $StorageSystem.UnmountVmfsVolume($resigds.ExtensionData.Info.vmfs.uuid) 
                                $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $resigds.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
                            }
                            $outputTextBox.text = ("Removing copied datastore...`r`n$($outputTextBox.text)")
                            Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                            $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                            $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                            $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
                            $outputTextBox.text = ("The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                        }
                    }
                    catch
                    {
                        $outputTextBox.text = (" $($Error[0])`r`n$($outputTextBox.text)")
                        return
                    }
                }
            }
        }
    }
    if ($RadioButtonRDM.Checked -eq $true)
    {
        if ($deleteCheckBox.Checked -eq $true)
        {
            try
            {
                $outputTextBox.text = ("Refreshing RDM...`r`n$($outputTextBox.text)")
                $snapshotchoice = $SnapshotDropDownBox.SelectedIndex
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
                $naa = (($RDMDropDownBox.SelectedItem.ToString()).substring(0,36))
                $disk = $vm | get-harddisk |where-object { $_.ScsiCanonicalName -eq $naa } -ErrorAction stop
                $controller = $disk |Get-ScsiController -ErrorAction stop 
                $outputTextBox.text = ("Temporarily removing RDM from VM...`r`n$($outputTextBox.text)")
                $disk |remove-harddisk -Confirm:$false -DeletePermanently -ErrorAction stop
                $outputTextBox.text = ("Removing RDM from VM...`r`n$($outputTextBox.text)") 
                $outputTextBox.text = ("Refreshing RDM from snapshot...`r`n$($outputTextBox.text)")
                $newvol = New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $purevol.name -Overwrite
                $outputTextBox.text = ("Adding RDM back to VM...`r`n$($outputTextBox.text)") 
                $vm | new-harddisk -DeviceName "/vmfs/devices/disks/$($naa.toLower())" -DiskType RawPhysical -Controller $controller   -ErrorAction stop
                $outputTextBox.text = ("Added RDM back to VM.`r`n$($outputTextBox.text)") 
                $outputTextBox.text = "COMPLETE: Refreshed RDM on FlashArray volume $($newvol.name) from snapshot $($snapshots[$snapshotchoice].name) `r`n $($outputTextBox.text)"
            }
            catch
            {
                $outputTextBox.text = "Failed to refresh RDM on FlashArray volume $($newvol.name) from snapshot $($snapshots[$snapshotchoice].name) `r`n $($outputTextBox.text)"
                $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
                return
            }
        }
        else
        {
            getHostGroup
            try
            {
                $snapshotchoice = $SnapshotDropDownBox.SelectedIndex
                $volumename = $purevol.name + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
                $newvol =New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $volumename
                $outputTextBox.text = ("Creating new volume from snapshot...`r`n$($outputTextBox.text)")
                New-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
                Start-sleep -s 5
                $recoverylun = ("naa.624a9370" + $newvol.serial)
                $naa = (($RDMDropDownBox.SelectedItem.ToString()).substring(0,36))
                $outputTextBox.text = (" $($naa)`r`n$($outputTextBox.text)") 
                $disk = $vm | get-harddisk |where-object { $_.ScsiCanonicalName -eq $naa }  -ErrorAction stop
                $controller = $disk |Get-ScsiController -ErrorAction stop
                $outputTextBox.text = ("Adding copied RDM to VM...`r`n$($outputTextBox.text)")
                $vm | new-harddisk -DeviceName "/vmfs/devices/disks/$($recoverylun.toLower())" -DiskType RawPhysical -Controller $controller  -ErrorAction stop
                $outputTextBox.text = "COMPLETE: Cloned RDM to FlashArray volume $($newvol.name) from snapshot $($snapshots[$snapshotchoice].name) and added to VM named $($vm.name) `r`n $($outputTextBox.text)" 
            }
            catch
            {
                $outputTextBox.text = ("Error occurred, removing volume...`r`n$($outputTextBox.text)")
                Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                $outputTextBox.text = ("Rescanning cluster...`r`n$($outputTextBox.text)")
                $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                $outputTextBox.text = ("$($Error[0])`r`n$($outputTextBox.text)") 
                return
            }
        }
    }
}
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
##################Main Form Definition
    
    $main_form = New-Object System.Windows.Forms.Form 
    $main_form.Text = "Pure Storage VMware Recovery Tool" #Form Title
    $main_form.Size = New-Object System.Drawing.Size(500,1000) 
    $main_form.StartPosition = "CenterScreen"
    $main_form.KeyPreview = $True
    $main_form.AutoScroll = $True
    $main_form.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
    {$main_form.Close()}})

##################GroupBox Definition

    $groupBoxVC = New-Object System.Windows.Forms.GroupBox
    $groupBoxVC.Location = New-Object System.Drawing.Size(10,5) 
    $groupBoxVC.size = New-Object System.Drawing.Size(170,200) 
    $groupBoxVC.text = "Connect to vCenter:" 
    $main_form.Controls.Add($groupBoxVC) 

    $groupBoxFA = New-Object System.Windows.Forms.GroupBox
    $groupBoxFA.Location = New-Object System.Drawing.Size(190,5) 
    $groupBoxFA.size = New-Object System.Drawing.Size(170,200) 
    $groupBoxFA.text = "Connect to FlashArray:" 
    $main_form.Controls.Add($groupBoxFA)

    $groupBoxInfo = New-Object System.Windows.Forms.GroupBox
    $groupBoxInfo.Location = New-Object System.Drawing.Size(370,5) 
    $groupBoxInfo.size = New-Object System.Drawing.Size(110,200) 
    $groupBoxInfo.text = "About:" 
    $main_form.Controls.Add($groupBoxInfo)

    $groupBoxRadio = New-Object System.Windows.Forms.GroupBox
    $groupBoxRadio.Location = New-Object System.Drawing.Size(10,210) 
    $groupBoxRadio.size = New-Object System.Drawing.Size(470,120) 
    $groupBoxRadio.text = "Choose Recovery Option:" 
    $main_form.Controls.Add($groupBoxRadio) 

    $groupBoxVMFS = New-Object System.Windows.Forms.GroupBox
    $groupBoxVMFS.Location = New-Object System.Drawing.Size(10,335) 
    $groupBoxVMFS.size = New-Object System.Drawing.Size(470,100) 
    $groupBoxVMFS.text = "Datastore Selection:" 
    $main_form.Controls.Add($groupBoxVMFS) 

    $groupBoxVM = New-Object System.Windows.Forms.GroupBox
    $groupBoxVM.Location = New-Object System.Drawing.Size(10,440) 
    $groupBoxVM.size = New-Object System.Drawing.Size(470,170) 
    $groupBoxVM.text = "Virtual Machine Selection:" 
    $main_form.Controls.Add($groupBoxVM) 

    $groupBoxLog = New-Object System.Windows.Forms.GroupBox
    $groupBoxLog.Location = New-Object System.Drawing.Size(10,805) 
    $groupBoxLog.size = New-Object System.Drawing.Size(470,145) 
    $groupBoxLog.text = "Output:" 
    $main_form.Controls.Add($groupBoxLog)

    $groupBoxSnapshot = New-Object System.Windows.Forms.GroupBox
    $groupBoxSnapshot.Location = New-Object System.Drawing.Size(10,615) 
    $groupBoxSnapshot.size = New-Object System.Drawing.Size(470,90) 
    $groupBoxSnapshot.text = "Create Snapshot:" 
    $main_form.Controls.Add($groupBoxSnapshot)
    
    $groupBoxRecover = New-Object System.Windows.Forms.GroupBox
    $groupBoxRecover.Location = New-Object System.Drawing.Size(10,710) 
    $groupBoxRecover.size = New-Object System.Drawing.Size(470,90) 
    $groupBoxRecover.text = "Recover:" 
    $main_form.Controls.Add($groupBoxRecover)


 ##################Radio Definition   
    
    $RadioButtonVMFS = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonVMFS.Location = new-object System.Drawing.Point(15,15) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonVMFS.size = New-Object System.Drawing.Size(60,20) #the size in px of the radio button (length, height)
    $RadioButtonVMFS.Checked = $true #is checked by default
    $RadioButtonVMFS.Text = "VMFS" #labeling the radio button
    $RadioButtonVMFS.Enabled = $false
    $RadioButtonVMFS.add_CheckedChanged({radioSelect})
    $groupBoxRadio.Controls.Add($RadioButtonVMFS) #activate the inside the group box

    $RadioButtonVM = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonVM.Location = new-object System.Drawing.Point(80,15) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonVM.size = New-Object System.Drawing.Size(100,20) #the size in px of the radio button (length, height)
    $RadioButtonVM.Text = "Virtual Machine" #labeling the radio button
    $RadioButtonVM.Enabled = $false
    $RadioButtonVM.add_CheckedChanged({radioSelect})
    $groupBoxRadio.Controls.Add($RadioButtonVM) #activate the inside the group box

    $RadioButtonVMDK = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonVMDK.Location = new-object System.Drawing.Point(190,15) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonVMDK.size = New-Object System.Drawing.Size(80,20) #the size in px of the radio button (length, height)
    $RadioButtonVMDK.Text = "Virtual Disk" #labeling the radio button
    $RadioButtonVMDK.Enabled = $false
    $RadioButtonVMDK.add_CheckedChanged({radioSelect})
    $groupBoxRadio.Controls.Add($RadioButtonVMDK) #activate the inside the group box

    $RadioButtonRDM = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonRDM.Location = new-object System.Drawing.Point(280,15) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonRDM.size = New-Object System.Drawing.Size(150,20) #the size in px of the radio button (length, height)
    $RadioButtonRDM.Text = "Raw Device Mapping" #labeling the radio button
    $RadioButtonRDM.Enabled = $false
    $RadioButtonRDM.add_CheckedChanged({radioSelect})
    $groupBoxRadio.Controls.Add($RadioButtonRDM) #activate the inside the group box

##################Label Definition

    $LabelVC = New-Object System.Windows.Forms.Label
    $LabelVC.Location = New-Object System.Drawing.Point(10, 20)
    $LabelVC.Size = New-Object System.Drawing.Size(120, 14)
    $LabelVC.Text = "IP Address or FQDN:"
    $groupBoxVC.Controls.Add($LabelVC) 

    $LabelVCuser = New-Object System.Windows.Forms.Label
    $LabelVCuser.Location = New-Object System.Drawing.Point(10, 70)
    $LabelVCuser.Size = New-Object System.Drawing.Size(120, 14)
    $LabelVCuser.Text = "Username:"
    $groupBoxVC.Controls.Add($LabelVCuser) 

    $LabelVCpass = New-Object System.Windows.Forms.Label
    $LabelVCpass.Location = New-Object System.Drawing.Point(10, 120)
    $LabelVCpass.Size = New-Object System.Drawing.Size(120, 14)
    $LabelVCpass.Text = "Password:"
    $groupBoxVC.Controls.Add($LabelVCpass) 
          
    $LabelFA = New-Object System.Windows.Forms.Label
    $LabelFA.Location = New-Object System.Drawing.Point(10, 20)
    $LabelFA.Size = New-Object System.Drawing.Size(120, 14)
    $LabelFA.Text = "IP Address or FQDN:"
    $groupBoxFA.Controls.Add($LabelFA)
    
    $LabelFAuser = New-Object System.Windows.Forms.Label
    $LabelFAuser.Location = New-Object System.Drawing.Point(10, 70)
    $LabelFAuser.Size = New-Object System.Drawing.Size(120, 14)
    $LabelFAuser.Text = "Username:"
    $groupBoxFA.Controls.Add($LabelFAuser) 

    $LabelFApass = New-Object System.Windows.Forms.Label
    $LabelFApass.Location = New-Object System.Drawing.Point(10, 120)
    $LabelFApass.Size = New-Object System.Drawing.Size(120, 14)
    $LabelFApass.Text = "Password:"
    $groupBoxFA.Controls.Add($LabelFApass) 

    $LabelAbout = New-Object System.Windows.Forms.Label
    $LabelAbout.Location = New-Object System.Drawing.Point(10, 20)
    $LabelAbout.Size = New-Object System.Drawing.Size(90, 170)
    $LabelAbout.Text = "Version 1.0.1`r`n`r`nBy Cody Hosterman`r`n`r`nRequires:`r`n-----------------`r`nVMware PowerCLI 6.3+`r`n`r`nPure Storage PowerShell SDK 1.7+"
    $groupBoxInfo.Controls.Add($LabelAbout)  

    $LabelClusterFilter = New-Object System.Windows.Forms.Label
    $LabelClusterFilter.Location = New-Object System.Drawing.Point(10, 52)
    $LabelClusterFilter.Size = New-Object System.Drawing.Size(80, 14)
    $LabelClusterFilter.Text = "Cluster Filter:"
    $groupBoxRadio.Controls.Add($LabelClusterFilter)  

    $LabelNameFilter = New-Object System.Windows.Forms.Label
    $LabelNameFilter.Location = New-Object System.Drawing.Point(10, 87)
    $LabelNameFilter.Size = New-Object System.Drawing.Size(70, 14)
    $LabelNameFilter.Text = "Name Filter:"
    $groupBoxRadio.Controls.Add($LabelNameFilter)

    $LabelVMDK = New-Object System.Windows.Forms.Label
    $LabelVMDK.Location = New-Object System.Drawing.Point(10, 65)
    $LabelVMDK.Size = New-Object System.Drawing.Size(80, 14)
    $LabelVMDK.Text = "Virtual Disks:"
    $groupBoxVM.Controls.Add($LabelVMDK)

    $LabelCluster = New-Object System.Windows.Forms.Label
    $LabelCluster.Location = New-Object System.Drawing.Point(10, 65)
    $LabelCluster.Size = New-Object System.Drawing.Size(100, 14)
    $LabelCluster.Text = "Recovery Cluster:"
    $groupBoxVMFS.Controls.Add($LabelCluster)

    $LabelRDM = New-Object System.Windows.Forms.Label
    $LabelRDM.Location = New-Object System.Drawing.Point(10, 105)
    $LabelRDM.Size = New-Object System.Drawing.Size(80, 14)
    $LabelRDM.Text = "RDMs:"
    $groupBoxVM.Controls.Add($LabelRDM)

    $LabelNewSnap = New-Object System.Windows.Forms.Label
    $LabelNewSnap.Location = New-Object System.Drawing.Point(10, 25)
    $LabelNewSnap.Size = New-Object System.Drawing.Size(120, 14)
    $LabelNewSnap.Text = "New snapshot name:"
    $groupBoxSnapshot.Controls.Add($LabelNewSnap)

    $LabelNewSnapError = New-Object System.Windows.Forms.Label
    $LabelNewSnapError.Location = New-Object System.Drawing.Point(145, 60)
    $LabelNewSnapError.Size = New-Object System.Drawing.Size(320, 14)
    $LabelNewSnapError.Text = ""
    $groupBoxSnapshot.Controls.Add($LabelNewSnapError)

##################Button Definition

    $buttonConnect = New-Object System.Windows.Forms.Button
    $buttonConnect.add_click({connectServer})
    $buttonConnect.Text = "Connect"
    $buttonConnect.Top=170
    $buttonConnect.Left=7
    $buttonConnect.Enabled = $false #Disabled by default
    $groupBoxVC.Controls.Add($buttonConnect) #Member of groupBoxVC

    $buttonDisconnect = New-Object System.Windows.Forms.Button
    $buttonDisconnect.add_click({disconnectServer})
    $buttonDisconnect.Text = "Disconnect"
    $buttonDisconnect.Top=170
    $buttonDisconnect.Left=88
    $buttonDisconnect.Enabled = $false #Disabled by default
    $groupBoxVC.Controls.Add($buttonDisconnect) #Member of groupBoxVC

    $buttonDatastores = New-Object System.Windows.Forms.Button
    $buttonDatastores.add_click({getDatastores})
    $buttonDatastores.Text = "Get Datastores"
    $buttonDatastores.Top=23
    $buttonDatastores.Left=10
    $buttonDatastores.Width=120
    $buttonDatastores.Enabled = $false #Disabled by default
    $groupBoxVMFS.Controls.Add($buttonDatastores)

    $buttonVMs = New-Object System.Windows.Forms.Button
    $buttonVMs.add_click({getVMs})
    $buttonVMs.Text = "Get Virtual Machines"
    $buttonVMs.Top=24
    $buttonVMs.Left=10
    $buttonVMs.Width=120
    $buttonVMs.Enabled = $false #Disabled by default
    $groupBoxVM.Controls.Add($buttonVMs) 
    
    $buttonSnapshots = New-Object System.Windows.Forms.Button
    $buttonSnapshots.add_click({getSnapshots})
    $buttonSnapshots.Text = "Gather Snapshots"
    $buttonSnapshots.Top=20
    $buttonSnapshots.Left=10
    $buttonSnapshots.Width=120
    $buttonSnapshots.Enabled = $false #Disabled by default
    $groupBoxRecover.Controls.Add($buttonSnapshots) 

    $buttonNewSnapshot = New-Object System.Windows.Forms.Button
    $buttonNewSnapshot.add_click({newSnapshot})
    $buttonNewSnapshot.Text = "Create Snapshot"
    $buttonNewSnapshot.Top=55
    $buttonNewSnapshot.Left=20
    $buttonNewSnapshot.Width=120
    $buttonNewSnapshot.Enabled = $false #Disabled by default
    $groupBoxSnapshot.Controls.Add($buttonNewSnapshot) 
    
    $buttonRecover = New-Object System.Windows.Forms.Button
    $buttonRecover.add_click({recoverObject})
    $buttonRecover.Text = "EXECUTE"
    $buttonRecover.Top=55
    $buttonRecover.Left=180
    $buttonRecover.Width=120
    $buttonRecover.Enabled = $false #Disabled by default
    $groupBoxRecover.Controls.Add($buttonRecover) 

    $flasharrayButtonConnect = New-Object System.Windows.Forms.Button
    $flasharrayButtonConnect.add_click({connectFlashArray})
    $flasharrayButtonConnect.Text = "Connect"
    $flasharrayButtonConnect.Top=170
    $flasharrayButtonConnect.Left=7
    $flasharrayButtonConnect.Enabled = $false #Disabled by default
    $groupBoxFA.Controls.Add($flasharrayButtonConnect) #Member of groupBoxFA

    $flasharrayButtonDisconnect = New-Object System.Windows.Forms.Button
    $flasharrayButtonDisconnect.add_click({disconnectFlashArray})
    $flasharrayButtonDisconnect.Text = "Disconnect"
    $flasharrayButtonDisconnect.Top=170
    $flasharrayButtonDisconnect.Left=88
    $flasharrayButtonDisconnect.Enabled = $false #Disabled by default
    $groupBoxFA.Controls.Add($flasharrayButtonDisconnect) #Member of groupBoxFA


##################TextBox Definition

    $serverTextBox = New-Object System.Windows.Forms.TextBox 
    $serverTextBox.Location = New-Object System.Drawing.Size(10,40)
    $serverTextBox.Size = New-Object System.Drawing.Size(145,20)
    $serverTextBox.add_TextChanged({isVCTextChanged}) 
    $groupBoxVC.Controls.Add($serverTextBox) 

    $usernameTextBox = New-Object System.Windows.Forms.TextBox 
    $usernameTextBox.Location = New-Object System.Drawing.Size(10,90)
    $usernameTextBox.Size = New-Object System.Drawing.Size(145,20) 
    $usernameTextBox.add_TextChanged({isVCTextChanged}) 
    $groupBoxVC.Controls.Add($usernameTextBox) 

    $passwordTextBox = New-Object System.Windows.Forms.MaskedTextBox
    $passwordTextBox.PasswordChar = '*'
    $passwordTextBox.Location = New-Object System.Drawing.Size(10,140)
    $passwordTextBox.Size = New-Object System.Drawing.Size(145,20)
    $passwordTextBox.add_TextChanged({isVCTextChanged}) 
    $groupBoxVC.Controls.Add($passwordTextBox) 

    $outputTextBox = New-Object System.Windows.Forms.TextBox 
    $outputTextBox.Location = New-Object System.Drawing.Size(10,20)
    $outputTextBox.Size = New-Object System.Drawing.Size(450,115)
    $outputTextBox.MultiLine = $True 
    $outputTextBox.ReadOnly = $True
    $outputTextBox.ScrollBars = "Vertical"
    $outputTextBox.text = ""  
    $groupBoxLog.Controls.Add($outputTextBox) 

    $flasharrayTextBox = New-Object System.Windows.Forms.TextBox 
    $flasharrayTextBox.Location = New-Object System.Drawing.Size(10,40)
    $flasharrayTextBox.Size = New-Object System.Drawing.Size(145,20) 
    $flasharrayTextBox.add_TextChanged({isFATextChanged}) 
    $groupBoxFA.Controls.Add($flasharrayTextBox) 

    $newSnapshotTextBox = New-Object System.Windows.Forms.TextBox 
    $newSnapshotTextBox.Location = New-Object System.Drawing.Size(140,21)
    $newSnapshotTextBox.Size = New-Object System.Drawing.Size(320,20) 
    $newSnapshotTextBox.add_TextChanged({isSnapshotTextChanged}) 
    $newSnapshotTextBox.Enabled = $false
    $groupBoxSnapshot.Controls.Add($newSnapshotTextBox) 

    $flasharrayUsernameTextBox = New-Object System.Windows.Forms.TextBox 
    $flasharrayUsernameTextBox.Location = New-Object System.Drawing.Size(10,90)
    $flasharrayUsernameTextBox.Size = New-Object System.Drawing.Size(145,20)
    $flasharrayUsernameTextBox.add_TextChanged({isFATextChanged}) 
    $groupBoxFA.Controls.Add($flasharrayUsernameTextBox) 

    $flasharrayPasswordTextBox = New-Object System.Windows.Forms.MaskedTextBox
    $flasharrayPasswordTextBox.PasswordChar = '*'
    $flasharrayPasswordTextBox.Location = New-Object System.Drawing.Size(10,140)
    $flasharrayPasswordTextBox.Size = New-Object System.Drawing.Size(145,20)
    $flasharrayPasswordTextBox.add_TextChanged({isFATextChanged})    
    $groupBoxFA.Controls.Add($flasharrayPasswordTextBox) 

    $nameFilterTextBox = New-Object System.Windows.Forms.MaskedTextBox
    $nameFilterTextBox.Location = New-Object System.Drawing.Size(100,87)
    $nameFilterTextBox.Size = New-Object System.Drawing.Size(360,20)
    $nameFilterTextBox.Enabled = $false
    $nameFilterTextBox.add_TextChanged({nameFilterChanged})
    $groupBoxRadio.Controls.Add($nameFilterTextBox) 
    
##################CheckBox Definition

    $deleteCheckBox = new-object System.Windows.Forms.checkbox
    $deleteCheckBox.Location = new-object System.Drawing.Size(30,140)
    $deleteCheckBox.Size = new-object System.Drawing.Size(200,20)
    $deleteCheckBox.Text = "Replace original VM/VMDK/RDM"
    $deleteCheckBox.Checked = $false
    $deleteCheckBox.Enabled = $false
    $groupBoxVM.Controls.Add($deleteCheckBox) 

    $migrateCheckBox = new-object System.Windows.Forms.checkbox
    $migrateCheckBox.Location = new-object System.Drawing.Size(230,140)
    $migrateCheckBox.Size = new-object System.Drawing.Size(230,20)
    $migrateCheckBox.Text = "Storage vMotion back to source VMFS"
    $migrateCheckBox.Checked = $false
    $migrateCheckBox.Enabled = $false
    $groupBoxVM.Controls.Add($migrateCheckBox) 

##################DropDownBox Definition

    $DatastoreDropDownBox = New-Object System.Windows.Forms.ComboBox
    $DatastoreDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $DatastoreDropDownBox.Location = New-Object System.Drawing.Size(140,24) 
    $DatastoreDropDownBox.Size = New-Object System.Drawing.Size(320,20) 
    $DatastoreDropDownBox.DropDownHeight = 200
    $DatastoreDropDownBox.Enabled=$false 
    $DatastoreDropDownBox.add_SelectedIndexChanged({datastoreSelectionChanged})
    $groupBoxVMFS.Controls.Add($DatastoreDropDownBox)

    $VMDropDownBox = New-Object System.Windows.Forms.ComboBox
    $VMDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $VMDropDownBox.Location = New-Object System.Drawing.Size(140,25) 
    $VMDropDownBox.Size = New-Object System.Drawing.Size(320,20) 
    $VMDropDownBox.DropDownHeight = 200
    $VMDropDownBox.Enabled=$false
    $VMDropDownBox.add_SelectedIndexChanged({getDisks}) 
    $groupBoxVM.Controls.Add($VMDropDownBox)

    $VMDKDropDownBox = New-Object System.Windows.Forms.ComboBox
    $VMDKDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $VMDKDropDownBox.Location = New-Object System.Drawing.Size(90,65) 
    $VMDKDropDownBox.Size = New-Object System.Drawing.Size(370,20) 
    $VMDKDropDownBox.DropDownHeight = 200
    $VMDKDropDownBox.Enabled=$false 
    $groupBoxVM.Controls.Add($VMDKDropDownBox)

    $RDMDropDownBox = New-Object System.Windows.Forms.ComboBox
    $RDMDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $RDMDropDownBox.Location = New-Object System.Drawing.Size(90,105) 
    $RDMDropDownBox.Size = New-Object System.Drawing.Size(370,20) 
    $RDMDropDownBox.DropDownHeight = 200
    $RDMDropDownBox.Enabled=$false 
    $groupBoxVM.Controls.Add($RDMDropDownBox)
    
    $ClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $ClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $ClusterDropDownBox.Location = New-Object System.Drawing.Size(100,50) 
    $ClusterDropDownBox.Size = New-Object System.Drawing.Size(360,20) 
    $ClusterDropDownBox.DropDownHeight = 200
    $ClusterDropDownBox.Enabled=$false 
    $ClusterDropDownBox.add_SelectedIndexChanged({clusterSelectionChanged})
    $groupBoxRadio.Controls.Add($ClusterDropDownBox)

    $RecoveryClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $RecoveryClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $RecoveryClusterDropDownBox.Location = New-Object System.Drawing.Size(140,60) 
    $RecoveryClusterDropDownBox.Size = New-Object System.Drawing.Size(320,20) 
    $RecoveryClusterDropDownBox.DropDownHeight = 200
    $RecoveryClusterDropDownBox.Enabled=$false 
    $groupBoxVMFS.Controls.Add($RecoveryClusterDropDownBox)
    
    $SnapshotDropDownBox = New-Object System.Windows.Forms.ComboBox
    $SnapshotDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $SnapshotDropDownBox.Location = New-Object System.Drawing.Size(140,20) 
    $SnapshotDropDownBox.Size = New-Object System.Drawing.Size(320,20) 
    $SnapshotDropDownBox.DropDownHeight = 200
    $SnapshotDropDownBox.Enabled=$false
    $groupBoxRecover.Controls.Add($SnapshotDropDownBox)

##################Show Form

    $main_form.Add_Shown({$main_form.Activate()})
    [void] $main_form.ShowDialog()