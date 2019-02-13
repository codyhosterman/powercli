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
-PowerCLI 6.5 Release 1+
-Purity 4.8 and later
-FlashArray 400 Series and //m and //x
-vCenter 6.0 and later

'Pure Storage FlashArray VMware Snapshot Recovery Tool v2.8.1'
#>
#Import PowerCLI. Requires PowerCLI version 6.3 or later. Will fail here if PowerCLI is not installed
#Will try to install PowerCLI with PowerShellGet if PowerCLI is not present.

if ((!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable))) {
    if (Test-Path "C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1")
    {
      . "C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1" |out-null
    }
    elseif (Test-Path "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1")
    {
        . "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1" |out-null
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
#Set
$EndPoint = $null
$Endpoints = @()
$ErrorActionPreference = "Stop"
#Connection Functions
function connectServer{
    try 
    {
        $connect = Connect-VIServer -Server $serverTextBox.Text -User $usernameTextBox.Text -Password $passwordTextBox.Text -ErrorAction stop
        $buttonConnect.Enabled = $false #Disable controls once connected
        $serverTextBox.Enabled = $false
        $usernameTextBox.Enabled = $false
        $passwordTextBox.Enabled = $false
        $buttonDisconnect.Enabled = $true #Enable Disconnect button
        $outputTextBox.text = ((get-Date -Format G) + " Successfully connected to vCenter $($serverTextBox.Text)`r`n$($outputTextBox.text)")
        if (($endpoints.count -ge 1) -and ($buttonDisconnect.Enabled = $true))
        {
            getClusters
            enableObjects
            $TabControl.Enabled = $true
        }
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function disconnectServer{
    try 
    {
        $disconnect = Disconnect-VIServer -Server $serverTextBox.Text -Confirm:$false -Force:$true -ErrorAction stop
        $buttonConnect.Enabled = $true #Enable login controls once disconnected
        $serverTextBox.Enabled = $true
        $usernameTextBox.Enabled = $true
        $passwordTextBox.Enabled = $true
        $buttonDisconnect.Enabled = $false #Disable Disconnect button
        $outputTextBox.text = (get-Date -Format G) + " Successfully disconnected from vCenter $($serverTextBox.Text)`r`n" + $outputTextBox.text
        disableObjects
        $TabControl.Enabled = $false
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function connectFlashArray{
   
    try
    {
        $FApassword = convertto-securestring $flasharrayPasswordTextBox.Text -asplaintext -force
        $script:EndPoints += New-PfaArray -EndPoint $flasharrayTextBox.Text -Username $flasharrayUsernameTextBox.Text -Password $FApassword -IgnoreCertificateError -ErrorAction stop
        $outputTextBox.text = (get-Date -Format G) + " Successfully connected to FlashArray $($flasharrayTextBox.Text)" + ("`r`n") + $outputTextBox.text
        $newArray = Get-PfaArrayAttributes -Array $endpoints[-1]
        $FAisValid = $true
        for ($i=0;$i -lt ($endpoints.count - 1);$i++)
        {
             $currentArray = Get-PfaArrayAttributes -Array $endpoints[$i]
             if ($currentArray.id -eq $newArray.id)
             {
                $outputTextBox.text = (get-Date -Format G) + " ERROR: Will not connect this FlashArray. This FlashArray is already registered under the IP/FQDN of $($endpoints[$i].endpoint)" + ("`r`n") + $outputTextBox.text
                $FAisValid = $false

             }
        }
        if ($FAisValid -eq $false)
        {
            disconnectFlashArray
        }
        else
        {
            $flasharrayButtonConnect.enabled = $false
            $flasharrayButtonDisconnect.enabled = $true
            $flasharrayTextBox.Enabled = $false
            $flasharrayUsernameTextBox.Enabled = $false
            $flasharrayPasswordTextBox.Enabled = $false
            $FlashArrayDropDownBox.Items.Add($flasharrayTextBox.Text)
            $flasharrayPasswordTextBox.Text = ""
            $flasharrayUsernameTextBox.Text = ""
            $FlashArrayDropDownBox.Enabled=$true
            $FlashArrayDropDownBox.SelectedIndex = $endpoints.count
            if (($endpoints.count -eq 1) -and ($buttonDisconnect.Enabled -eq $true))
            {
                getClusters
                enableObjects
                $TabControl.Enabled = $true
            }
             elseif (($endpoints.count -gt 1) -and ($buttonDisconnect.Enabled -eq $true))
            {
                listFlashArrays
            }
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " Connection to FlashArray " + $flasharrayTextBox.Text + " failed. Please check credentials or IP/FQDN") + ("`r`n") + $outputTextBox.text
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function disconnectFlashArray{
    try
    {
        foreach ($EndPoint in $Endpoints)
        {
            if ($endpoint.endpoint-eq $flasharrayTextBox.Text)
            {
                break
            }
        }
        Disconnect-PfaArray -Array $EndPoint -ErrorAction stop
        $script:endpoints = $endpoints -ne $endpoint
        $outputTextBox.text = ((get-Date -Format G) + " Successfully disconnected from FlashArray " + $flasharrayTextBox.Text) + ("`r`n") + $outputTextBox.text
        $FlashArrayDropDownBox.Items.Remove($flasharrayTextBox.Text)
        $FlashArrayDropDownBox.SelectedIndex = $endpoints.count
        if ($Endpoints.count -eq 0)
        {
            $RadioButtonVM.Enabled = $false
            $RadioButtonVMDK.Enabled = $false
            $RadioButtonRDM.Enabled = $false
        }
        if (($endpoints.count -ge 1) -and ($buttonDisconnect.Enabled = $true))
        {
            listFlashArrays
        }
        if (($endpoints.count -eq 0))
        {
            disableObjects
            $TabControl.Enabled = $false
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " Disconnection from FlashArray " + $flasharrayTextBox.Text + " failed.") + ("`r`n") + $outputTextBox.text
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
#Inventory Functions
function getDatastores{
    
    try 
    {
        $DatastoreDropDownBox.Items.Clear()
        if ($ClusterDropDownBox.SelectedItem.ToString() -eq "<All Clusters>")
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $datastores = get-datastore -Name ("*" + $nameFilterTextBox.Text + "*") | where-object {$_.Type -eq "VMFS"}
            }
            else
            {
                $datastores = get-datastore | where-object {$_.Type -eq "VMFS"}
            }
        }
        else
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $datastores = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() |get-datastore -Name ("*" + $nameFilterTextBox.Text + "*") | where-object {$_.Type -eq "VMFS"}
            }
            else
            {
                $datastores = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() |get-datastore | where-object {$_.Type -eq "VMFS"}
            }
        }
        if ($datastores.count -ge 1)
        {
            $DatastoreDropDownBox.Enabled=$true
            $DatastoreDropDownBox.Items.Add("Choose VMFS...")
            foreach ($datastore in $datastores) 
            {
                $DatastoreDropDownBox.Items.Add($datastore.Name) #Add Datastores to DropDown List
            }
            $DatastoreDropDownBox.SelectedIndex = 0
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
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getClusters{  
    try 
    {
        $clusters = Get-Cluster #Returns all clusters
        if ($TabControl.SelectedIndex -eq 3)
        {
            $PgroupClusterDropDownBox.Items.Clear()
            $PgroupClusterDropDownBox.Items.Add("Choose a Recovery Cluster...")
            foreach ($cluster in $clusters) 
            {
                $PgroupClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
            } 
            $PgroupClusterDropDownBox.Enabled = $true
            $PgroupClusterDropDownBox.SelectedIndex = 0
        }
        elseif ($TabControl.SelectedIndex -eq 2)
        {
            $HostClusterDropDownBox.Items.Clear()
            $HostClusterDropDownBox.Items.Add("Choose a Cluster...")
            foreach ($cluster in $clusters) 
            {
                $HostClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
            } 
            $HostClusterDropDownBox.Enabled = $true
            $HostClusterDropDownBox.SelectedIndex = 0
        }
        elseif (($TabControl.SelectedIndex -eq 0) -or ($TabControl.SelectedIndex -eq 1))
        {
            $ClusterDropDownBox.Items.Clear()
            $ClusterDropDownBox.Items.Add("<All Clusters>")
            foreach ($cluster in $clusters) 
            {
                $ClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
            } 
            $ClusterDropDownBox.Enabled = $true
            $ClusterDropDownBox.SelectedIndex = 0
        }
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getRecoveryClusters{
  
    try 
    {
        $clusters = Get-Cluster -ErrorAction stop #Returns all clusters
        
        if ($getVMFSCluster -eq $true)
        {
            $CreateVMFSClusterDropDownBox.Items.Clear()
            $CreateVMFSClusterDropDownBox.Items.Add("Choose a Cluster...")
            foreach ($cluster in $clusters) 
            {
                $CreateVMFSClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
                $CreateVMFSClusterDropDownBox.Enabled = $true
            }
            $CreateVMFSClusterDropDownBox.SelectedIndex = 0
        }
        elseif ($RecoveryClusterDropDownBox.Enabled -eq $true)
        {
            $RecoveryClusterDropDownBox.Items.Clear()
            $RecoveryClusterDropDownBox.Items.Add("Choose a Cluster...")
            foreach ($cluster in $clusters) 
            {
                $RecoveryClusterDropDownBox.Items.Add($cluster.Name) #Add Clusters to DropDown List
                $RecoveryClusterDropDownBox.Enabled = $true
            }
            $RecoveryClusterDropDownBox.SelectedIndex = 0
        } 
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
    
}
function getSnapshots{
    try
    {
        $SnapshotDropDownBox.Items.Clear()
        $SnapshotDropDownBox.Enabled = $false
        if ($TabControl.SelectedIndex -eq 0)
        {
                    $datastore = get-datastore $DatastoreDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                    $script:lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        getFlashArray
        if ($script:lun -like 'naa.624a9370*')
        {
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $script:purevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($purevol -eq $null)
            {
                $outputTextBox.text = (get-Date -Format G) + " ERROR: Volume not found on a connected FlashArray." + ("`r`n") + $outputTextBox.text
                $SnapshotDropDownBox.Items.Clear()
                $buttonSnapshots.Enabled = $false
                $newSnapshotTextBox.Enabled = $false
                $buttonDeleteVMFS.Enabled = $false
                $newSnapshotTextBox.Text = ""
                $LabelNewSnapError.Text = ""
                $SnapshotDropDownBox.Enabled = $false
                $buttonDelete.Enabled = $false

            }
            else
            {
                $script:snapshots = $null
                $script:snapshots = Get-PfaVolumeSnapshots -array $endpoint -VolumeName $purevol.name
                $buttonDeleteVMFS.Enabled = $true
                if ($snapshots -ne $null)
                {
                    $SnapshotDropDownBox.Items.Add("Choose a Snapshot...")
                    foreach ($snapshot in $snapshots) 
                    {
                        $SnapshotDropDownBox.Items.Add("$($snapshot.Name) ($($snapshot.Created))") #Add snapshots to drop down List
                    }
                    $SnapshotDropDownBox.Enabled=$true
                    $newSnapshotTextBox.Enabled = $true
                    $SnapshotDropDownBox.SelectedIndex = 0
                }
                else
                {
                    $SnapshotDropDownBox.Items.Add("No snapshots found")
                    $SnapshotDropDownBox.SelectedIndex = 0
                    $newSnapshotTextBox.Enabled = $true
                    $SnapshotDropDownBox.Enabled=$false
                }
            }
        }
        else
        {
            $outputTextBox.text = (get-Date -Format G) + " Selected datastore is not a FlashArray volume." + ("`r`n") + $outputTextBox.text
            $SnapshotDropDownBox.Items.Clear()
            $buttonSnapshots.Enabled = $false
            $newSnapshotTextBox.Enabled = $false
            $buttonDeleteVMFS.Enabled = $false
            $newSnapshotTextBox.Text = ""
            $LabelNewSnapError.Text = ""
            $SnapshotDropDownBox.Enabled = $false
            $buttonDelete.Enabled = $false
        }

    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getVMSnapshots{
    try
    {
        $VMSnapshotDropDownBox.Items.Clear()
        $VMSnapshotDropDownBox.Enabled = $false
        if ($script:RadioButtonVMDK.Checked -eq $true)
        {
            $datastore = get-datastore (($VMDKDropDownBox.SelectedItem.ToString() |foreach { $_.Split("]")[0] }).substring(1))  -ErrorAction stop
            $script:lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        elseif ($script:RadioButtonRDM.Checked -eq $true)
        {
            $script:lun = ($RDMDropDownBox.SelectedItem.ToString()).substring(0,36)
        }
        else
        {
            $datastore = get-vm -Name $VMDropDownBox.SelectedItem.ToString() |Get-Datastore  -ErrorAction stop
            
            $script:lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
            if ($datastore.count -gt 1)
            {
                $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
                $CheckBoxDeleteVMObjectSnapshot.Checked = $false
                $buttonGetVMSnapshots.Enabled = $false
                $newVMSnapshotTextBox.Enabled = $false
                $buttonNewVMSnapshot.Enabled = $false
                $newVMSnapshotTextBox.Text = ""
                disableRecoveryItems
                throw "This VM uses more than one datastore and is not currently supported in this tool for full recovery. Use per-VMDK or per-RDM recovery instead."
            }
        }
        getFlashArray
        if ($script:lun -like 'naa.624a9370*')
        {
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $script:purevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($purevol -eq $null)
            {
                disableRecoveryItems
                $outputTextBox.text =  (get-Date -Format G) + " ERROR: Volume not found on a connected FlashArray." + ("`r`n") + $outputTextBox.text
                $VMSnapshotDropDownBox.Items.Clear()
                $buttonGetVMSnapshots.Enabled = $false
                $VMSnapshotDropDownBox.Enabled = $false
                $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
                $CheckBoxDeleteVMObjectSnapshot.Checked = $false
                $newVMSnapshotTextBox.Enabled = $false
                $buttonNewVMSnapshot.Enabled = $false
                $newVMSnapshotTextBox.Text = ""
            }
            else
            {
                $script:snapshots = $null
                $script:snapshots = Get-PfaVolumeSnapshots -array $endpoint -VolumeName $purevol.name
                if ($snapshots -ne $null)
                {
                    $VMSnapshotDropDownBox.Items.Add("Choose a Snapshot...")
                    foreach ($snapshot in $snapshots) 
                    {
                        $VMSnapshotDropDownBox.Items.Add("$($snapshot.Name) ($($snapshot.Created))") #Add snapshots to drop down List
                    }
                    $VMSnapshotDropDownBox.Enabled=$true
                    $buttonGetVMSnapshots.Enabled = $true
                    $VMSnapshotDropDownBox.SelectedIndex = 0
                    $newVMSnapshotTextBox.Enabled = $true
                }
                else
                {
                    $VMSnapshotDropDownBox.Items.Add("No snapshots found")
                    $VMSnapshotDropDownBox.SelectedIndex = 0
                    $VMSnapshotDropDownBox.Enabled=$false
                    $buttonGetVMSnapshots.Enabled = $false
                    $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
                    $CheckBoxDeleteVMObjectSnapshot.Checked = $false
                    $newVMSnapshotTextBox.Enabled = $true
                }
            }
        }
        else
        {
            $outputTextBox.text = (get-Date -Format G) + " Selected datastore is not a FlashArray volume." + ("`r`n") + $outputTextBox.text
            $VMSnapshotDropDownBox.Items.Clear()
            $newSnapshotTextBox.Enabled = $false
            $newSnapshotTextBox.Text = ""
            $LabelNewSnapError.Text = ""
            $VMSnapshotDropDownBox.Enabled = $false
            $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
            $CheckBoxDeleteVMObjectSnapshot.Checked = $false
            $buttonGetVMSnapshots.Enabled = $false
        }

    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getHostGroup{
    try
    {
        $fcinitiators = @()
        $iscsiinitiators = @()
        if ($TabControl.SelectedIndex -eq 0)
        {
            if ($script:createVMFS -eq $true)
            {
                $recoveryobject = get-cluster -Name $CreateVMFSClusterDropDownBox.SelectedItem.ToString()
                $fatemp = $ChooseFlashArrayDropDownBox.SelectedItem.ToString()
                foreach ($faArray in $endpoints)
                {
                    if ($faArray.endpoint -eq $fatemp)
                    {
                        $script:endpoint = $faArray
                        break
                    }
                }
            }
            else
            {
                $recoveryobject = get-cluster -Name $RecoveryClusterDropDownBox.SelectedItem.ToString()
            }
        }
        elseif ($TabControl.SelectedIndex -eq 2)
        {
            $recoveryobject = get-cluster -name $HostClusterDropDownBox.SelectedItem.ToString() 
            
        }
        elseif ($TabControl.SelectedIndex -eq 3)
        {
            $script:endpoint = $endpoints[$PgroupFADropDownBox.SelectedIndex-1]
            $recoveryobject = get-cluster -Name $PgroupClusterDropDownBox.SelectedItem.ToString()
        }
        else
        {
            if (($script:RadioButtonVM.Checked -eq $true) -and ($cloneObject -eq $true))
            {
                $recoveryobject = get-cluster -Name $TargetClusterDropDownBox.SelectedItem.ToString()
            }
            elseif((($script:RadioButtonVMDK.Checked -eq $true) -or ($script:RadioButtonRDM.Checked -eq $true)) -and ($cloneObject -eq $true))
            {
                $recoveryobject = get-vm -Name $TargetVMDropDownBox.SelectedItem.ToString()
            }
            else
            {
                $recoveryobject = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
            }
        }
        $iscsiadapters = $recoveryobject  |Get-VMHost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
        $fcadapters = $recoveryobject  |Get-VMHost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
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
            $outputTextBox.text = ((get-Date -Format G) + " No matching host group on $($endpoint.endpoint) could be found") + ("`r`n") + $outputTextBox.text
        }
        else
        {
           $outputTextBox.text = ((get-Date -Format G) + " The host group identified on FlashArray $($endpoint.endpoint) is named $($hostgroup)`r`n$($outputTextBox.text)") 
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getVMs{
    try 
    {
        $VMDropDownBox.Items.Clear()
        if ($ClusterDropDownBox.SelectedItem.ToString() -eq "<All Clusters>")
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $vms = get-vm -Name ("*" + $nameFilterTextBox.Text + "*") -ErrorAction stop
            }
            else
            {
                $vms = get-vm -ErrorAction stop
            }
        }
        else
        {
            if ($nameFilterTextBox.Text -ne "")
            {
                $vms = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() -ErrorAction stop|get-vm -Name ("*" + $nameFilterTextBox.Text + "*") -ErrorAction stop
            }
            else
            {
                $vms = get-cluster -Name $ClusterDropDownBox.SelectedItem.ToString() -ErrorAction stop |get-vm -ErrorAction stop
            }
        }
        if ($vms.count -eq 0)
        {
            $VMDropDownBox.Items.Add("No VMs found")
            $VMDropDownBox.SelectedIndex = 0
            $VMDropDownBox.Enabled=$false
            $VMSnapshotDropDownBox.Items.Clear()
            $VMSnapshotDropDownBox.Enabled = $false
        }
        else
        {
            $VMDropDownBox.Items.Add("Choose VM...")
            foreach ($vm in $vms) 
            {
                $VMDropDownBox.Items.Add($vm.Name) #Add VMs to DropDown List                
            }
            $VMDropDownBox.Enabled=$true
            $VMDropDownBox.SelectedIndex = 0
        }
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getDisks{
    try
    {
        if (($VMDropDownBox.text -ne "No VMs found") -and ($script:RadioButtonVM.Checked -ne $true))
        {
            if ($script:RadioButtonVMDK.Checked -eq $true)
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
                            if ($atLeastOnevdisk -eq $false)
                            {
                                $VMDKDropDownBox.Items.Add("Choose a VMDK...")
                            }
                            $atLeastOnevdisk = $true
                            $VMDKDropDownBox.Items.Add(($($vmdevice.Backing.fileName) + " (" + $($vmdevice.CapacityInKB/1024/1024) + " GB)"))
                        }
                    } 
                }
                if ($atLeastOnevdisk -eq $true)
                {
                    $VMDKDropDownBox.Enabled = $true
                    $VMDKDropDownBox.SelectedIndex = 0
                }
                else
                {
                    $VMDKDropDownBox.Items.Add("No virtual disks found")
                    $VMDKDropDownBox.SelectedIndex = 0
                    $VMSnapshotDropDownBox.Items.Clear()
                    $VMSnapshotDropDownBox.Enabled = $false
                }
            }
            elseif ($script:RadioButtonRDM.Checked -eq $true)
            {
                $RDMDropDownBox.Items.Clear()
                $atLeastOnerdm = $false
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
                $vmdevices = $vm.ExtensionData.Config.Hardware.Device 
                foreach ($vmdevice in $vmdevices)
                {
                    if ($vmdevice.gettype().Name -eq "VirtualDisk")
                    {
                        if ( $vmdevice.Backing.gettype().Name -eq "VirtualDiskRawDiskMappingVer1BackingInfo")
                        {
                            if ($atLeastOnerdm -eq $false)
                            {
                                $RDMDropDownBox.Items.Add("Choose a RDM...")
                            }
                            $atLeastOnerdm = $true
                            $RDMname = ('naa.' + $($vmdevice.Backing.DeviceName.substring(14,32)) + ' (' + $($vmdevice.CapacityInKB/1024/1024) + ' GB)')
                            $RDMDropDownBox.Items.Add($RDMname)
                        }
                    } 
                }
                if ($atLeastOnerdm -eq $true)
                {
                    $RDMDropDownBox.Enabled = $true
                    $RDMDropDownBox.SelectedIndex = 0
                }
                else
                {
                    $RDMDropDownBox.Items.Add("No raw device mappings found")
                    $RDMDropDownBox.SelectedIndex = 0
                    $RDMDropDownBox.Enabled = $false
                    $VMSnapshotDropDownBox.Items.Clear()
                    $VMSnapshotDropDownBox.Enabled = $false
                }
            }
        }
        else
        {

        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getFlashArray{
    try
    {
        $volArraySN = $script:lun.substring(12,16)
        foreach ($FAarray in $endpoints)
        {
            $arraySN = Get-PfaArrayAttributes -Array $FAarray
            $arraySN = $arraySN.id.substring(0,18)
            $arraySN = $arraySN -replace '-',''
            if ($arraySN -ieq $volArraySN)
            {
                $script:endpoint = $FAarray
                break
            }
            else
            {
                $script:endpoint = $FAarray
            }
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function listFlashArrays{
    try
    {
        if (($TabControl.SelectedIndex -eq 0) -or ($TabControl.SelectedIndex -eq 1))
        {
            $ChooseFlashArrayDropDownBox.Items.Clear()
            $ChooseFlashArrayDropDownBox.Items.Add("Choose a FlashArray...")
            foreach ($fa in $endpoints)
            {
                $ChooseFlashArrayDropDownBox.Items.Add($fa.endpoint)
            }
            $ChooseFlashArrayDropDownBox.SelectedIndex = 0
        }
        elseif ($TabControl.SelectedIndex -eq 2)
        {
            $HostFlashArrayDropDownBox.Enabled = $false
            $HostFlashArrayDropDownBox.Items.Clear()
            $HostFlashArrayDropDownBox.Items.Add("Choose a FlashArray...")
            $HostFlashArrayDropDownBox.Items.Add("Select All FlashArrays")
            foreach ($fa in $endpoints)
            {
                $HostFlashArrayDropDownBox.Items.Add($fa.endpoint)
                $HostFlashArrayDropDownBox.Enabled = $true
            }
            $HostFlashArrayDropDownBox.SelectedIndex = 0
        }
        elseif ($TabControl.SelectedIndex -eq 3)
        {
            $PgroupFADropDownBox.Enabled = $false
            $PgroupFADropDownBox.Items.Clear()
            $PgroupFADropDownBox.Items.Add("Choose a FlashArray...")
            foreach ($fa in $endpoints)
            {
                $PgroupFADropDownBox.Items.Add($fa.endpoint)
                $PgroupFADropDownBox.Enabled = $true
            }
            if ($endpoints.count -eq 1)
            {
                $PgroupFADropDownBox.SelectedIndex = 1
            }
            else
            {
                $PgroupFADropDownBox.SelectedIndex = 0
                $AddToPgroupCheckedListBox.Items.Clear()
                $AddToPgroupCheckedListBox.Enabled=$false
            }
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getTargetVMs{
    try 
    {
        $targetVMs = Get-VM #Returns all VMs
        $TargetVMDropDownBox.Items.Clear()
        $TargetVMDropDownBox.Items.Add("Choose Target VM...")
        foreach ($targetVM in $targetVMs) 
        {
            $TargetVMDropDownBox.Items.Add($targetVM.Name) #Add VMs to DropDown List
        } 
        $TargetVMDropDownBox.Enabled = $true
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
    $TargetVMDropDownBox.Enabled = $true
    $TargetVMDropDownBox.SelectedIndex = 0
}
function getTargetClusters{
    try 
    {
        if ($TargetDatastoreDropDownBox.SelectedItem.ToString() -eq "<Keep on a New Recovery Datastore>")
        {
            $targetClusters = get-cluster #Returns all clusters
        }
        else
        {
            $targetClusters = get-datastore $TargetDatastoreDropDownBox.SelectedItem.ToString() |get-vmhost |get-cluster #Returns all clusters
        }
        $TargetClusterDropDownBox.Items.Clear()
        $TargetClusterDropDownBox.Items.Add("Choose Target Cluster...")
        foreach ($targetCluster in $targetClusters) 
        {
            $TargetClusterDropDownBox.Items.Add($targetCluster.Name) #Add Clusters to DropDown List
        } 
        $TargetClusterDropDownBox.Enabled = $true
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
    $TargetClusterDropDownBox.Enabled = $true
    $TargetClusterDropDownBox.SelectedIndex = 0
}
function getTargetDatastores{
    try 
    {
        $targetDatastores = Get-Datastore |Where-Object {$_.Type -eq "VMFS"} #Returns all datastores
        $TargetDatastoreDropDownBox.Items.Clear()
        $TargetDatastoreDropDownBox.Items.Add("Choose Target Datastore...")
        $TargetDatastoreDropDownBox.Items.Add("<Keep on a New Recovery Datastore>")
        foreach ($targetDatastore in $targetDatastores) 
        {
            $TargetDatastoreDropDownBox.Items.Add($targetDatastore.Name) #Add Datastores to DropDown List
        } 
        $TargetDatastoreDropDownBox.Enabled = $true
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
    $TargetDatastoreDropDownBox.Enabled = $true
    $TargetDatastoreDropDownBox.SelectedIndex = 0
}
function getProtectionGroups{
    try
    {
        $script:pgroups = Get-PfaProtectionGroups -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] 
        if ($TabControl.SelectedIndex -eq 3)
        {
            $PgroupPGDropDownBox.Enabled = $false
            $PgroupPGDropDownBox.Items.Clear()
            if ($pgroups -ne $null)
            {
                $PgroupPGDropDownBox.Items.Add("Choose a Protection Group...")
                foreach ($pg in $script:pgroups)
                {
                    $PgroupPGDropDownBox.Items.Add($pg.name)
                    $PgroupPGDropDownBox.Enabled = $true
                }
            }
            else
            {
                $PgroupPGDropDownBox.Items.Add("No Protection Groups found")
            }
            $PgroupPGDropDownBox.SelectedIndex = 0
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getProtectionGroupSnapshots{
    try
    {
        if ($TabControl.SelectedIndex -eq 3)
        {
            $selectedPG = $PgroupPGDropDownBox.SelectedItem.ToString()
            if ($selectedPG -ne "Choose a Protection Group...")
            {
                if ($PgroupPGDropDownBox.SelectedItem.ToString() -like "*:*")
                {
                    if ($script:currentPGisRemote -eq $true)
                    {
                        $script:pgFaChanged = $false
                    }
                    else
                    {
                        $script:pgFaChanged = $true
                    }
                    $script:currentPGisRemote = $true
                }
                else
                {
                    if ($script:currentPGisRemote -eq $true)
                    {
                        $script:pgFaChanged = $true
                    }
                    else
                    {
                        $script:pgFaChanged = $false
                    }
                    $script:currentPGisRemote = $false
                }
                $script:pgroupsnapshots = Get-PfaProtectionGroupSnapshots -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Name $selectedPG
                $buttonCreatePgroupSnap.Enabled = $true
                $PgroupSnapDropDownBox.Enabled = $false
                $PgroupSnapDropDownBox.Items.Clear()
                if ($script:pgroupsnapshots -ne $null)
                {
                    $PgroupSnapDropDownBox.Items.Add("Choose a Snapshot Group...")
                    foreach ($pgsnapgroup in $script:pgroupsnapshots)
                    {
                        $dateconvert = get-date $pgsnapgroup.created
                        $PgroupSnapDropDownBox.Items.Add("$($dateconvert)       $($pgsnapgroup.name)")
                        $PgroupSnapDropDownBox.Enabled = $true
                    }
                }
                else
                {
                    $PgroupSnapDropDownBox.Items.Add("No Snapshot Groups found")
                }
                $PgroupSnapDropDownBox.SelectedIndex = 0
                getPgroupDatastores
                $script:atChoosePgroup = $false
            }
            else
            {
                $script:atChoosePgroup = $true
                $PgroupSnapDropDownBox.Enabled = $false
                $PgroupSnapDropDownBox.Items.Clear()
                $SnapshotCheckedListBox.Items.Clear()
                $SnapshotCheckedListBox.Enabled=$false
                $PgroupSnapDropDownBox.Enabled = $false
                $PgroupSnapDropDownBox.Items.Clear()
                $PgroupClusterDropDownBox.Items.Clear()
                $buttonRecoverPgroup.Enabled = $false
                $PgroupClusterDropDownBox.Enabled=$false
                $SnapshotCheckedListBox.Items.Clear()
                $SnapshotCheckedListBox.Enabled=$false
                $registerVMs.Enabled = $false
                $registerVMs.Checked = $false
                $buttonCreatePgroupSnap.Enabled = $false
                $buttonDeletePgroupSnap.Enabled = $false
                $AddToPgroupCheckedListBox.Items.Clear()
                $AddToPgroupCheckedListBox.Enabled=$false
            }
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getPiTSnapshots{
    try
    {
        if (($PgroupSnapDropDownBox.SelectedItem.ToString() -ne "Choose a Snapshot Group...") -and ($PgroupSnapDropDownBox.SelectedItem.ToString() -ne "No Snapshot Groups found"))
        {
            
            $selectedPiT = $script:pgroupsnapshots[$PgroupSnapDropDownBox.SelectedIndex-1].name
            $selectedPG = $PgroupPGDropDownBox.SelectedItem.ToString()
            $script:volumeSnapshots = Get-PfaProtectionGroupVolumeSnapshots -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Name $selectedPG |where-object {$_.name -like "$($selectedPiT).*"}
            $SnapshotCheckedListBox.Items.Clear()
            $SnapshotCheckedListBox.Enabled=$false
            $buttonDeletePgroupSnap.Enabled = $true
            $SnapshotCheckedListBox.Items.Add("Select All")
            foreach ($volumeSnapshot in $script:volumeSnapshots)
            {
                $SnapshotCheckedListBox.Items.Add($volumeSnapshot.name)
            } 
            $SnapshotCheckedListBox.Enabled = $true
            $SnapshotCheckedListBox.SetItemchecked(0,$true)
            for ($i=1;$i -lt $SnapshotCheckedListBox.Items.count;$i++) 
            {
                $SnapshotCheckedListBox.SetItemchecked($i,$true)
            }
            getClusters
        }
        else
        {
            $SnapshotCheckedListBox.Items.Clear()
            $SnapshotCheckedListBox.Enabled=$false
            $PgroupClusterDropDownBox.Items.Clear()
            $PgroupClusterDropDownBox.Enabled=$false
            $SnapshotCheckedListBox.Items.Clear()
            $SnapshotCheckedListBox.Enabled=$false
            $registerVMs.Enabled = $false
            $registerVMs.Checked = $false
            $buttonRecoverPgroup.Enabled = $false
            $buttonDeletePgroupSnap.Enabled = $false
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getPgroupDatastores{
    try
    {
        if ($PgroupPGDropDownBox.SelectedItem.ToString() -like "*:*")
        {
            $AddToPgroupCheckedListBox.Items.Clear()
            $AddToPgroupCheckedListBox.Enabled=$false
        }
        elseif (($script:pgFaChanged -eq $true) -or ($script:atChoosePgroup -eq $true))
        {
            $arraySN = Get-PfaArrayAttributes -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1]
            $arraySN = $arraySN.id.substring(0,18)
            $arraySN = $arraySN -replace '-',''
            $script:datastoresOnFA = get-datastore | where-object {($_.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique) -like "*$($arraySN)*"}
            $AddToPgroupCheckedListBox.Items.Clear()
            $AddToPgroupCheckedListBox.Enabled=$false
            $AddToPgroupCheckedListBox.Items.Add("Select All")
            if ($datastoresOnFA -ne $null)
            {
                foreach ($datastoreOnFA in $datastoresOnFA)
                {
                    $AddToPgroupCheckedListBox.Items.Add($datastoreOnFA.name)    
                }
                $AddToPgroupCheckedListBox.Enabled = $true
            }
            else
            {
                $AddToPgroupCheckedListBox.Items.Add("No datastores found from this FA.")
            }
            $script:pgFaChanged = $false
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function getHosts{
    try 
    {
        $AddHostDropDownBox.Items.Clear()
        $esxihosts = get-cluster -name $HostClusterDropDownBox.SelectedItem.ToString() |get-vmhost
        foreach ($esxihost in $esxihosts) 
        {
            $AddHostDropDownBox.Items.Add($esxihost.Name) #Add hosts to DropDown List
        } 
        $AddHostDropDownBox.Enabled = $true
        $AddHostDropDownBox.SelectedIndex = 0
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
#Context change functions
function radioSelectChanged{
    disableRecoveryItems
    $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
    $CheckBoxDeleteVMObject.Checked = $false
    $CheckBoxDeleteVMObjectSnapshot.Checked = $false
    if ($script:RadioButtonVM.Checked -eq $true)
    {
        if ($groupBoxRecoverVM.text -eq "Restore/Clone Virtual Disk:")
        {
            $script:groupBoxCloneVM.Controls.Remove($TargetDatastoreDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($TargetVMDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetVM)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetDatastore)
        }
        elseif($groupBoxRecoverVM.text -eq "Restore/Clone Raw Device Mapping:")
        {
            $script:groupBoxCloneVM.Controls.Remove($TargetVMDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetVM)
            $groupBoxRecoverVM.Controls.Remove($groupBoxRestoreRDM)
            $groupBoxRecoverVM.Controls.Add($groupBoxRestoreVM)
        }
        $script:groupBoxRecoverVM.text = "Restore/Clone Virtual Machine:"
        $buttonDeleteVM.Text = "Delete VM"
        $script:LabelTargetDatastore.Location = New-Object System.Drawing.Point(5, 20)
        $script:LabelTargetCluster.Location = New-Object System.Drawing.Point(5, 45)
        $script:TargetDatastoreDropDownBox.Location = New-Object System.Drawing.Size(90,20)
        $script:TargetClusterDropDownBox.Location = New-Object System.Drawing.Size(90,45) 
        $script:groupBoxCloneVM.Controls.Add($TargetDatastoreDropDownBox)
        $script:groupBoxCloneVM.Controls.Add($TargetClusterDropDownBox)
        $script:groupBoxCloneVM.Controls.Add($LabelTargetCluster)
        $script:groupBoxCloneVM.Controls.Add($LabelTargetDatastore)
    }
    elseif ($script:RadioButtonVMDK.Checked -eq $true)
    {
        if ($groupBoxRecoverVM.text -eq "Restore/Clone Virtual Machine:")
        {
            $script:groupBoxCloneVM.Controls.Remove($TargetDatastoreDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($TargetClusterDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetDatastore)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetCluster)
        }
        elseif($groupBoxRecoverVM.text -eq "Restore/Clone Raw Device Mapping:")
        {
            $script:groupBoxCloneVM.Controls.Remove($TargetVMDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetVM)
            $groupBoxRecoverVM.Controls.Remove($groupBoxRestoreRDM)
            $groupBoxRecoverVM.Controls.Add($groupBoxRestoreVM)
        }
        $script:groupBoxRecoverVM.text = "Restore/Clone Virtual Disk:"
        $buttonDeleteVM.Text = "Delete VMDK"
        $script:LabelTargetVM.Location = New-Object System.Drawing.Point(5, 20)
        $script:LabelTargetDatastore.Location = New-Object System.Drawing.Point(5, 45)
        $script:TargetVMDropDownBox.Location = New-Object System.Drawing.Size(90,20) 
        $script:TargetDatastoreDropDownBox.Location = New-Object System.Drawing.Size(90,45)
        $script:groupBoxCloneVM.Controls.Add($TargetDatastoreDropDownBox)
        $script:groupBoxCloneVM.Controls.Add($TargetVMDropDownBox)
        $script:groupBoxCloneVM.Controls.Add($LabelTargetVM)
        $script:groupBoxCloneVM.Controls.Add($LabelTargetDatastore)
    }
    elseif ($script:RadioButtonRDM.Checked -eq $true)
    {
        if ($groupBoxRecoverVM.text -eq "Restore/Clone Virtual Machine:")
        {
            $script:groupBoxCloneVM.Controls.Remove($TargetDatastoreDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($TargetClusterDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetDatastore)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetCluster)
        }
        elseif ($groupBoxRecoverVM.text -eq "Restore/Clone Virtual Disk:")
        {
            $script:groupBoxCloneVM.Controls.Remove($TargetDatastoreDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($TargetVMDropDownBox)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetVM)
            $script:groupBoxCloneVM.Controls.Remove($LabelTargetDatastore)
        }
        $groupBoxRecoverVM.Controls.Remove($groupBoxRestoreVM)
        $groupBoxRecoverVM.Controls.Add($groupBoxRestoreRDM)
        $script:groupBoxRecoverVM.text = "Restore/Clone Raw Device Mapping:"
        $buttonDeleteVM.Text = "Delete RDM"
        $script:LabelTargetVM.Location = New-Object System.Drawing.Point(5, 30)
        $script:TargetVMDropDownBox.Location = New-Object System.Drawing.Size(90,30) 
        $script:groupBoxCloneVM.Controls.Add($TargetVMDropDownBox)
        $script:groupBoxCloneVM.Controls.Add($LabelTargetVM)
    }
    if ($script:RadioButtonVM.Checked -eq $true)
    {
        if (($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM...") -and ($VMDropDownBox.SelectedItem.ToString() -ne "No VMs found"))
        {
            getVMSnapshots
        }
        if ($script:vmdkChosen -eq $true)
        {
            $script:groupBoxVM.Controls.Remove($groupBoxVMDK) 
            $script:vmdkChosen = $false
        }
        if ($script:rdmChosen -eq $true)
        {
            $script:groupBoxVM.Controls.Remove($groupBoxRDM) 
            $script:rdmChosen = $false
        }
        $CheckBoxDeleteVMObject.Text = "I confirm that I want to delete this ENTIRE virtual machine"
        $groupBoxDeleteVMObject.text = "Delete Virtual Machine:" 
    }
    elseif ($script:RadioButtonVMDK.Checked -eq $true)
    {
        if ($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM...")
        {
            getDisks
        }
        if ($script:rdmChosen -eq $true)
        {
            $script:groupBoxVM.Controls.Remove($groupBoxRDM) 
            $script:rdmChosen = $false
        }
        $script:vmdkChosen = $true
        $script:groupBoxVM.Controls.Add($groupBoxVMDK) 
        $CheckBoxDeleteVMObject.Text = "I confirm that I want to delete this virtual disk"
        $groupBoxDeleteVMObject.text = "Delete Virtual Disk:" 
    }
    elseif ($script:RadioButtonRDM.Checked -eq $true)
    {
        if ($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM...")
        {
            getDisks
        }
        if ($script:vmdkChosen -eq $true)
        {
            $script:groupBoxVM.Controls.Remove($groupBoxVMDK) 
            $script:vmdkChosen = $false
        }
        $script:rdmChosen = $true
        $script:groupBoxVM.Controls.Add($groupBoxRDM) 
        $CheckBoxDeleteVMObject.Text = "I confirm that I want to delete this raw device mapping"
        $groupBoxDeleteVMObject.text = "Delete Raw Device Mapping:" 
    }
    enableVMDetails
}
function vmDiskSelectionChanged{
    if (($script:RadioButtonVMDK.Checked -eq $true) -and ($VMDKDropDownBox.SelectedItem.ToString() -ne "Choose a VMDK...") -and ($VMDKDropDownBox.SelectedItem.ToString() -ne "No virtual disks found") )
    {
        $CheckBoxDeleteVMObject.Enabled = $true
        getVMSnapshots
        disableRecoveryItems
    }
    elseif (($script:RadioButtonRDM.Checked -eq $true) -and ($RDMDropDownBox.SelectedItem.ToString() -ne "Choose a RDM...") -and ($RDMDropDownBox.SelectedItem.ToString() -ne "No raw device mappings found") )
    {
        $CheckBoxDeleteVMObject.Enabled = $true
        getVMSnapshots
        disableRecoveryItems
    }
    else
    {
        $CheckBoxDeleteVMObject.Enabled = $false
        $CheckBoxDeleteVMObject.Enabled = $false
        $VMSnapshotDropDownBox.Enabled = $false
        $VMSnapshotDropDownBox.Items.Clear()
        $buttonGetVMSnapshots.Enabled = $false
        disableRecoveryItems
    }
    if (($script:RadioButtonVMDK.Checked -eq $true) -and ($VMDKDropDownBox.SelectedItem.ToString() -eq "Choose a VMDK..."))
    {
        $newVMSnapshotTextBox.Enabled = $false
        disableRecoveryItems
    }
    elseif (($script:RadioButtonRDM.Checked -eq $true) -and ($RDMDropDownBox.SelectedItem.ToString() -eq "Choose a RDM..."))
    {
        $newVMSnapshotTextBox.Enabled = $false
        disableRecoveryItems
    }
    $CheckBoxDeleteVMObject.Checked = $false
}
function isSnapshotTextChanged{
    if ($TabControl.SelectedIndex -eq 0)
    {
        $LabelNewSnapError.Text = ""
        if (($newSnapshotTextBox.Text -notmatch "^[\w\-]+$") -and ($newSnapshotTextBox.Text -ne ""))
        {
            $LabelNewSnapError.ForeColor = "Red"
            $LabelNewSnapError.Text = "The snapshot name must only be letters, numbers or dashes"
            $buttonNewSnapshot.Enabled = $false
        }
        elseif($newVMSnapshotTextBox.Text -eq "")
        {
            $buttonNewSnapshot.Enabled = $false
        }
        else
        {
            $buttonNewSnapshot.Enabled = $true
        }
    }
    elseif ($TabControl.SelectedIndex -eq 1)
    {
        $LabelNewVMSnapError.Text = ""
        if (($newVMSnapshotTextBox.Text -notmatch "^[\w\-]+$") -and ($newVMSnapshotTextBox.Text -ne ""))
        {
            $LabelNewVMSnapError.ForeColor = "Red"
            $LabelNewVMSnapError.Text = "The snapshot name must only be letters, numbers or dashes"
            $buttonNewVMSnapshot.Enabled = $false
        }
        elseif($newVMSnapshotTextBox.Text -eq "")
        {
            $buttonNewVMSnapshot.Enabled = $false
        }
        else
        {
            $buttonNewVMSnapshot.Enabled = $true
        }
    }
}
function datastoreSelectionChanged{
    if (($DatastoreDropDownBox.Enabled -eq $true) -and ($DatastoreDropDownBox.SelectedItem.ToString() -ne "<No Datastores Found>") -and ($DatastoreDropDownBox.SelectedItem.ToString() -ne "Choose VMFS..."))
    {
        getSnapshots
        $buttonSnapshots.Enabled = $true
    }
    else
    {
        $SnapshotDropDownBox.Items.Clear()
        $buttonSnapshots.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $buttonDeleteVMFS.Enabled = $false
        $newSnapshotTextBox.Text = ""
        $SnapshotDropDownBox.Enabled = $false
    }
}
function vmSelectionChanged{
    if (($VMDropDownBox.Enabled -eq $true) -and ($VMDropDownBox.SelectedItem.ToString() -ne "<No Virtual Machines Found>") -and ($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM..."))
    {
        $CheckBoxDeleteVMObject.Enabled = $false
        if ($script:RadioButtonVM.Checked -eq $true)
        {
            if (($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM...") -and ($VMDropDownBox.SelectedItem.ToString() -ne "No VMs found"))
            {
                $CheckBoxDeleteVMObject.Enabled = $true
            }
        }
        $CheckBoxDeleteVMObject.Checked = $false
        $CheckBoxDeleteVMObjectSnapshot.Checked = $false
        $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
        getDisks
        if ($script:RadioButtonVM.Checked -eq $true)
        {
            if (($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM...") -and ($VMDropDownBox.SelectedItem.ToString() -ne "No VMs found"))
            {
                getVMSnapshots
            }
        }
    }
    else
    {
        $CheckBoxDeleteVMObject.Enabled = $false
        $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
        $CheckBoxDeleteVMObject.Checked = $false
        $CheckBoxDeleteVMObjectSnapshot.Checked = $false
        $VMSnapshotDropDownBox.Items.Clear()
        $VMSnapshotDropDownBox.Enabled = $false
        $buttonGetVMSnapshots.Enabled = $false
        disableRecoveryItems
        if ($script:RadioButtonVMDK.Checked -eq $true)
        {
            $script:VMDKDropDownBox.Items.Clear()
            $script:VMDKDropDownBox.Enabled = $false
            $CheckBoxDeleteVMObject.Enabled = $false
        }
        elseif ($script:RadioButtonRDM.Checked -eq $true)
        {
            $script:RDMDropDownBox.Items.Clear()
            $script:RDMDropDownBox.Enabled = $false
            $CheckBoxDeleteVMObject.Enabled = $false
        }

    }
}
function isVMFSTextChanged{
    $LabelNewVMFSError.Text = ""
    if (($newVMFSTextBox.Text -notmatch "^[\w\-]+$") -and ($newVMFSTextBox.Text -ne ""))
    {
        $LabelNewVMFSError.ForeColor = "Red"
        $LabelNewVMFSError.Text = "The VMFS name must only be letters, numbers or dashes"
        $buttonNewVMFS.Enabled = $false
        $script:nameIsValid = $false
    }
    elseif ($newVMFSTextBox.Text -eq "")
    {
        $script:nameIsValid = $false
        enableCreateVMFS
    }
    else
    {
        $script:nameIsValid = $true
        enableCreateVMFS
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
function snapshotChanged{
    try
    {
        if (($SnapshotDropDownBox.SelectedItem.ToString() -ne "Choose a Snapshot...") -and ($SnapshotDropDownBox.Enabled -eq $true))
        {
            $buttonDelete.Enabled = $true
            $newSnapshotTextBox.Text = ""
            $LabelNewSnapError.Text = ""
            $RecoveryClusterDropDownBox.Enabled=$true
            getRecoveryClusters
        }
        else 
        {
            $buttonDelete.Enabled = $false
            $RecoveryClusterDropDownBox.Enabled=$false
            $RecoveryClusterDropDownBox.Items.Clear()
            $newSnapshotTextBox.Text = ""
            $LabelNewSnapError.Text = ""
            $buttonRecover.Enabled = $false
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function vmSnapshotChanged{
    try
    {
        if (($VMSnapshotDropDownBox.SelectedItem.ToString() -ne "Choose a Snapshot...") -and ($VMSnapshotDropDownBox.Enabled -eq $true))
        {
            $CheckBoxDeleteVMObjectSnapshot.Enabled = $true
            $buttonRestoreVM.Enabled = $true
            $buttonRestoreRDM.Enabled = $true
            $migrateVMCheckBox.Enabled = $true
            if ($script:RadioButtonVM.Checked -eq $true)
            {
                getTargetDatastores
            }
            elseif ($script:RadioButtonVMDK.Checked -eq $true)
            {
                getTargetVMs
            }
            elseif ($script:RadioButtonRDM.Checked -eq $true)
            {
                getTargetVMs
            }
        }
        else 
        {
            $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
            $CheckBoxDeleteVMObjectSnapshot.Checked = $false
            $buttonRestoreVM.Enabled = $false
            $buttonRestoreRDM.Enabled = $false
            $migrateVMCheckBox.Enabled = $false
            disableRecoveryItems
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function FlashArrayChanged{
    if ($FlashArrayDropDownBox.SelectedItem.ToString() -eq "Add new FlashArray...")
       {
            if ($endpoints.count -eq 0)
            {
                $FlashArrayDropDownBox.Enabled = $false
            }
            $flasharrayTextBox.Text = ""
            $flasharrayPasswordTextBox.Text = ""
            $flasharrayUsernameTextBox.Text = ""
            $flasharrayTextBox.Enabled = $true
            $flasharrayPasswordTextBox.Enabled = $true
            $flasharrayUsernameTextBox.Enabled = $true
            $flasharrayButtonDisconnect.enabled = $false
            $flasharrayButtonConnect.enabled = $false
            
       }
       else
       {
            $flasharrayTextBox.Text = $FlashArrayDropDownBox.SelectedItem.ToString()
            $flasharrayPasswordTextBox.Text = ""
            $flasharrayUsernameTextBox.Text = ""
            $flasharrayTextBox.Enabled = $false
            $flasharrayPasswordTextBox.Enabled = $false
            $flasharrayUsernameTextBox.Enabled = $false
            $flasharrayButtonDisconnect.enabled = $true
            $flasharrayButtonConnect.enabled = $false
       }
}
function sizeChanged{
    $LabelNewVMFSSizeError.Text = ""
    if (($newVMFSSizeTextBox.Text -notmatch "^[\d]+$") -and ($newVMFSSizeTextBox.Text -ne ""))
    {
        $LabelNewVMFSSizeError.ForeColor = "Red"
        $LabelNewVMFSSizeError.Text = " The size must be a whole integer greater than zero"
        $buttonNewVMFS.Enabled = $false
        $script:sizeIsValid = $false
    }
    elseif (($newVMFSSizeTextBox.Text -eq 0) -and ($newVMFSSizeTextBox.Text -ne ""))
    {
        $LabelNewVMFSSizeError.ForeColor = "Red"
        $LabelNewVMFSSizeError.Text = " The size must be greater than zero"
        $buttonNewVMFS.Enabled = $false
        $script:sizeIsValid = $false
    }
    elseif ($newVMFSSizeTextBox.Text -eq "")
    {
        $script:sizeIsValid = $false
        enableCreateVMFS
    }
    else
    {
        $script:sizeIsValid = $true
        enableCreateVMFS
    }
}
function vmDeleteCheckedChanged{
   if (($CheckBoxDeleteVMObject.Checked -eq $false) -or ($CheckBoxDeleteVMObject.Enabled -eq $false)) 
   {
        $buttonDeleteVM.Enabled = $false
   }
   elseif ($CheckBoxDeleteVMObject.Checked -eq $true)
   {
        $buttonDeleteVM.Enabled = $true
   }
}
function vmDeleteSnapshotCheckedChanged{
   if (($CheckBoxDeleteVMObjectSnapshot.Checked -eq $false) -or ($CheckBoxDeleteVMObjectSnapshot.Enabled -eq $false)) 
   {
        $buttonDeleteVMSnapshot.Enabled = $false
   }
   elseif ($CheckBoxDeleteVMObjectSnapshot.Checked -eq $true)
   {
        $buttonDeleteVMSnapshot.Enabled = $true
   }
}
function targetClusterSelectionChanged{
    if ($script:RadioButtonVM.Checked -eq $true)
    {
        if (($targetClusterDropDownBox.SelectedItem.ToString() -ne "Choose Target Cluster...") -and ($targetClusterDropDownBox.Enabled -eq $true))
        {
            $buttonCloneVM.Enabled = $true
        }
        elseif (($targetClusterDropDownBox.SelectedItem.ToString() -eq "Choose Target Cluster...") -or ($targetClusterDropDownBox.Enabled -eq $false))
        {
            $buttonCloneVM.Enabled = $false
        }
    }
}
function targetVMSelectionChanged{
    if ($script:RadioButtonVMDK.Checked -eq $true)
    {
        if (($targetVMDropDownBox.SelectedItem.ToString() -ne "Choose Target VM...") -and ($targetVMDropDownBox.Enabled -eq $true))
        {
            getTargetDatastores
        }
        elseif (($targetVMDropDownBox.SelectedItem.ToString() -eq "Choose Target VM...") -or ($targetVMDropDownBox.Enabled -eq $false))
        {
            $TargetDatastoreDropDownBox.Items.Clear()
            $TargetDatastoreDropDownBox.Enabled = $false
            $buttonCloneVM.Enabled = $false
        }
    }
    if ($script:RadioButtonRDM.Checked -eq $true)
    {
        if (($targetVMDropDownBox.SelectedItem.ToString() -ne "Choose Target VM...") -and ($targetVMDropDownBox.Enabled -eq $true))
        {
            $buttonCloneVM.Enabled = $true
        }
        elseif (($targetVMDropDownBox.SelectedItem.ToString() -eq "Choose Target VM...") -or ($targetVMDropDownBox.Enabled -eq $false))
        {
            $buttonCloneVM.Enabled = $false
        }
    }
}
function targetDatastoreSelectionChanged{
    if ($script:RadioButtonVM.Checked -eq $true)
    {
        if (($targetDatastoreDropDownBox.SelectedItem.ToString() -ne "Choose Target Datastore...") -and ($targetDatastoreDropDownBox.Enabled -eq $true))
        {
            getTargetClusters
        }
        elseif (($targetDatastoreDropDownBox.SelectedItem.ToString() -eq "Choose Target Datastore...") -or ($targetDatastoreDropDownBox.Enabled -eq $false))
        {
            $TargetClusterDropDownBox.Items.Clear()
            $TargetClusterDropDownBox.Enabled = $false
            $buttonCloneVM.Enabled = $false
        }
    }
    elseif ($script:RadioButtonVMDK.Checked -eq $true)
    {
        if (($targetDatastoreDropDownBox.SelectedItem.ToString() -ne "Choose Target Datastore...") -and ($targetDatastoreDropDownBox.Enabled -eq $true))
        {
            $buttonCloneVM.Enabled = $true
        }
        elseif (($targetDatastoreDropDownBox.SelectedItem.ToString() -eq "Choose Target Datastore...") -or ($targetDatastoreDropDownBox.Enabled -eq $false))
        {
            $buttonCloneVM.Enabled = $false
        }
    }
}
function clusterConfigSelectionChanged{
    try
    {
        if (($HostClusterDropDownBox.SelectedItem.ToString() -ne "Choose a Cluster...") -and ($HostFlashArrayDropDownBox.SelectedItem.ToString() -ne "Choose a FlashArray..."))
        {
            $script:RadioButtoniSCSI.Enabled = $true
            $script:RadioButtoniSCSI.Checked = $true
            $script:RadioButtonFC.Enabled = $true
            $buttonCreateHostGroup.Enabled = $true
            $script:RadioButtonHostiSCSI.Enabled = $true
            $script:RadioButtonHostiSCSI.Checked = $true
            $script:RadioButtonHostFC.Enabled = $true
            $buttonAddHosts.Enabled = $true
            $buttonConfigureiSCSI.Enabled = $true
            $buttonConfigureSATP.Enabled = $true
            getHosts
        }
        else
        {
            $script:RadioButtoniSCSI.Enabled = $false
            $script:RadioButtoniSCSI.Checked = $false
            $script:RadioButtonFC.Checked = $false
            $script:RadioButtonFC.Enabled = $false
            $buttonCreateHostGroup.Enabled = $false
            $buttonConfigureiSCSI.Enabled = $false
            $buttonConfigureSATP.Enabled = $false
            $script:RadioButtonHostiSCSI.Enabled = $false
            $script:RadioButtonHostiSCSI.Checked = $false
            $script:RadioButtonHostFC.Enabled = $false
            $buttonAddHosts.Enabled = $false
            $AddHostDropDownBox.Enabled = $false
            $AddHostDropDownBox.Items.Clear()
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + "  $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function pgroupFAChanged{
    if ($PgroupFADropDownBox.SelectedItem.ToString() -ne "Choose a FlashArray...")
    {
        getProtectionGroups
        $script:pgFaChanged = $true
    }
    else
    {
        $PgroupPGDropDownBox.Enabled = $false
        $PgroupPGDropDownBox.Items.Clear()
        $PgroupSnapDropDownBox.Enabled = $false
        $PgroupSnapDropDownBox.Items.Clear()
        $PgroupClusterDropDownBox.Items.Clear()
        $PgroupClusterDropDownBox.Enabled=$false
        $SnapshotCheckedListBox.Items.Clear()
        $SnapshotCheckedListBox.Enabled=$false
        $registerVMs.Enabled = $false
        $buttonRecoverPgroup.Enabled = $false
        $registerVMs.Checked = $false
        $buttonCreatePgroupSnap.Enabled = $false
        $buttonDeletePgroupSnap.Enabled = $false
        $AddToPgroupCheckedListBox.Items.Clear()
        $AddToPgroupCheckedListBox.Enabled=$false
    }
}
function snapshotSelectAll{
    if ($This.SelectedItem -eq 'Select All') 
    {
        If ($This.GetItemCheckState(0) -ne 'Checked')
        {
            for ($i=1;$i -lt $SnapshotCheckedListBox.Items.count;$i++) 
            {
                $SnapshotCheckedListBox.SetItemchecked($i,$true)
            }
            if ($PgroupClusterDropDownBox.Enabled -eq $false)
            {
                getClusters
            }
        }
        else
        {
            for ($i=1;$i -lt $SnapshotCheckedListBox.Items.count;$i++) 
            {
                $SnapshotCheckedListBox.SetItemchecked($i,$false)
            }
            $PgroupClusterDropDownBox.Items.Clear()
            $PgroupClusterDropDownBox.Enabled=$false
            $registerVMs.Enabled = $false
            $buttonRecoverPgroup.Enabled = $false
            $registerVMs.Checked = $false
        }
    }
    else
    {
        if ($This.GetItemCheckState($This.SelectedIndex) -ne 'Checked')
        {
            if ($PgroupClusterDropDownBox.Enabled -eq $false)
            {
                getClusters
            }
        }
        elseif($SnapshotCheckedListBox.CheckedItems.count -eq 1)
        {
            $PgroupClusterDropDownBox.Items.Clear()
            $PgroupClusterDropDownBox.Enabled=$false
            $registerVMs.Enabled = $false
            $buttonRecoverPgroup.Enabled = $false
            $registerVMs.Checked = $false
        }
        elseif ($This.GetItemCheckState($This.SelectedIndex) -eq 'Checked')
        {
            if ($SnapshotCheckedListBox.GetItemCheckState(0) -eq 'Checked')
            {
                $SnapshotCheckedListBox.SetItemchecked(0,$false)
            }
        }
    }
}
function enableAddtoPG{
    if ($This.SelectedItem -eq 'Select All') 
    {
        If ($This.GetItemCheckState(0) -ne 'Checked')
        {
            for ($i=1;$i -lt $AddToPgroupCheckedListBox.Items.count;$i++) 
            {
                $AddToPgroupCheckedListBox.SetItemchecked($i,$true)
            }
            $buttonAddVMFStoPgroup.Enabled = $true
        }
        else
        {
            for ($i=1;$i -lt $AddToPgroupCheckedListBox.Items.count;$i++) 
            {
                $AddToPgroupCheckedListBox.SetItemchecked($i,$false)
            }
            $buttonAddVMFStoPgroup.Enabled = $false
        }
    }
    else
    {
        if ($This.GetItemCheckState($This.SelectedIndex) -ne 'Checked')
        {
            $buttonAddVMFStoPgroup.Enabled = $true
        }
        elseif($AddToPgroupCheckedListBox.CheckedItems.count -eq 1)
        {
            $buttonAddVMFStoPgroup.Enabled = $false
        }
        elseif ($This.GetItemCheckState($This.SelectedIndex) -eq 'Checked')
        {
            if ($AddToPgroupCheckedListBox.GetItemCheckState(0) -eq 'Checked')
            {
                $AddToPgroupCheckedListBox.SetItemchecked(0,$false)
            }
        }
    }
}
function clusterSelectionChanged{
   enableObjects 
}
function registerVMchanged{
    if ($registerVMs.Checked -eq $false)
    {
        $powerOnVMs.Enabled = $false
        $powerOnVMs.Checked = $false
    }
    else
    {
        $powerOnVMs.Enabled = $true
    }   
}
#Enable functions
function enableCreateVMFS{
    if (($nameIsValid -eq $true) -and ($sizeIsValid -eq $true) -and ($ChooseFlashArrayDropDownBox.SelectedItem.ToString() -ne "Choose a FlashArray...") -and ($CreateVMFSClusterDropDownBox.SelectedItem.ToString() -ne "Choose a Cluster..."))
    {
        $buttonNewVMFS.Enabled = $true
    }
    else
    {
        $buttonNewVMFS.Enabled = $false
    }
}
function enableVMDetails{
    if (($VMDropDownBox.Enabled -eq $true) -and ($VMDropDownBox.SelectedItem.ToString() -ne "<No Virtual Machines Found>") -and ($VMDropDownBox.SelectedItem.ToString() -ne "Choose VM..."))
    {
        if ($script:RadioButtonVM.Checked -eq $true)
        {

        }
        elseif ($script:RadioButtonVMDK.Checked -eq $true)
        {
            $VMDKDropDownBox.Enabled=$true
            $CheckBoxDeleteVMObject.Enabled=$false
        }
        elseif ($script:RadioButtonRDM.Checked -eq $true)
        {
            $RDMDropDownBox.Enabled=$true 
            $CheckBoxDeleteVMObject.Enabled=$false
        }
        getDisks
    }
    elseif (($VMDropDownBox.SelectedItem.ToString() -eq "<No Virtual Machines Found>") -and ($VMDropDownBox.SelectedItem.ToString() -eq "Choose VM..."))
    {
        $VMDKDropDownBox.Enabled=$false
        $RDMDropDownBox.Enabled=$false
        $CheckBoxDeleteVMObject.Enabled=$false
        $CheckBoxDeleteVMObject.Enabled=$false
    }
}
function enableRecovery{
    if (($RecoveryClusterDropDownBox.SelectedItem.ToString() -eq "Choose a Cluster...") -or ($RecoveryClusterDropDownBox.Enabled -eq $false))
    {
        $buttonRecover.Enabled = $false
    }
    else
    {
        $buttonRecover.Enabled = $true
    }
}
function enableObjects{
    disableObjects
    if ($TabControl.SelectedIndex -eq 0)
    {
        if ($script:lastTab -ieq "host")
        {
            $script:main_form.Controls.Remove($groupBoxChooseHost)
            $script:main_form.Controls.Add($groupBoxRadio)
        }
        elseif ($script:lastTab -ieq "pgroup")
        {
            $script:main_form.Controls.Remove($groupBoxFilterPgroup)
            $script:main_form.Controls.Add($groupBoxRadio)
        }
        $script:lastTab = "vmfs"
        $ChooseFlashArrayDropDownBox.Enabled=$true 
        $CreateVMFSClusterDropDownBox.Enabled=$true
        $newVMFSTextBox.Enabled = $true 
        $newVMFSSizeTextBox.Enabled = $true
        $UnitDropDownBox.Enabled=$true
        $buttonDatastores.Enabled = $true
        $ClusterDropDownBox.Enabled=$true
        $nameFilterTextBox.Enabled = $true
        listFlashArrays
        getDatastores
        $getVMFSCluster = $true
        getRecoveryClusters
        $getVMFSCluster = $false
    }
    elseif($TabControl.SelectedIndex -eq 1)
    {
        if ($script:lastTab -ieq "host")
        {
            $script:main_form.Controls.Remove($groupBoxChooseHost)
            $script:main_form.Controls.Add($groupBoxRadio)
        }
        elseif ($script:lastTab -ieq "pgroup")
        {
            $script:main_form.Controls.Remove($groupBoxFilterPgroup)
            $script:main_form.Controls.Add($groupBoxRadio)
        }
        $script:lastTab = "vm"
        $VMDropDownBox.Enabled = $true
        $buttonVMs.Enabled = $true
        $ClusterDropDownBox.Enabled=$true
        $nameFilterTextBox.Enabled = $true
        $RadioButtonVM.Enabled = $true
        $RadioButtonVMDK.Enabled = $true
        $RadioButtonRDM.Enabled = $true
        getVMs
        $script:RadioButtonVM.Checked = $true
    }
    elseif($TabControl.SelectedIndex -eq 2)
    {
        if (($script:lastTab -ieq "vm") -or ($script:lastTab -ieq "vmfs"))
        {
            $script:main_form.Controls.Remove($groupBoxRadio)
            $script:main_form.Controls.Add($groupBoxChooseHost) 
        }
        elseif ($script:lastTab -ieq "pgroup")
        {
            $script:main_form.Controls.Remove($groupBoxFilterPgroup)
            $script:main_form.Controls.Add($groupBoxChooseHost)
        } 
        $script:lastTab = "host"
        getclusters
        listFlashArrays
    }
    elseif($TabControl.SelectedIndex -eq 3)
    {
        if ($script:lastTab -ieq "host")
        {
            $script:main_form.Controls.Remove($groupBoxChooseHost)
            $script:main_form.Controls.Add($groupBoxFilterPgroup)
        }
        elseif (($script:lastTab -ieq "vm") -or ($script:lastTab -ieq "vmfs"))
        {
            $script:main_form.Controls.Remove($groupBoxRadio)
            $script:main_form.Controls.Add($groupBoxFilterPgroup)
        }
        $script:lastTab = "pgroup"
        listFlashArrays
    }
}
function disableObjects{
    if ($TabControl.SelectedIndex -eq 0)
    {
        $buttonDatastores.Enabled = $false
        $buttonDeleteVMFS.Enabled = $false
        $buttonSnapshots.Enabled = $false 
        $buttonNewSnapshot.Enabled = $false 
        $buttonNewVMFS.Enabled = $false 
        $buttonRecover.Enabled = $false 
        $buttonDelete.Enabled = $false 
        $nameFilterTextBox.Enabled = $false
        $newSnapshotTextBox.Enabled = $false
        $newVMFSTextBox.Enabled = $false
        $newVMFSSizeTextBox.Enabled = $false
        $ClusterDropDownBox.Enabled=$false 
        $DatastoreDropDownBox.Enabled=$false 
        $UnitDropDownBox.Enabled=$false 
        $CreateVMFSClusterDropDownBox.Enabled=$false 
        $ChooseFlashArrayDropDownBox.Enabled=$false 
        $RecoveryClusterDropDownBox.Enabled=$false 
        $SnapshotDropDownBox.Enabled=$false
    }
    elseif($TabControl.SelectedIndex -eq 1)
    {
        $VMDropDownBox.Enabled = $false
        $buttonVMs.Enabled = $false
        $ClusterDropDownBox.Enabled=$false
        $nameFilterTextBox.Enabled = $false
        $RadioButtonVM.Enabled = $false
        $RadioButtonVMDK.Enabled = $false
        $RadioButtonRDM.Enabled = $false
    }
    elseif($TabControl.SelectedIndex -eq 2)
    {
        $HostFlashArrayDropDownBox.Enabled = $false
        $HostFlashArrayDropDownBox.Items.Clear()
        $HostClusterDropDownBox.Items.Clear()
        $HostClusterDropDownBox.Enabled = $false
    }
    elseif($TabControl.SelectedIndex -eq 3)
    {
        $PgroupPGDropDownBox.Enabled = $false
        $PgroupPGDropDownBox.Items.Clear()
        $PgroupSnapDropDownBox.Enabled = $false
        $PgroupSnapDropDownBox.Items.Clear()
        $SnapshotCheckedListBox.Items.Clear()
        $SnapshotCheckedListBox.Enabled=$false
        $buttonRecoverPgroup.Enabled = $false
        $PgroupSnapDropDownBox.Enabled = $false
        $PgroupSnapDropDownBox.Items.Clear()
        $PgroupClusterDropDownBox.Items.Clear()
        $PgroupClusterDropDownBox.Enabled=$false
        $SnapshotCheckedListBox.Items.Clear()
        $SnapshotCheckedListBox.Enabled=$false
        $registerVMs.Enabled = $false
        $buttonCreatePgroupSnap.Enabled = $false
        $registerVMs.Checked = $false
        $buttonDeletePgroupSnap.Enabled = $false
        $AddToPgroupCheckedListBox.Items.Clear()
        $AddToPgroupCheckedListBox.Enabled=$false
    }
 
}
function disableRecoveryItems{
    $script:TargetDatastoreDropDownBox.Items.Clear()
    $script:TargetDatastoreDropDownBox.Enabled = $false
    $script:buttonCloneVM.Enabled = $false
    $script:TargetClusterDropDownBox.Items.Clear()
    $script:TargetClusterDropDownBox.Enabled = $false
    $script:TargetVMDropDownBox.Items.Clear()
    $script:TargetVMDropDownBox.Enabled = $false
    $script:buttonRestoreVM.Enabled = $false
    $script:buttonRestoreRDM.Enabled = $false
    $migrateVMCheckBox.Enabled = $false
}
function pgroupcheckboxes{
    if (($PgroupClusterDropDownBox.SelectedItem.ToString() -ne "Choose a Recovery Cluster...") -and ($SnapshotCheckedListBox.CheckedItems.count -ge 1))
    {
        $registerVMs.Enabled = $true
        $buttonRecoverPgroup.Enabled = $true
    }
    else
    {
        $registerVMs.Enabled = $false
        $registerVMs.Checked = $false
        $powerOnVMs.Enabled = $false
        $powerOnVMs.Checked = $false
        $buttonRecoverPgroup.Enabled = $false
    }
}
#Operation Functions
function addHost{
    try 
    {
        if ($HostFlashArrayDropDownBox.SelectedItem.ToString() -eq "Select All FlashArrays")
        {
            foreach ($FAendpoint in $endpoints)
            {
                $script:endpoint = $FAendpoint
                getHostGroup
                createHost
            }
        }
        else
        {
            foreach ($FAendpoint in $endpoints)
            {
                if ($HostFlashArrayDropDownBox.SelectedItem.ToString() -eq $FAendpoint.endpoint)
                {
                    $script:endpoint = $FAendpoint
                    break
                }
            }
            getHostGroup
            createHost
        }
    }
    catch 
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function deleteVMObject{
    if ($script:RadioButtonVM.Checked -eq $true)
    {
        deleteVM
    }
    elseif ($script:RadioButtonVMDK.Checked -eq $true)
    {
        deleteVMDK
    }
    elseif ($script:RadioButtonRDM.Checked -eq $true)
    {
        deleteRDM
    }
}
function deleteSnapshot{
    try
    {
         $deletedSnap = Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $snapshots[$SnapshotDropDownBox.SelectedIndex-1].name
         $outputTextBox.text = ((get-Date -Format G) + " Deleted snapshot $($deletedSnap.name)`r`n$($outputTextBox.text)")
         getSnapshots
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function deleteVMSnapshot{
    try
    {
         $deletedSnap = Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $snapshots[$VMSnapshotDropDownBox.SelectedIndex-1].name
         $outputTextBox.text = ((get-Date -Format G) + " Deleted snapshot $($deletedSnap.name)`r`n$($outputTextBox.text)")
         getVMSnapshots
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function deleteVMFS{
  
    $outputTextBox.text = ((get-Date -Format G) + " Deleting datastore $($DatastoreDropDownBox.SelectedItem.ToString())...`r`n$($outputTextBox.text)")
    try
    {
        $deleteVmfs = get-datastore $DatastoreDropDownBox.SelectedItem.ToString() -ErrorAction stop
        $vms = $deleteVmfs |get-vm -ErrorAction stop
        $templates = $deleteVmfs |get-template -ErrorAction stop
        if (($vms.count -eq 0) -and ($templates.count -eq 0))
        {
            $lun = $deleteVmfs.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $deletevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($deletevol -eq $null)
            {
                $outputTextBox.text =  "ERROR: Volume not found on connected FlashArray." + ("`r`n") + $outputTextBox.text
                return
            }
            $FAhostgroups = Get-PfaVolumeHostGroupConnections -Array $endpoint -VolumeName $deletevol.name
            $FAhosts = Get-PfaVolumeHostConnections -Array $endpoint -VolumeName $deletevol.name
            $esxihosts = $deleteVmfs |get-vmhost -ErrorAction stop
            $FAhostgroups = $FAhostgroups.hgroup |Select-Object -unique
            $FAhosts = $FAhosts.host |Select-Object -unique
            $outputTextBox.text = ((get-Date -Format G) + " Unmounting and detaching volume from each ESXi host...`r`n$($outputTextBox.text)")
            foreach ($esxihost in $esxihosts)
            {
                $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
	            $StorageSystem.UnmountVmfsVolume($deleteVmfs.ExtensionData.Info.vmfs.uuid) 
                $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost -ErrorAction stop| where {$_.CanonicalName -eq $deleteVmfs.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) 
            }
            foreach ($FAhost in $FAhosts)
            {
                Remove-PfaHostVolumeConnection -Array $endpoint -VolumeName $deletevol.name -HostName $FAhost
            }
            foreach ($FAhostgroup in $FAhostgroups)
            {
                Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $deletevol.name -HostGroupName $FAhostgroup
            }
            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $deletevol.name
            $outputTextBox.text = ((get-Date -Format G) + " The FlashArray volume $($deletevol.name) has been deleted`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
            $esxihosts | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " COMPLETED: The datastore and FlashArray volume has been deleted`r`n$($outputTextBox.text)")
            getDatastores 
        } 
        else
        {
            $outputTextBox.text = ((get-Date -Format G) + " ERROR: Cannot delete this VMFS as there are virtual machines and/or templates using it.`r`n$($outputTextBox.text)")
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function deleteVM{

    try
    {
        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
        $vm |remove-vm -DeletePermanently -Confirm:$false -ErrorAction stop
        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Deleted VM $($VMDropDownBox.SelectedItem.ToString())`r`n$($outputTextBox.text)")
        getVMs
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function deleteVMDK{
  
    try
    {
        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
        $filepath = ($VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
        $filepath = $filepath.Substring(0,$filepath.Length-1)
        $disk = $vm | get-harddisk |where-object { $_.Filename -eq $filepath } -ErrorAction stop
        if ($disk.ExtensionData.Backing.Sharing -eq "sharingMultiWriter")
        {
            $VMDKinUse = $false
            $outputTextBox.text = ((get-Date -Format G) + " WARNING. VMDK is detected in Shared Multi-Writer Mode. Could be in use by another VM. Checking...`r`n$($outputTextBox.text)")
            $vms = $disk |Get-Datastore| get-vm 
            foreach ($vmdkVM in $vms)
            {
                $tempDisk = $vmdkVM |get-harddisk |where-object { $_.Filename -eq $filepath } -ErrorAction stop
                if (($tempDisk -ne $null) -and ($vmdkVM.name -ne $vm.name))
                {
                    $outputTextBox.text = ((get-Date -Format G) + " RDM is also in use by VM $($vmdkVM.Name).`r`n$($outputTextBox.text)")
                    $VMDKinUse = $true
                }
            }
            if ($VMDKinUse -eq $true)
            {
                $outputTextBox.text = ((get-Date -Format G) + " VMDK is detected as in-use by other VMs. Only removing VMDK from this VM, but not deleting it.`r`n$($outputTextBox.text)")
                disk |remove-harddisk -Confirm:$false -ErrorAction stop
                $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: VMDK removed.`r`n$($outputTextBox.text)")
            }
            else
            {
                $outputTextBox.text = ((get-Date -Format G) + " No other VMs have been detected using this VMDK. Will continue with removing and deleting it.`r`n$($outputTextBox.text)")
            }
        }
        if (($disk.ExtensionData.Backing.Sharing -ne "sharingMultiWriter") -or ($VMDKinUse -eq $false) )
        {
            $outputTextBox.text = ((get-Date -Format G) + " Removing VMDK from VM...`r`n$($outputTextBox.text)")
            $disk | remove-harddisk -DeletePermanently -Confirm:$false -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: VMDK removed and deleted.`r`n$($outputTextBox.text)")
        }
        getDisks
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function deleteRDM{

    try
    {
        $outputTextBox.text = ((get-Date -Format G) + " Removing RDM and destroying the FlashArray volume...`r`n$($outputTextBox.text)")
        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
        $naa = (($RDMDropDownBox.SelectedItem.ToString()).substring(0,36))
        $disk = $vm | get-harddisk |where-object { $_.ScsiCanonicalName -eq $naa } -ErrorAction stop
        if ($disk.ExtensionData.Backing.Sharing -eq "sharingMultiWriter")
        {
            $RDMinUse = $false
            $outputTextBox.text = ((get-Date -Format G) + " WARNING. RDM is detected in Shared Multi-Writer Mode. Could be in use by another VM. Checking...`r`n$($outputTextBox.text)")
            $vms = $disk |Get-Datastore| get-vm 
            foreach ($rdmVM in $vms)
            {
                $tempDisk = $rdmVM |get-harddisk |where-object { $_.ScsiCanonicalName -eq $naa } -ErrorAction stop
                if (($tempDisk -ne $null) -and ($rdmVM.name -ne $vm.Name))
                {
                    $outputTextBox.text = ((get-Date -Format G) + " RDM is also in use by VM $($rdmVM.Name).`r`n$($outputTextBox.text)")
                    $RDMinUse = $true
                }
            }
            if ($RDMinUse -eq $true)
            {
                $outputTextBox.text = ((get-Date -Format G) + " RDM is detected as in-use by other VMs. Only removing RDM from this VM, but not deleting it.`r`n$($outputTextBox.text)")
                $disk |remove-harddisk -Confirm:$false -ErrorAction stop
                $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: RDM removed.`r`n$($outputTextBox.text)")
            }
            else
            {
                $outputTextBox.text = ((get-Date -Format G) + " No other VMs have been detected using this RDM. Will continue with removing and deleting it.`r`n$($outputTextBox.text)")
            }
        }
        if (($disk.ExtensionData.Backing.Sharing -ne "sharingMultiWriter") -or ($RDMinUse -eq $false) )
        {
            $disk |remove-harddisk -Confirm:$false -DeletePermanently -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " Removed RDM from VM. Now detaching the volume`r`n$($outputTextBox.text)")
            $lun = $naa
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $deletevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($deletevol -eq $null)
            {
                $outputTextBox.text =  "ERROR: Volume not found on connected FlashArray." + ("`r`n") + $outputTextBox.text
                return
            }
            $esxihosts = get-vmhost
            $hostsToDetach = @()
            foreach ($esxihost in $esxihosts)
            {
               $scsilun = $esxihost | get-scsilun |where-object { $_.CanonicalName -eq $naa }
               if ($scsilun.count -ne 0)
               {
                    $hostsToDetach += $esxihost
               }
            }
            $outputTextBox.text = ((get-Date -Format G) + " Detaching device from hosts...`r`n$($outputTextBox.text)")
            foreach ($esxihost in $hostsToDetach)
            {
                $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem -ErrorAction stop
                $storageSystem.DetachScsiLun($naa) 
            }
            $FAhostgroups = Get-PfaVolumeHostGroupConnections -Array $endpoint -VolumeName $deletevol.name | select -ExpandProperty hgroup |select-object -unique
            $FAhosts = Get-PfaVolumeHostConnections -Array $endpoint -VolumeName $deletevol.name | select -ExpandProperty hgroup |select-object -unique
            foreach ($FAhost in $FAhosts)
            {
                Remove-PfaHostVolumeConnection -Array $endpoint -VolumeName $deletevol.name -HostName $FAhost
            }
            foreach ($FAhostgroup in $FAhostgroups)
            {
                Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $deletevol.name -HostGroupName $FAhostgroup
            }
            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $deletevol.name
            $outputTextBox.text = ((get-Date -Format G) + " The FlashArray volume $($deletevol.name) has been deleted`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
            $hostsToDetach | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The RDM volume has been removed and destroyed.`r`n$($outputTextBox.text)")
            getDisks
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function createHostGroup{
    if ($HostFlashArrayDropDownBox.SelectedItem.ToString() -eq "Select All FlashArrays")
    {
        $flasharrays = $endpoints
    }
    else
    {
        foreach ($endpoint in $endpoints)
        {
            if ($HostFlashArrayDropDownBox.SelectedItem.ToString() -eq $endpoint.endpoint)
            {
                $flasharrays = $endpoint
            }
        }
    }
    $esxihosts = get-cluster -name $HostClusterDropDownBox.SelectedItem.ToString() |get-vmhost
    $clustername = $HostClusterDropDownBox.SelectedItem.ToString()
    $outputTextBox.text = ((get-Date -Format G) + " Creating host groups for the cluster $($clustername) on $($flasharrays.count) FlashArrays`r`n$($outputTextBox.text)") 
    foreach ($flasharray in $flasharrays)
    {
        try
        {
            $fahosts = Get-PFAHosts -array $flasharray -ErrorAction Stop
            $fahostgroups = Get-PFAHostGroups -array $flasharray -ErrorAction Stop
        }
        catch
        {
            $outputTextBox.text = ((get-Date -Format G) + " ERROR: Could not obtain host information from the FlashArray. Check FlashArray for errors. Skipping the FlashArray named  $($flasharray.endpoint)`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
            return
        } 
        $iqnexist = $false
        $wwnsexist = $false
        foreach ($esxihost in $esxihosts)
        {
            if ($RadioButtoniSCSI.Checked -eq $true)
            {
                    $iscsiadapter = $esxihost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
                    if ($iscsiadapter -eq $null)
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " ERROR: No Software iSCSI adapter found on host " + $esxihost.NetworkInfo.HostName + ". No changes were made.`r`n$($outputTextBox.text)")
                        return
                    }
                    else
                    {
                        $iqn = $iscsiadapter.ExtensionData.IScsiName
                        foreach ($esxi in $fahosts)
                        {
                            if ($esxi.iqn.count -ge 1)
                            {
                                foreach($fahostiqn in $esxi.iqn)
                                {
                                    if ($iqn.ToLower() -eq $fahostiqn.ToLower())
                                    {
                                        $hostgroupfailed = $true
                                        $iqnexist = $true
                                    }
                                }
                            }
                        }
                    }
                }
            elseif ($RadioButtonFC.Checked -eq $true)
            {
                $wwns = $esxihost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
                $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
                $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
                {
                        $wwns.substring($i,16)
                }}
                if ($wwns -eq $null)
                {
                    $outputTextBox.text = ((get-Date -Format G) + " No FC WWNs found on host $($esxihost.NetworkInfo.HostName). No changes were made.`r`n$($outputTextBox.text)")
                    return
                }
                else
                {
                    foreach ($wwn in $wwns)
                    {
                        foreach ($esxi in $fahosts)
                        {
                            if ($esxi.wwn.count -ge 1)
                            {
                                foreach($fahostwwn in $esxi.wwn)
                                {
                                    if ($wwn.ToLower() -eq $fahostwwn.ToLower())
                                    {
                                        $outputTextBox.text = ((get-Date -Format G) + " ERROR: The ESXi WWN $($wwn) already exists on the FlashArray.`r`n$($outputTextBox.text)")  
                                        $wwnsexist = $true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if (($iqnexist -eq $true) -or ($wwnsexist -eq $true))
        {
            $outputTextBox.text = ((get-Date -Format G) + " ERROR: An ESXi host's initiators have been found on this FlashArray. Skipping the FlashArray named $($flasharray.endpoint)`r`n$($outputTextBox.text)")
            continue
        }
        else
        {
            $outputTextBox.text = ((get-Date -Format G) + " Creating hosts on the FlashArray $($flasharray.endpoint)`r`n$($outputTextBox.text)")
            $createhostfail = $false
            $newfahosts = @()
            if ($RadioButtoniSCSI.Checked -eq $true)
            {
                foreach ($esxihost in $esxihosts)
                {
                if ($createhostfail -eq $false)
                {
                    $iscsiadapter = $esxihost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
                    $iqn = $iscsiadapter.ExtensionData.IScsiName
                    try
                    {
                        $newfahosts += New-PfaHost -Array $flasharray -Name $esxihost.NetworkInfo.HostName -IqnList $iqn -ErrorAction stop
                    }
                    catch
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " ERROR: The host $($esxihost.NetworkInfo.HostName) failed to create. Review error. Cleaning up this FlashArray and moving on.`r`n$($outputTextBox.text)")
                        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
                        $hostgroupfailed = $true
                        $createhostfail = $true
                        if ($newfahosts.count -ge 1)
                        {
                            $outputTextBox.text = ((get-Date -Format G) + " Deleting the $($newfahosts.count) hosts on this FlashArray that were just created by this script..`r`n$($outputTextBox.text)")
                            foreach ($removehost in $newfahosts)
                            {
                                Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                            }
                        }
                    }
                }
            }
            }
            elseif ($RadioButtonFC.Checked -eq $true)
            {
                foreach ($esxihost in $esxihosts)
                {
                    if ($createhostfail -eq $false)
                    {
                        $wwns = $esxihost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
                        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
                        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
                        {
                                $wwns.substring($i,16)
                        }}
                        try
                        {
                            $newfahosts += New-PfaHost -Array $flasharray -Name $esxihost.NetworkInfo.HostName -ErrorAction stop
                            foreach ($wwn in $wwns)
                            {
                                if ($createhostfail -eq $false)   
                                {
                                    try
                                    {
                                        Add-PfaHostWwns -Array $flasharray -Name $esxihost.NetworkInfo.HostName -AddWwnList $wwn -ErrorAction stop |out-null
                                    }
                                    catch
                                    {
                                        $outputTextBox.text = ((get-Date -Format G) + " ERROR: The host $($esxihost.NetworkInfo.HostName) failed to create. Review error. Cleaning up this FlashArray and moving on.`r`n$($outputTextBox.text)")
                                        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
                                        $hostgroupfailed = $true
                                        $createhostfail = $true
                                        if ($newfahosts.count -ge 1)
                                        {
                                            $outputTextBox.text = ((get-Date -Format G) + " Deleting the $($newfahosts.count) hosts on this FlashArray that were just created by this script..`r`n$($outputTextBox.text)")
                                            foreach ($removehost in $newfahosts)
                                            {
                                                Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                            }
                                        }
                                    }
                                }
                            }
                  
                         }
                        catch
                        {
                            $outputTextBox.text = ((get-Date -Format G) + "ERROR: The host $($esxihost.NetworkInfo.HostName) failed to create. Review error. Cleaning up this FlashArray and moving on.`r`n$($outputTextBox.text)")
                            $hostgroupfailed = $true
                            $outputTextBox.text = ((get-Date -Format G) + " $($error[0])`r`n$($outputTextBox.text)")
                            $createhostfail = $true
                            if ($newfahosts.count -ge 1)
                            {
                                $outputTextBox.text = ((get-Date -Format G) + " Deleting the $($newfahosts.count) hosts on this FlashArray that were created by this script`r`n$($outputTextBox.text)")
                                foreach ($removehost in $newfahosts)
                                {
                                    Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                    $outputTextBox.text = ((get-Date -Format G) + " Removed host $($removehost.Name)`r`n$($outputTextBox.text)")
                                }
                            }
                        }
                    }
                }
            }
            if ($createhostfail -eq $false)
            {
                #FlashArray only supports Alphanumeric or the dash - character in host group names. Checking for VMware cluster name compliance and removing invalid characters.
                if ($clustername -notmatch "^[a-zA-Z0-9\-]+$")
                {
                    $clustername = $clustername -replace "[^\w\-]", ""
                    $clustername = $clustername -replace "[_]", ""
                }
                $clustersuccess = $false
                try
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Creating host group on the FlashArray $($flasharray.endpoint)`r`n$($outputTextBox.text)")
                    $newcluster = New-PfaHostGroup -Array $flasharray -Name $clustername -ErrorAction stop
                    $clustersuccess = $true
                }
                catch
                {
                    $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
                    $outputTextBox.text = ((get-Date -Format G) + " ERROR: The host group $($clustername) failed to create. Review error below. Cleaning up this FlashArray and moving on.`r`n$($outputTextBox.text)") 
                    $hostgroupfailed = $true
                    if ($newfahosts.count -ge 1)
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " Deleting the $($newfahosts.count) hosts on this FlashArray that were created by this script`r`n$($outputTextBox.text)") 
                        foreach ($removehost in $newfahosts)
                        {
                            Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                        }
                    }
                }
                if ($clustersuccess -eq $true)
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Adding the hosts to the host group`r`n$($outputTextBox.text)") 
                    foreach ($newfahost in $newfahosts)
                    {
                        Add-PfaHosts -Array $flasharray -Name $clustername -hoststoadd $newfahost.name |Out-Null
                    }
                    $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Host Group created on FlashArray $($flasharray.endpoint)`r`n$($outputTextBox.text)")
                }
            }
        }
    }
}
function createHost{
    $esxihost = get-vmhost -name $AddHostDropDownBox.SelectedItem.ToString()
    $outputTextBox.text = ((get-Date -Format G) + " Creating host for $($esxihost.name) on FlashArray $($endpoint.endpoint) and adding to host group `r`n$($outputTextBox.text)") 
    try
    {
        $fahosts = Get-PFAHosts -array $endpoint -ErrorAction Stop
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " ERROR: Could not obtain host information from the FlashArray. Check FlashArray for errors. `r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
        return
    } 
    $iqnexist = $false
    $wwnsexist = $false
    if ($RadioButtonHostiSCSI.Checked -eq $true)
    {
        $iscsiadapter = $esxihost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
        if ($iscsiadapter -eq $null)
        {
            $outputTextBox.text = ((get-Date -Format G) + " ERROR: No Software iSCSI adapter found on host " + $esxihost.NetworkInfo.HostName + ". No changes were made.`r`n$($outputTextBox.text)")
            return
        }
        else
        {
            $iqn = $iscsiadapter.ExtensionData.IScsiName
            foreach ($esxi in $fahosts)
            {
                if ($esxi.iqn.count -ge 1)
                {
                    foreach($fahostiqn in $esxi.iqn)
                    {
                        if ($iqn.ToLower() -eq $fahostiqn.ToLower())
                        {
                            $hostgroupfailed = $true
                            $iqnexist = $true
                            return
                        }
                    }
                }
            }
        }
    }
    elseif ($RadioButtonHostFC.Checked -eq $true)
    {
        $wwns = $esxihost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
        {
                $wwns.substring($i,16)
        }}
        if ($wwns -eq $null)
        {
            $outputTextBox.text = ((get-Date -Format G) + " No FC WWNs found on host $($esxihost.NetworkInfo.HostName). No changes were made.`r`n$($outputTextBox.text)")
            return
        }
        else
        {
            foreach ($wwn in $wwns)
            {
                foreach ($esxi in $fahosts)
                {
                    if ($esxi.wwn.count -ge 1)
                    {
                        foreach($fahostwwn in $esxi.wwn)
                        {
                            if ($wwn.ToLower() -eq $fahostwwn.ToLower())
                            {
                                $outputTextBox.text = ((get-Date -Format G) + " ERROR: The ESXi WWN $($wwn) already exists on the FlashArray.`r`n$($outputTextBox.text)")  
                                $wwnsexist = $true
                                return
                            }
                        }
                    }
                }
            }
        }
    }
    $outputTextBox.text = ((get-Date -Format G) + " Creating the host on the FlashArray $($endpoint.endpoint)`r`n$($outputTextBox.text)")
    if ($RadioButtonHostiSCSI.Checked -eq $true)
    {
        $iscsiadapter = $esxihost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
        $iqn = $iscsiadapter.ExtensionData.IScsiName
        try
        {
            $newfahost = New-PfaHost -Array $endpoint -Name $esxihost.NetworkInfo.HostName -IqnList $iqn -ErrorAction stop
        }
        catch
        {
            $outputTextBox.text = ((get-Date -Format G) + " ERROR: The host $($esxihost.NetworkInfo.HostName) failed to create. Review error.`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
            return
        }
    }
    elseif ($RadioButtonHostFC.Checked -eq $true)
    {
        $wwns = $esxihost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
        {
                $wwns.substring($i,16)
        }}
        try
        {
            $newfahost = New-PfaHost -Array $endpoint -Name $esxihost.NetworkInfo.HostName -ErrorAction stop
            foreach ($wwn in $wwns)
            {
                Add-PfaHostWwns -Array $endpoint -Name $esxihost.NetworkInfo.HostName -AddWwnList $wwn -ErrorAction stop |out-null
            }
        }
        catch
        {
            $outputTextBox.text = ((get-Date -Format G) + " ********ERROR********`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " $($error[0])`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " The host $($esxihost.NetworkInfo.HostName) failed to create. Review error.`r`n$($outputTextBox.text)")
            return
        }
    }
    try
    {
        Add-PfaHosts -Array $endpoint -Name $hostgroup -hoststoadd $newfahost.name |Out-Null
        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Host added to host group on FlashArray $($endpoint.endpoint)`r`n$($outputTextBox.text)")
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " ********ERROR********`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " $($error[0])`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " The host failed to add to the host group. Review error.`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " Removing the earlier created host`r`n$($outputTextBox.text)")
        Remove-PfaHost -Array $endpoint -Name $newfahost.name |out-null
        return
    }
}
function newSnapshot{  
    try
    {
        if ($TabControl.SelectedIndex -eq 0)
        {
            $LabelNewSnapError.Text = ""
            $datastore = get-datastore $DatastoreDropDownBox.SelectedItem.ToString()
            $script:lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
        }
        elseif ($TabControl.SelectedIndex -eq 1) 
        {
            $LabelNewVMSnapError.Text = ""
            if ($RadioButtonVM.Checked -eq $true)
            {
                $datastore = get-vm -Name $VMDropDownBox.SelectedItem.ToString() |Get-Datastore
                $script:lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
                if ($datastore.count -gt 1)
                {
                    throw "This VM uses more than one datastore and is not supported in this tool"
                }
            }
            if ($RadioButtonVMDK.Checked -eq $true)
            {
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
                $datastore = get-datastore (($script:VMDKDropDownBox.SelectedItem.ToString() |foreach { $_.Split("]")[0] }).substring(1))
                $script:lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
            }
            if ($RadioButtonRDM.Checked -eq $true)
            {
                $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()
                $script:lun = ($script:RDMDropDownBox.SelectedItem.ToString()).substring(0,36)
            }
        }
        getFlashArray
        if ($lun -like 'naa.624a9370*')
        {
            $volumes = Get-PfaVolumes -Array $EndPoint
            $volserial = ($lun.ToUpper()).substring(12)
            $script:purevol = $volumes | where-object { $_.serial -eq $volserial }
            if ($purevol -eq $null)
            {
                $outputTextBox.text =  (get-Date -Format G) + " ERROR: Volume not found on connected FlashArray." + ("`r`n") + $outputTextBox.text
            }
            else
            {
                if ($TabControl.SelectedIndex -eq 0)
                {
                    $newSnapshot = New-PfaVolumeSnapshots -Array $EndPoint -Sources $purevol.name -Suffix $newSnapshotTextBox.Text -ErrorAction stop
                    $newSnapshotTextBox.Text = ""
                    $LabelNewSnapError.ForeColor = "Black"
                    $LabelNewSnapError.Text = "$($newSnapshot.Name) ($($newSnapshot.Created))"
                    $buttonNewSnapshot.Enabled = $false
                    getSnapshots
                }
                elseif ($TabControl.SelectedIndex -eq 1)
                {
                    $newSnapshot = New-PfaVolumeSnapshots -Array $EndPoint -Sources $purevol.name -Suffix $newVMSnapshotTextBox.Text -ErrorAction stop
                    $newVMSnapshotTextBox.Text = ""
                    $LabelNewVMSnapError.ForeColor = "Black"
                    $LabelNewVMSnapError.Text = "$($newSnapshot.Name) ($($newSnapshot.Created))"
                    $buttonNewVMSnapshot.Enabled = $false
                    getVMSnapshots
                }    
                $outputTextBox.text = ((get-Date -Format G) + " Created snapshot $($newSnapshot.Name)`r`n$($outputTextBox.text)")
            }
        }
        else
        {
            $outputTextBox.text = (get-Date -Format G) + " Selected datastore is not a FlashArray volume." + ("`r`n") + $outputTextBox.text
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
    }
}
function newVMFS{
    $script:createVMFS = $true
    getHostGroup
    try
    {
        $newvol = New-PfaVolume -Array $endpoints[$ChooseFlashArrayDropDownBox.SelectedIndex-1] -VolumeName $newVMFSTextBox.text -Size $($newVMFSSizeTextBox.text) $($UnitDropDownBox.SelectedItem.ToString())
        $outputTextBox.text = ((get-Date -Format G) + " New FlashArray volume is $($newvol.name)`r`n$($outputTextBox.text)")
        New-PfaHostGroupVolumeConnection -Array $endpoints[$ChooseFlashArrayDropDownBox.SelectedIndex-1] -VolumeName $newvol.name -HostGroupName $hostgroup
        $outputTextBox.text = ((get-Date -Format G) + " Connected volume to host group $($hostgroup)`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
        $esxi = get-cluster -Name $CreateVMFSClusterDropDownBox.SelectedItem.ToString() | Get-VMHost -ErrorAction stop
        $esxi | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
        $newNAA =  "naa.624a9370" + $newvol.serial.toLower()
        $ESXiApiVersion = $esxi[0].ExtensionData.Summary.Config.Product.ApiVersion
        if ($ESXiApiVersion -eq "6.5")
        {
            $outputTextBox.text = ((get-Date -Format G) + " Creating a VMFS 6 datastore...`r`n$($outputTextBox.text)")
            $newVMFS = $esxi[0] |new-datastore -name $newVMFSTextBox.text -vmfs -Path $newNAA -FileSystemVersion 6
        }
        else
        {
            $outputTextBox.text = ((get-Date -Format G) + " Creating a VMFS 5 datastore...`r`n$($outputTextBox.text)")
            $newVMFS = $esxi[0] |new-datastore -name $newVMFSTextBox.text -vmfs -Path $newNAA -FileSystemVersion 5
        }
        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: VMFS datastore $($newVMFSTextBox.text) created.`r`n$($outputTextBox.text)")
        $newVMFSTextBox.Text = "" 
        $newVMFSSizeTextBox.Text = ""
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " FAILED: Datastore creation failed.`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + "  $($Error[0])`r`n$($outputTextBox.text)")
        if ($newvol -ne $null)
        {
            $outputTextBox.text = ((get-Date -Format G) + " Cleaning up volume... $($Error[0])`r`n$($outputTextBox.text)")
            Remove-PfaHostGroupVolumeConnection -Array $endpoints[$ChooseFlashArrayDropDownBox.SelectedIndex-1] -VolumeName $newvol.name -HostGroupName $hostgroup
            Remove-PfaVolumeOrSnapshot -Array $endpoints[$ChooseFlashArrayDropDownBox.SelectedIndex-1] -Name $newvol.name
            Remove-PfaVolumeOrSnapshot -Array $endpoints[$ChooseFlashArrayDropDownBox.SelectedIndex-1] -Name $newvol.name -Eradicate
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)") 
            $esxi | Get-VMHostStorage -RescanAllHba -RescanVMFS 
            $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
        }
    }
    $script:createVMFS = $false
}
function cloneVMFS{
    getFlashArray
    getHostGroup
    try
    {
        $snapshotchoice = $SnapshotDropDownBox.SelectedIndex -1
        $volumename = $purevol.name + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
        $newvol =New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $volumename
        $outputTextBox.text = ((get-Date -Format G) + " New FlashArray volume is $($newvol.name)`r`n$($outputTextBox.text)")
        New-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
        $outputTextBox.text = ((get-Date -Format G) + " Connected volume to host group $($hostgroup)`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
        $cluster =  get-cluster -Name $RecoveryClusterDropDownBox.SelectedItem.ToString() -ErrorAction stop
        $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
        $esxi = $cluster | Get-VMHost -ErrorAction stop
        $esxcli=get-esxcli -VMHost $esxi[0] -v2 -ErrorAction stop
        $resigargs =$esxcli.storage.vmfs.snapshot.list.createargs()
        $sourceds = get-datastore $DatastoreDropDownBox.SelectedItem.ToString()
        $resigargs.volumelabel = $sourceds.Name
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
            $outputTextBox.text = ((get-Date -Format G) + " Resignaturing the VMFS...`r`n$($outputTextBox.text)")
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
            $outputTextBox.text = (get-Date -Format G) + " Presented copied VMFS named " + $resigds.name + ("`r`n") + $outputTextBox.text
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
        $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup recovered datastore...`r`n$($outputTextBox.text)")
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
        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
        $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
        $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
        return
    } 
}
function restoreVMObject{
    getFlashArray
    $cloneObject = $false
    if ($RadioButtonRDM.Checked -eq $false)
    {
        getHostGroup
        try
        {
            $snapshotchoice = $VMSnapshotDropDownBox.SelectedIndex -1
            $volumename = $purevol.name + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
            $newvol =New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $volumename
            $outputTextBox.text = ((get-Date -Format G) + " New FlashArray volume is $($newvol.name)`r`n$($outputTextBox.text)")
            New-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
            $outputTextBox.text = ((get-Date -Format G) + " Connected volume to host group $($hostgroup)`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
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
                $vmdkpath = ($script:VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                $resigargs.volumelabel = ($vmdkpath.Split("]")[0]).substring(1)
            }
            elseif ($sourceds.count -gt 1)
            {
                throw "This VM has more than one datastore and is not a supported configuration for this tool" 
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
                $outputTextBox.text = ((get-Date -Format G) + " Resignaturing the VMFS...`r`n$($outputTextBox.text)")
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
                $outputTextBox.text = (get-Date -Format G) + " Presented copied VMFS named " + $resigds.name + ("`r`n") + $outputTextBox.text
            }
        }
        catch
        {
            $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
            if (($sourceds.count -eq 1) -or ($RadioButtonVMDK.Checked -eq $true))
            {
                $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup recovered datastore...`r`n$($outputTextBox.text)")
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
                Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
 
            }
            return 
        }
        if ($RadioButtonVM.Checked -eq $true)
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
                    $outputTextBox.text = ((get-Date -Format G) + " Registering VM from copied datastore...`r`n$($outputTextBox.text)")
                    $newvm = New-VM -VMHost ($vm |Get-VMHost) -VMFilePath $vmpath -Name ("$($vm.Name)-copy") -ErrorAction stop
                }
                $outputTextBox.text = ((get-Date -Format G) + " Powering on recovered VM...`r`n$($outputTextBox.text)")
                $newvm | start-vm -runasync -ErrorAction stop
                Start-Sleep -Seconds 20
                $newvm | Get-VMQuestion | Set-VMQuestion -DefaultOption -confirm:$false
                $outputTextBox.text = ((get-Date -Format G) + " Removing original VM permanently...`r`n$($outputTextBox.text)")
                Start-Sleep -Seconds 4
                $vm |remove-vm -DeletePermanently -Confirm:$false -ErrorAction stop
                Start-Sleep -Seconds 4
                $newvm = $newvm | set-vm -name $vm.name -Confirm:$false  -ErrorAction stop
                $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The VM has been recovered and the old VM has been deleted`r`n$($outputTextBox.text)")
            }
            catch
            {
                $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
                $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup copied datastore...`r`n$($outputTextBox.text)")
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
                    Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                    $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                    $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                    $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)") 
                } 
                return
            }
            if ($migrateVMCheckBox.Checked -eq $true)
            {
                try
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Moving the VM to the original datastore...`r`n$($outputTextBox.text)")
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
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                        $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The VM has been moved and the temporary datastore has been deleted`r`n$($outputTextBox.text)")
                        $migrateVMCheckBox.Checked = $false
                    }
                }
                catch
                {
                    $outputTextBox.text = ((get-Date -Format G) + "  $($Error[0])`r`n$($outputTextBox.text)")
                    return
                }
            }
        }
        if ($RadioButtonVMDK.Checked -eq $true)
        {
            try
            {
                $filepath = ($VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                $filepath = $filepath.Substring(0,$filepath.Length-1)
                $disk = $vm | get-harddisk |where-object { $_.Filename -eq $filepath } -ErrorAction stop
                $controller = $disk |Get-ScsiController -ErrorAction stop
                $oldname = ($filepath.Split("]")[0]).substring(1)
                $filepath = $filepath -replace $oldname, $resigds.name
                $outputTextBox.text = ((get-Date -Format G) + " Removing old VMDK from VM...`r`n$($outputTextBox.text)")
                $disk | remove-harddisk -DeletePermanently -Confirm:$false -ErrorAction stop
                $outputTextBox.text = ((get-Date -Format G) + " Replacing VMDK from copied datastore...`r`n$($outputTextBox.text)")
                $newDisk = $vm | new-harddisk -DiskPath $filepath -Controller $controller -ErrorAction stop
                $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: VMDK replaced and restored.`r`n$($outputTextBox.text)")
            }
            catch
            {
                $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
                $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup recovered datastore...`r`n$($outputTextBox.text)")
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
                    Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                    $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                    $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                    $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                    $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                } 
                return
            }
            if ($migrateVMCheckBox.Checked -eq $true)
            {
                try
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Moving the VM to the original datastore...`r`n$($outputTextBox.text)")
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
                        $outputTextBox.text = ((get-Date -Format G) + " Removing copied datastore...`r`n$($outputTextBox.text)")
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                        $vm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
                        $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                        $migrateVMCheckBox.Checked = $false
                    }
                }
                catch
                {
                    $outputTextBox.text = ((get-Date -Format G) + "  $($Error[0])`r`n$($outputTextBox.text)")
                    return
                }
            }
        }
    }
}
function restoreRDM{
    getFlashArray
    $cloneObject = $false
    try
    {
        $outputTextBox.text = ((get-Date -Format G) + " Refreshing RDM...`r`n$($outputTextBox.text)")
        $snapshotchoice = $SnapshotDropDownBox.SelectedIndex
        $vm = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
        $naa = (($RDMDropDownBox.SelectedItem.ToString()).substring(0,36))
        $disk = $vm | get-harddisk |where-object { $_.ScsiCanonicalName -eq $naa } -ErrorAction stop
        $controller = $disk |Get-ScsiController -ErrorAction stop 
        $outputTextBox.text = ((get-Date -Format G) + " Temporarily removing RDM from VM...`r`n$($outputTextBox.text)")
        $disk |remove-harddisk -Confirm:$false -DeletePermanently -ErrorAction stop
        $outputTextBox.text = ((get-Date -Format G) + " Removed RDM from VM.`r`n$($outputTextBox.text)") 
        $outputTextBox.text = ((get-Date -Format G) + " Refreshing RDM from snapshot...`r`n$($outputTextBox.text)")
        $newvol = New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $purevol.name -Overwrite
        $outputTextBox.text = ((get-Date -Format G) + " Adding RDM back to VM...`r`n$($outputTextBox.text)") 
        $vm | new-harddisk -DeviceName "/vmfs/devices/disks/$($naa.toLower())" -DiskType RawPhysical -Controller $controller   -ErrorAction stop
        $outputTextBox.text = ((get-Date -Format G) + " Added RDM back to VM.`r`n$($outputTextBox.text)") 
        $outputTextBox.text = (get-Date -Format G) + " COMPLETE: Refreshed RDM on FlashArray volume $($newvol.name) from snapshot $($snapshots[$snapshotchoice].name) `r`n $($outputTextBox.text)"
    }
    catch
    {
        $outputTextBox.text = (get-Date -Format G) + " Failed to refresh RDM on FlashArray volume $($newvol.name) from snapshot $($snapshots[$snapshotchoice].name) `r`n $($outputTextBox.text)"
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
        return
    }
}
function cloneVMObject{
    getFlashArray
    if ($RadioButtonRDM.Checked -eq $false)
    {
        $cloneObject = $true #tells gethostgroup what operation type is going on
        getHostGroup
        $cloneObject = $false
        try
        {
            $snapshotchoice = $VMSnapshotDropDownBox.SelectedIndex -1
            $volumename = $purevol.name + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
            $newvol =New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $volumename
            $outputTextBox.text = ((get-Date -Format G) + " New FlashArray volume is $($newvol.name)`r`n$($outputTextBox.text)")
            New-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
            $outputTextBox.text = ((get-Date -Format G) + " Connected volume to host group $($hostgroup)`r`n$($outputTextBox.text)")
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
            $sourceVM = get-vm -Name $VMDropDownBox.SelectedItem.ToString() -ErrorAction stop
            if ($script:RadioButtonVM.Checked -eq $true)
            {
                $cluster = get-cluster -Name $TargetClusterDropDownBox.SelectedItem.ToString()
                $targetVM = $sourceVM
            }
            elseif($script:RadioButtonVMDK.Checked -eq $true)
            {
                $targetVM = get-vm -Name $TargetVMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                $cluster =  $targetVM |get-cluster
            }
            $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
            $esxi = $cluster | Get-VMHost -ErrorAction stop
            $esxcli=get-esxcli -VMHost $esxi[0] -v2 -ErrorAction stop
            $resigargs =$esxcli.storage.vmfs.snapshot.list.createargs()
            $sourceds = $sourceVM |get-datastore
            if ($sourceds.count -eq 1)
            {
                $resigargs.volumelabel = $sourceds.Name
            }
            elseif ($RadioButtonVMDK.Checked -eq $true)
            {
                $vmdkpath = ($script:VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                $resigargs.volumelabel = ($vmdkpath.Split("]")[0]).substring(1)
            }
            elseif ($sourceds.count -gt 1)
            {
                throw "This VM has more than one datastore and is not a supported configuration for this tool" 
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
                $outputTextBox.text = ((get-Date -Format G) + " Resignaturing the VMFS...`r`n$($outputTextBox.text)")
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
                $outputTextBox.text = (get-Date -Format G) + " Presented copied VMFS named " + $resigds.name + ("`r`n") + $outputTextBox.text
            }
        }
        catch
        {
            $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
            if (($sourceds.count -eq 1) -or ($RadioButtonVMDK.Checked -eq $true))
            {
                $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup recovered datastore...`r`n$($outputTextBox.text)")
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
                Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                $cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
            }
            return 
        }
        if ($RadioButtonVM.Checked -eq $true)
        {
            try
            {
                $vmpath = $sourceVM.extensiondata.Config.Files.VmPathName
                $oldname = ($vmpath.Split("]")[0]).substring(1)
                $vmpath = $vmpath -replace $oldname, $resigds.name 
                $outputTextBox.text = ((get-Date -Format G) + " Registering VM from copied datastore...`r`n$($outputTextBox.text)")
                $newvm = New-VM -VMHost ($esxi[0]) -VMFilePath $vmpath -Name ("$($sourceVM.Name)-copy" + (Get-Random -Minimum 1000 -Maximum 9999)) -ErrorAction stop
                $vmAdapters = $newvm | Get-NetworkAdapter
                foreach ($vmAdapter in $vmAdapters)
                {
                    $vmAdapter.ExtensionData.AddressType = "Generated"
                    $vmAdapter.ExtensionData.MacAddress = ""
                    Set-NetworkAdapter $vmAdapter -confirm:$false
                }
                Remove-VM -VM $newvm -confirm:$false
                $newvm = New-VM -VMHost ($esxi[0]) -VMFilePath $vmpath -Name ("$($sourceVM.Name)-copy" + (Get-Random -Minimum 1000 -Maximum 9999)) -ErrorAction stop
                if ($TargetDatastoreDropDownBox.SelectedItem.ToString() -ne "<Keep on a New Recovery Datastore>")
                {
                    $targetDatastore = get-datastore -name $TargetDatastoreDropDownBox.SelectedItem.ToString()
                }
                else
                {
                    $targetDatastore = $newvm |get-datastore
                }
                $currentDatastore = $newvm |get-datastore
                $migrateVM = $false
                if ($targetDatastore -ne $currentDatastore)
                {
                    $migrateVM = $true
                }
                if ($migrateVM -eq $false)
                {
                    $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: A copy of the VM has been restored `r`n$($outputTextBox.text)")
                }
            }
            catch
            {
                $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
                $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup copied datastore...`r`n$($outputTextBox.text)")
                if ($resigds)
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
                    Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                    $sourceVM = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                    $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                    $sourceVM |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                    $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                } 
                return 
            }
            if ($migrateVM -eq $true)
            {
                try
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Moving the VM to the original datastore...`r`n$($outputTextBox.text)")
                    Move-vm -vm $newvm -Datastore ($targetDatastore) -Confirm:$false -ErrorAction stop
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
                        $outputTextBox.text = ((get-Date -Format G) + " Removing temporary datastore...`r`n$($outputTextBox.text)")
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name 
                        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                        $newvm |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The VM has been moved and the temporary datastore has been deleted`r`n$($outputTextBox.text)")
                    }
                }
                catch
                {
                    $outputTextBox.text = ((get-Date -Format G) + "  $($Error[0])`r`n$($outputTextBox.text)")
                    return
                }
            }
        }
        if ($RadioButtonVMDK.Checked -eq $true)
        {
            try
            {
                Start-Sleep -Seconds 6
                $filepath = ($VMDKDropDownBox.SelectedItem.ToString().Split("(")[0])
                $filepath = $filepath.Substring(0,$filepath.Length-1)
                $disk = $sourceVM | get-harddisk |where-object { $_.Filename -eq $filepath } -ErrorAction stop
                if ($targetVM -eq $sourceVM)
                {
                    $controller = $disk |Get-ScsiController -ErrorAction stop
                }
                else
                {
                    $controller = $targetVM |Get-ScsiController
                    $controller = $controller[0]
                }
                $oldname = ($filepath.Split("]")[0]).substring(1)
                $filepath = $filepath -replace $oldname, $resigds.name
                $outputTextBox.text = ((get-Date -Format G) + " $($filepath)`r`n$($outputTextBox.text)")
                $outputTextBox.text = ((get-Date -Format G) + " Adding VMDK from copied datastore...`r`n$($outputTextBox.text)")
                $vmDisks = $targetvm | get-harddisk
                $vdm = get-view -id (get-view serviceinstance).content.virtualdiskmanager
                $dc=$targetVM |get-datacenter 
                $oldUUID=$vdm.queryvirtualdiskuuid($filePath, $dc.id)
                foreach ($vmDisk in $vmDisks)
                {
                    $currentUUID=$vdm.queryvirtualdiskuuid($vmDisk.Filename, $dc.id)
                    if ($currentUUID -eq $oldUUID)
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " Found duplicate disk UUID on target VM. Assigning a new UUID to the copied VMDK`r`n$($outputTextBox.text)")
                        $firstHalf = $oldUUID.split("-")[0]
                        $testguid=[Guid]::NewGuid()
                        $strGuid=[string]$testguid
                        $arrGuid=$strGuid.split("-")
                        $secondHalfTemp=$arrGuid[3]+$arrGuid[4]
                        $halfUUID=$secondHalfTemp[0]+$secondHalfTemp[1]+" "+$secondHalfTemp[2]+$secondHalfTemp[3]+" "+$secondHalfTemp[4]+$secondHalfTemp[5]+" "+$secondHalfTemp[6]+$secondHalfTemp[7]+" "+$secondHalfTemp[8]+$secondHalfTemp[9]+" "+$secondHalfTemp[10]+$secondHalfTemp[11]+" "+$secondHalfTemp[12]+$secondHalfTemp[13]+" "+$secondHalfTemp[14]+$secondHalfTemp[15]
                        $vdm.setVirtualDiskUuid($filePath, $dc.id, $firstHalf+"-"+$halfUUID)
                        break
                    }
                }
                $newDisk = $targetVM | new-harddisk -DiskPath $filepath -Controller $controller -ErrorAction stop
                $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: VMDK copy added to VM.`r`n$($outputTextBox.text)")
            }
            catch
            {
                $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
                $outputTextBox.text = ((get-Date -Format G) + " Attempting to cleanup copied datastore...`r`n$($outputTextBox.text)")
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
                    Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                    $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                    $targetVM |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                    $outputTextBox.text = ((get-Date -Format G) + " The recovery datastore has been deleted`r`n$($outputTextBox.text)")
                } 
                return
            }
            if ($TargetDatastoreDropDownBox.SelectedItem.ToString() -ne "<Keep on a New Recovery Datastore>")
            {
                try
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Moving the VMDK to the original datastore...`r`n$($outputTextBox.text)")
                    $targetDatastore = get-datastore -name $TargetDatastoreDropDownBox.SelectedItem.ToString()
                    Move-HardDisk -HardDisk $newDisk -Datastore ($targetDatastore) -Confirm:$false -ErrorAction stop
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
                        $outputTextBox.text = ((get-Date -Format G) + " Removing copied datastore...`r`n$($outputTextBox.text)")
                        Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name
                        Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name -Eradicate
                        $targetVM = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
                        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
                        $targetVM |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
                        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The VMDK has been moved and the temporary datastore has been deleted`r`n$($outputTextBox.text)")
                    }
                }
                catch
                {
                    $outputTextBox.text = ((get-Date -Format G) + "  $($Error[0])`r`n$($outputTextBox.text)")
                    return
                }
            }
        }
    }
    if ($RadioButtonRDM.Checked -eq $true)
    {
        getHostGroup
        try
        {
            $snapshotchoice = $VMSnapshotDropDownBox.SelectedIndex -1
            $volumename = $purevol.name + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
            $newvol =New-PfaVolume -Array $endpoint -Source $snapshots[$snapshotchoice].name -VolumeName $volumename
            $outputTextBox.text = ((get-Date -Format G) + " Creating new volume from snapshot...`r`n$($outputTextBox.text)")
            New-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
            $targetVM = get-vm -Name $TargetVMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning host...`r`n$($outputTextBox.text)")
            $targetVM  | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop
            Start-sleep -s 5
            $recoverylun = ("naa.624a9370" + $newvol.serial)
            $naa = (($RDMDropDownBox.SelectedItem.ToString()).substring(0,36))
            $outputTextBox.text = ((get-Date -Format G) + "  $($naa)`r`n$($outputTextBox.text)") 
            $controller = $targetVM|Get-ScsiController -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " Adding copied RDM to VM...`r`n$($outputTextBox.text)")
            $targetVM | new-harddisk -DeviceName "/vmfs/devices/disks/$($recoverylun.toLower())" -DiskType RawPhysical -Controller $controller[0]  -ErrorAction stop
            $outputTextBox.text = (get-Date -Format G) + " COMPLETE: Cloned RDM to FlashArray volume $($newvol.name) from snapshot $($snapshots[$snapshotchoice].name) and added to VM named $($targetVM.name) `r`n $($outputTextBox.text)" 
        }
        catch
        {
            $outputTextBox.text = ((get-Date -Format G) + " Error occurred, removing volume...`r`n$($outputTextBox.text)")
            Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $newvol.name -HostGroupName $hostgroup
            Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newvol.name
            $targetVM = get-vm -Name $VMDropDownBox.SelectedItem.ToString()  -ErrorAction stop
            $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
            $targetVM |get-cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop 
            $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)") 
            return
        }
    }
}
function configureiSCSI{
    if ($HostFlashArrayDropDownBox.SelectedItem.ToString() -eq "Select All FlashArrays")
    {
        $flasharrays = $endpoints
    }
    else
    {
        foreach ($endpoint in $endpoints)
        {
            if ($HostFlashArrayDropDownBox.SelectedItem.ToString() -eq $endpoint.endpoint)
            {
                $flasharrays = $endpoint
            }
        }
    }
    $esxihosts = get-cluster -name $HostClusterDropDownBox.SelectedItem.ToString() |get-vmhost
    $outputTextBox.text = ((get-Date -Format G) + " Configuring software iSCSI for the hosts in the cluster $($clustername) on $($flasharrays.count) FlashArrays`r`n$($outputTextBox.text)") 
    foreach ($flasharray in $flasharrays)
    {
        $faiSCSItargets = Get-PfaNetworkInterfaces -Array $flasharray |Where-Object {$_.services -eq "iscsi"}
        foreach ($esxihost in $esxihosts)
        {
            $outputTextBox.text = ((get-Date -Format G) + " Configuring FlashArray $($flasharray.endpoint) iSCSI targets and FlashArray best practices for $($esxihost.NetworkInfo.HostName)`r`n$($outputTextBox.text)")
            $iscsi = $esxihost |Get-VMHostStorage
            if ($iscsi.SoftwareIScsiEnabled -ne $true)
            {
                $outputTextBox.text = ((get-Date -Format G) + " No software iSCSI adapter found on host. Creating one.`r`n$($outputTextBox.text)")
                $esxihost | get-vmhoststorage |Set-VMHostStorage -SoftwareIScsiEnabled $True |out-null
            }
            $iscsiadapter = $esxihost | Get-VMHostHba -Type iScsi | Where {$_.Model -eq "iSCSI Software Adapter"}
            foreach ($faiSCSItarget in $faiSCSItargets)
            {
                try
                {
                    if (Get-IScsiHbaTarget -IScsiHba $iscsiadapter -Type Send -ErrorAction stop | Where {$_.Address -cmatch $faiSCSItarget.address})
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " NOTICE: The iSCSI target $($faiSCSItarget.address) already exists on the host $($esxihost.NetworkInfo.HostName). Skipping adding target on this host.`r`n$($outputTextBox.text)")
                    }
                    else
                    {
                        New-IScsiHbaTarget -IScsiHba $iscsiadapter -Address $faiSCSItarget.address -ErrorAction stop 
                    }
                    $outputTextBox.text = ((get-Date -Format G) + " Checking FlashArray iSCSI best practices for the target $($faiSCSItarget.address) on host $($esxihost.NetworkInfo.HostName)) If best practices are correct, no more info will be logged.`r`n$($outputTextBox.text)")
                    $esxcli = $esxihost |Get-esxcli -v2 
                    $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.CreateArgs()
                    $iscsiargs.adapter = $iscsiadapter.Device
                    $iscsiargs.address = $faiSCSItarget.address
                    $delayedAck = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "DelayedAck"}
                    $loginTimeout = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "LoginTimeout"}
                    if ($delayedAck.Current -eq "true")
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " DelayedAck not disabled. Disabling.`r`n$($outputTextBox.text)")
                        $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                        $iscsiargs.adapter = $iscsiadapter.Device
                        $iscsiargs.address = $faiSCSItarget.address
                        $iscsiargs.value = "false"
                        $iscsiargs.key = "DelayedAck"
                        $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
                    }
                    if ($loginTimeout.Current -ne "30")
                    {
                        $outputTextBox.text = ((get-Date -Format G) + " LoginTimeout is not set to 30. Setting to 30 seconds.`r`n$($outputTextBox.text)")
                        $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                        $iscsiargs.adapter = $iscsiadapter.Device
                        $iscsiargs.address = $faiSCSItarget.address
                        $iscsiargs.value = "30"
                        $iscsiargs.key = "LoginTimeout"
                        $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
                    }
                    
                }
                catch
                {
                    $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
                }
            }
        }
    }
    $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: iSCSI has been configured for all of the hosts`r`n$($outputTextBox.text)")
}
function createMultipathingrule{
    $esxihosts = get-cluster -name $HostClusterDropDownBox.SelectedItem.ToString() |get-vmhost
    foreach ($esxihost in $esxihosts)
    {
        $outputTextBox.text = ((get-Date -Format G) + " Configuring FlashArray Multipathing Rule for host $($esxihost.NetworkInfo.HostName)`r`n$($outputTextBox.text)") 
        $esxcli = $esxihost |Get-esxcli -v2 
        $rules = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
        $correctrule = 0
        $iopsoption = "iops=1"
        if ($rules.Count -ge 1)
        {
            foreach ($rule in $rules)
            {
                $issuecount = 0
                if ($rule.DefaultPSP -ne "VMW_PSP_RR") 
                {
                    $outputTextBox.text = ((get-Date -Format G) + " The existing Pure Storage FlashArray rule is NOT configured with the correct Path Selection Policy:`r`n$($outputTextBox.text)") 
                    $issuecount = 1
                }
                if ($rule.PSPOptions -ne $iopsoption) 
                {
                    $outputTextBox.text = ((get-Date -Format G) + " The existing Pure Storage FlashArray rule is NOT configured with the correct IO Operations Limit:`r`n$($outputTextBox.text)") 
                    $issuecount = $issuecount + 1
                } 
                if ($rule.Model -ne "FlashArray") 
                {
                    $outputTextBox.text = ((get-Date -Format G) + " The existing Pure Storage FlashArray rule is NOT configured with the correct model:`r`n$($outputTextBox.text)") 
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
                    $esxcli.storage.nmp.satp.rule.remove.invoke($satpArgs)
                    $outputTextBox.text = ((get-Date -Format G) + " *****NOTE: Deleted the rule.*****`r`n$($outputTextBox.text)") 
                }
                else
                {
                    $correctrule = 1
                }
            }
        }
        if ($correctrule -eq 0)
        {  
            $outputTextBox.text = ((get-Date -Format G) + " Creating a new rule to set Round Robin and an IO Operations Limit of 1`r`n$($outputTextBox.text)") 
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
                $newrule = $esxcli.storage.nmp.satp.rule.list.invoke() |where-object {$_.Vendor -eq "PURE"}
            }
            else
            {
                $outputTextBox.text = ((get-Date -Format G) + " ERROR: The rule failed to create. Manual intervention might be required.`r`n$($outputTextBox.text)") 
            }
        }
        else 
        {
            $outputTextBox.text = ((get-Date -Format G) + " A correct SATP rule for the FlashArray exists. No need to create a new one on this host.`r`n$($outputTextBox.text)") 
        }
    }
}
function rescanCluster{
    $esxihosts = get-cluster -Name $PgroupClusterDropDownBox.SelectedItem.ToString() |get-vmhost
    foreach ($esxihost in $esxihosts)
    {
        $argList = @($serverTextBox.Text, $usernameTextBox.Text, $passwordTextBox.Text, $esxihost.name)
                    $job = Start-Job -ScriptBlock{
                        Connect-VIServer -Server $args[0] -username $args[1] -Password $args[2]
                       $temphost = Get-VMHost $args[3]
                        (Get-View $temphost.extensiondata.configManager.storageSystem).RescanAllHba()
                         (Get-View $temphost.extensiondata.configManager.storageSystem).RescanVmfs()
                       Disconnect-VIServer -Confirm:$false
                    } -ArgumentList $argList
    }
    get-job |wait-job
}
function rescanVMFS{
    $esxihosts = get-cluster -Name $PgroupClusterDropDownBox.SelectedItem.ToString() |get-vmhost
    foreach ($esxihost in $esxihosts)
    {
        $argList = @($serverTextBox.Text, $usernameTextBox.Text, $passwordTextBox.Text, $esxihost.name)
                    $job = Start-Job -ScriptBlock{
                        Connect-VIServer -Server $args[0] -username $args[1] -Password $args[2]
                        $temphost = Get-VMHost $args[3]
                        (Get-View $temphost.extensiondata.configManager.storageSystem).RescanVmfs()
                        Disconnect-VIServer -Confirm:$false
                    } -ArgumentList $argList
    }
    get-job |wait-job 
}
function recoverPgroup{
    try
    {
        if ($SnapshotCheckedListBox.GetItemCheckState(0) -eq 'Checked')
        {
            $recoverySnapshots = $script:volumeSnapshots
            if ($recoverySnapshots.count -eq $null)
            {
                $outputTextBox.text = ((get-Date -Format G) + " Recovering 1 out of 1 snapshots in the snapshot group $($script:pgroupsnapshots[$PgroupSnapDropDownBox.SelectedIndex-1].name)`r`n$($outputTextBox.text)")
            }
            else
            {
                $outputTextBox.text = ((get-Date -Format G) + " Recovering $($recoverySnapshots.count) out of $($recoverySnapshots.count) snapshots in the snapshot group $($script:pgroupsnapshots[$PgroupSnapDropDownBox.SelectedIndex-1].name)`r`n$($outputTextBox.text)")
            }
        }
        else
        {
            $recoverySnapshots = @()
            for ($i = 1;$i -lt $SnapshotCheckedListBox.Items.count;$i++)
            {
                if ($SnapshotCheckedListBox.GetItemCheckState($i) -eq 'Checked')
                {
                    $recoverySnapshots += $script:volumeSnapshots[$i-1]
                }
            }
            if (($recoverySnapshots.count -eq $null) -or ($script:volumeSnapshots.count -eq $null))
            {
                $outputTextBox.text = ((get-Date -Format G) + " Recovering $($SnapshotCheckedListBox.CheckedItems.count) out of 1 snapshots in the snapshot group $($script:pgroupsnapshots[$PgroupSnapDropDownBox.SelectedIndex-1].name)`r`n$($outputTextBox.text)")
            }
            else
            {
                $outputTextBox.text = ((get-Date -Format G) + " Recovering $($SnapshotCheckedListBox.CheckedItems.count) out of $($script:volumeSnapshots.count) snapshots in the snapshot group $($script:pgroupsnapshots[$PgroupSnapDropDownBox.SelectedIndex-1].name)`r`n$($outputTextBox.text)")
            }
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
    try
    {
        getHostGroup
        $newVolumes =@()
        foreach ($recoverySnapshot in $recoverySnapshots)
        {
            $suffix = Get-Random -minimum 1 -maximum 99999
            $newName = (($recoverySnapshot.name -split "\.")[2..2] -join ".") + ("--" + $suffix)
            $newVolumes += New-PfaVolume -array $endpoint -source $recoverySnapshot.name -Volumename $newName
            $outputTextBox.text = ((get-Date -Format G) + " Creating volume $($newName) from snapshot $($recoverySnapshot.name)`r`n$($outputTextBox.text)")
            new-pfahostgroupvolumeconnection -array $endpoint -VolumeName $newName -hostgroupname $hostgroup
        }
        $outputTextBox.text = ((get-Date -Format G) + " Rescanning cluster...`r`n$($outputTextBox.text)")
        $cluster =  get-cluster -Name $PgroupClusterDropDownBox.SelectedItem.ToString() -ErrorAction stop
        rescanCluster
        $outputTextBox.text = ((get-Date -Format G) + " Rescan complete.`r`n$($outputTextBox.text)")
        $esxi = $cluster | Get-VMHost -ErrorAction stop
        $hostchoice = get-random -minimum 0 -maximum ($esxi.count-1)
        $esxcli=get-esxcli -VMHost $esxi[$hostchoice] -v2 -ErrorAction stop
        $resigargs =$esxcli.storage.vmfs.snapshot.list.createargs()
        Start-sleep -s 10
        $datastoreSystem = get-view $esxi[$hostchoice].ExtensionData.configManager.datastoreSystem
        $unresolvedvmfs = $datastoreSystem.QueryUnresolvedVmfsVolumes()
        $resigOp =@()
        $resigCount = 0
        $outputTextBox.text = ((get-Date -Format G) + " Identifying unresolved VMFS datastores for $($newVolumes.count) FlashArray volumes...`r`n$($outputTextBox.text)")
        foreach ($newVolume in $newVolumes)
        {
            for ($loopcount = 0; $loopcount -lt $unresolvedvmfs.count; $loopcount++)
            {
                if ($unresolvedvmfs[$loopcount].Extent.count -gt 1)
                {
                    continue
                }
                $unresolvedSerial = ($unresolvedvmfs[$loopcount].Extent[0].Device.DiskName.ToUpper()).substring(12)
                if ($unresolvedSerial -eq $newVolume.serial)
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Found the unresolved volume $($unresolvedvmfs[$loopcount].Extent[0].Device.DiskName)...`r`n$($outputTextBox.text)")
                    $resigOp += $esxcli.storage.vmfs.snapshot.resignature.createargs()
                    $resigOp[$resigCount].volumelabel = $unresolvedvmfs[$loopcount].vmfsLabel
                    break
                }
            }
            if ($resigOp[$resigCount] -eq $null)
            {
                $failAndDelete = $true
                throw "ERROR: Could not find an unresolved VMFS volume for FlashArray volume $($newVolume.name). Exiting process and deleting volume copies."
            }
            $resigCount++
        }
        $outputTextBox.text = ((get-Date -Format G) + " Resignaturing $($resigOp.count) volumes...`r`n$($outputTextBox.text)")
        foreach ($resigOperation in $resigOp)
        {
            $outputTextBox.text = ((get-Date -Format G) + " Resignaturing the VMFS copy $($resigOperation.volumelabel)...`r`n$($outputTextBox.text)")
            $esxcli.storage.vmfs.snapshot.resignature.invoke($resigOperation)
            $outputTextBox.text = ((get-Date -Format G) + " Resignature complete.`r`n$($outputTextBox.text)")
        }
        rescanVMFS
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
        if ($failAndDelete -eq $true)
        {
            foreach ($newVolume in $newVolumes)
            {
                remove-pfahostgroupvolumeconnection -array $endpoint -VolumeName $newVolume.name -hostgroupname $hostgroup
                Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newVolume.name
                Remove-PfaVolumeOrSnapshot -Array $endpoint -Name $newVolume.name -Eradicate
            }
            rescanCluster
        }
    }
    try
    {
        if($registerVMs.Checked -eq $false)
        {
            $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The protection group has been recovered to VMware cluster $($cluster.name)`r`n$($outputTextBox.text)")
        }
        elseif ($registerVMs.Checked -eq $true)
        {
            $outputTextBox.text = ((get-Date -Format G) + " Registering all found virtual machines on recovered datastores...`r`n$($outputTextBox.text)")
            $datastores = $cluster| get-datastore  | where-object {$_.Type -eq "VMFS"}|where-object {$newVolumes.serial -contains (($_.ExtensionData.Info.Vmfs.Extent.DiskName.ToUpper()).substring(12))}
            foreach ($datastore in $datastores)
            {
                $outputTextBox.text = ((get-Date -Format G) + " Registering VMs on VMFS $($datastore.name)`r`n$($outputTextBox.text)")
                $argList = @($serverTextBox.Text, $usernameTextBox.Text, $passwordTextBox.Text, $datastore.name, $cluster.name, $powerOnVMs.Checked)
                $job = Start-Job -ScriptBlock{
                try
                {
                    Connect-VIServer -Server $args[0] -username $args[1] -Password $args[2]
                    $esxi = get-cluster $args[4] |get-vmhost
                    $datastore = get-datastore $args[3]
                    $logname = get-random -minimum 0 -maximum 99999
                    $ds = $datastore | %{Get-View $_.Id}
                    $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
                    $SearchSpec.matchpattern = "*.vmx"
                    $dsBrowser = Get-View $ds.browser
                    $vmxfiles = $dsBrowser.SearchDatastoreSubFolders("[$($ds.Summary.Name)]", $SearchSpec) | %{$_.FolderPath + ($_.File | select Path).Path}
                    foreach($vmxfile in $vmxfiles) 
                    {
                        $hostchoice = get-random -minimum 0 -maximum ($esxi.count-1)
                        $vm = New-VM -VMFilePath $vmxfile -VMHost $esxi[$hostchoice]
                        if ($vmWarnings -ne $null)
                        {
                            $vmWarnings = get-view $vm.ExtensionData.TriggeredAlarmState[0].Alarm
                            foreach ($vmWarning in $vmWarnings)
                            {
                                if ($vmWarning.Info.Description -eq "Default alarm that monitors VM MAC conflicts.")
                                {
                                    Remove-VM -VM $vm -confirm:$false
                                    $vm = New-VM -VMHost ($esxi[$hostchoice]) -VMFilePath $vmxfile -Name $vm.Name -ErrorAction stop 
                                    break
                                }
                            }
                        }
                        if ($args[5] -eq $true)
                        {
                            $vm |start-vm -RunAsync
                        }
                    }               
                    Disconnect-VIServer -Confirm:$false
                    }
                catch
                {
                    ("$($error[0]) $($datastore.name) ")|out-file "c:/puretoolerror-$($logname).log" -Append
                }
                } -ArgumentList $argList
            }
            Get-Job | Wait-Job
            $datastores |get-vm | Get-VMQuestion | Set-VMQuestion -Option ‘button.uuid.copiedTheVM’ -Confirm:$false
            $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: The protection group has been recovered to VMware cluster $($cluster.name)`r`n$($outputTextBox.text)")
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function createPgroupSnap{
    try
    {
        if ($PgroupPGDropDownBox.SelectedItem.ToString() -like "*:*")
        {
            throw "ERROR: This protection group is remote. Snapshots must be initiated from the source FlashArray."
        }
        $pgroup = Get-PfaProtectionGroup -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Name $PgroupPGDropDownBox.SelectedItem.ToString()
        if ($pgroup.targets.count -ne $null)
        {
            $allowedTargets = $false
            foreach ($targetFA in $pgroup.targets)
            {
                if ($targetFA.allowed -eq $true)
                {
                    New-PfaProtectionGroupSnapshot -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Protectiongroupname $PgroupPGDropDownBox.SelectedItem.ToString() -ApplyRetention -ReplicateNow
                    $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Created snapshot, replicated it, and then applied retention`r`n$($outputTextBox.text)")
                    $outputTextBox.text = ((get-Date -Format G) + " NOTICE: It might take some time for replication to complete.`r`n$($outputTextBox.text)")
                    $allowedTargets = $true
                    break
                }
            }
            if ($allowedTargets -eq $false)
            {
                New-PfaProtectionGroupSnapshot -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Protectiongroupname $PgroupPGDropDownBox.SelectedItem.ToString() -ApplyRetention
                $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Created local snapshot and applied retention`r`n$($outputTextBox.text)")
            }
        }
        else
        {
            New-PfaProtectionGroupSnapshot -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Protectiongroupname $PgroupPGDropDownBox.SelectedItem.ToString() -ApplyRetention
            $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Created local snapshot and applied retention`r`n$($outputTextBox.text)")
        }
        getProtectionGroupSnapshots
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function deletePgroupSnap{
    try
    {
        $selectedPiT = $script:pgroupsnapshots[$PgroupSnapDropDownBox.SelectedIndex-1].name
        $deletedPgroupSnapshot = Remove-PfaProtectionGroupOrSnapshot -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -Name $selectedPiT 
        $outputTextBox.text = ((get-Date -Format G) + " COMPLETE: Deleted snapshot group $($deletedPgroupSnapshot.name)`r`n$($outputTextBox.text)")
        getProtectionGroupSnapshots
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
function addToPgroup{
    try
    {
        $vols = Get-PfaVolumes -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] 
        $volumesToAdd = @()
        $existPGvols = Get-PfaProtectionGroup -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -name $PgroupPGDropDownBox.SelectedItem.ToString()
        for ($i = 1;$i -lt $AddToPgroupCheckedListBox.Items.count;$i++)
        {
            if ($AddToPgroupCheckedListBox.GetItemCheckState($i) -eq 'Checked')
            {
                $serial = ($script:datastoresOnFA[$i-1].ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique)
                $serial = ($serial.ToUpper()).substring(12)
                $volMatch = $vols |where-object {$_.serial -eq $serial}
                if ($volMatch -eq $null)
                {
                    $outputTextBox.text = ((get-Date -Format G) + " Could not find the datastore $($script:datastoresOnFA[$i-1].name) Skipping...`r`n$($outputTextBox.text)")
                    continue
                }
                elseif ($existPGvols.volumes -contains $volMatch.name)
                {
                    $outputTextBox.text = ((get-Date -Format G) + " This  protection group already contains datastore $($script:datastoresOnFA[$i-1].name) Skipping...`r`n$($outputTextBox.text)")
                    continue
                }
                else
                {
                    $volumesToAdd += $volMatch.name
                }
            }
        }
        if ($volumesToAdd.count -ne 0)
        {
            $outputTextBox.text = ((get-Date -Format G) + " Adding $($volumesToAdd.count) datastores to the protection group $($PgroupPGDropDownBox.SelectedItem.ToString())...`r`n$($outputTextBox.text)")
            foreach ($volumeToAdd in $volumesToAdd)
            {
                Add-PfaVolumesToProtectionGroup -Array $endpoints[$PgroupFADropDownBox.SelectedIndex-1] -VolumesToAdd $volumeToAdd -Name $PgroupPGDropDownBox.SelectedItem.ToString()
            }
            $outputTextBox.text = ((get-Date -Format G) + " SUCCESS: Added $($volumesToAdd.count) datastores to the protection group $($PgroupPGDropDownBox.SelectedItem.ToString()).`r`n$($outputTextBox.text)")
        }
        else
        {
            $outputTextBox.text = ((get-Date -Format G) + " FAILED: Could not identify any volumes to add to the protection group.`r`n$($outputTextBox.text)")
        }
    }
    catch
    {
        $outputTextBox.text = ((get-Date -Format G) + " $($Error[0])`r`n$($outputTextBox.text)")
    }
}
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
##################Main Form Definition
    
    $main_form = New-Object System.Windows.Forms.Form 
    $main_form.Text = "Pure Storage FlashArray VMware Storage Manager" #Form Title
    $main_form.Size = New-Object System.Drawing.Size(1000,920) 
    $main_form.StartPosition = "CenterScreen"
    $main_form.KeyPreview = $True
    $main_form.AutoScroll = $True
    $main_form.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
    {$main_form.Close()}})

##################Tab Definition

    $TabControl = New-object System.Windows.Forms.TabControl
    $System_Drawing_Point = New-Object System.Drawing.Point
    $System_Drawing_Point.X = 10
    $System_Drawing_Point.Y = 370
    $tabControl.Location = $System_Drawing_Point
    $System_Drawing_Size = New-Object System.Drawing.Size
    $System_Drawing_Size.Height = 340
    $System_Drawing_Size.Width = 960
    $tabControl.Size = $System_Drawing_Size
    $TabControl.add_SelectedIndexChanged({enableObjects})
    $main_form.Controls.Add($tabControl)
    $TabControl.Enabled = $false
    
    $VMFSTab = New-Object System.Windows.Forms.TabPage
    $VMFSTab.Text = "VMFS Management"
    $tabControl.Controls.Add($VMFSTab)

    $VMTab = New-Object System.Windows.Forms.TabPage
    $VMTab.Text = "Virtual Machine Management"
    $tabControl.Controls.Add($VMTab)

    $HostTab = New-Object System.Windows.Forms.TabPage
    $HostTab.Text = "Host Management"
    $tabControl.Controls.Add($HostTab)
    
    $PgrpTab = New-Object System.Windows.Forms.TabPage
    $PgrpTab.Text = "Protection Group Recovery"
    $tabControl.Controls.Add($PgrpTab)


################## Connection GroupBox Definition

    $groupBoxVC = New-Object System.Windows.Forms.GroupBox
    $groupBoxVC.Location = New-Object System.Drawing.Size(10,5) 
    $groupBoxVC.size = New-Object System.Drawing.Size(345,235) 
    $groupBoxVC.text = "Connect to vCenter:" 
    $main_form.Controls.Add($groupBoxVC) 

    $groupBoxFA = New-Object System.Windows.Forms.GroupBox
    $groupBoxFA.Location = New-Object System.Drawing.Size(370,5) 
    $groupBoxFA.size = New-Object System.Drawing.Size(335,235) 
    $groupBoxFA.text = "Connect to FlashArray(s):" 
    $main_form.Controls.Add($groupBoxFA)

    $groupBoxInfo = New-Object System.Windows.Forms.GroupBox
    $groupBoxInfo.Location = New-Object System.Drawing.Size(720,5) 
    $groupBoxInfo.size = New-Object System.Drawing.Size(250,360) 
    $groupBoxInfo.text = "About:" 
    $main_form.Controls.Add($groupBoxInfo)

    $groupBoxRadio = New-Object System.Windows.Forms.GroupBox
    $groupBoxRadio.Location = New-Object System.Drawing.Size(10,245) 
    $groupBoxRadio.size = New-Object System.Drawing.Size(695,120) 
    $groupBoxRadio.text = "Choose Object Type:" 
    $main_form.Controls.Add($groupBoxRadio) 

    $groupBoxChooseHost = New-Object System.Windows.Forms.GroupBox
    $groupBoxChooseHost.Location = New-Object System.Drawing.Size(10,245) 
    $groupBoxChooseHost.size = New-Object System.Drawing.Size(695,120) 
    $groupBoxChooseHost.text = "Choose Cluster and FlashArray:" 

    $groupBoxLog = New-Object System.Windows.Forms.GroupBox
    $groupBoxLog.Location = New-Object System.Drawing.Size(10,725) 
    $groupBoxLog.size = New-Object System.Drawing.Size(960,145) 
    $groupBoxLog.text = "Output:" 
    $main_form.Controls.Add($groupBoxLog)

################## VMFS GroupBox Definition

    $groupBoxVMFS = New-Object System.Windows.Forms.GroupBox
    $groupBoxVMFS.Location = New-Object System.Drawing.Size(10,10) 
    $groupBoxVMFS.size = New-Object System.Drawing.Size(935,95) 
    $groupBoxVMFS.text = "Create New VMFS:" 
    $VMFSTab.Controls.Add($groupBoxVMFS) 

    $groupBoxManageVMFS = New-Object System.Windows.Forms.GroupBox
    $groupBoxManageVMFS.Location = New-Object System.Drawing.Size(10,110) 
    $groupBoxManageVMFS.size = New-Object System.Drawing.Size(930,200) 
    $groupBoxManageVMFS.text = "Manage VMFS Snapshots:" 
    $VMFSTab.Controls.Add($groupBoxManageVMFS) 

    $groupBoxCreateVMFSSnapshot = New-Object System.Windows.Forms.GroupBox
    $groupBoxCreateVMFSSnapshot.Location = New-Object System.Drawing.Size(200,70) 
    $groupBoxCreateVMFSSnapshot.size = New-Object System.Drawing.Size(340,120) 
    $groupBoxCreateVMFSSnapshot.text = "Create FlashArray Snapshot:" 
    $groupBoxManageVMFS.Controls.Add($groupBoxCreateVMFSSnapshot)

    $groupBoxDeleteVMFSSnapshot = New-Object System.Windows.Forms.GroupBox
    $groupBoxDeleteVMFSSnapshot.Location = New-Object System.Drawing.Size(10,70) 
    $groupBoxDeleteVMFSSnapshot.size = New-Object System.Drawing.Size(180,120) 
    $groupBoxDeleteVMFSSnapshot.text = "Delete VMFS/Snapshot:" 
    $groupBoxManageVMFS.Controls.Add($groupBoxDeleteVMFSSnapshot)
    
    $groupBoxVMFSClone = New-Object System.Windows.Forms.GroupBox
    $groupBoxVMFSClone.Location = New-Object System.Drawing.Size(550,70) 
    $groupBoxVMFSClone.size = New-Object System.Drawing.Size(370,120) 
    $groupBoxVMFSClone.text = "Clone VMFS from Snapshot:" 
    $groupBoxManageVMFS.Controls.Add($groupBoxVMFSClone)

################## VM GroupBox Definition

    $groupBoxVM = New-Object System.Windows.Forms.GroupBox
    $groupBoxVM.Location = New-Object System.Drawing.Size(10,10) 
    $groupBoxVM.size = New-Object System.Drawing.Size(540,160) 
    $groupBoxVM.text = "1) Select Virtual Machine Object:" 
    $VMTab.Controls.Add($groupBoxVM) 

    $groupBoxVMSnapshot = New-Object System.Windows.Forms.GroupBox
    $groupBoxVMSnapshot.Location = New-Object System.Drawing.Size(10,180) 
    $groupBoxVMSnapshot.size = New-Object System.Drawing.Size(540,120) 
    $groupBoxVMSnapshot.text = "2) Select Snapshot:" 
    $VMTab.Controls.Add($groupBoxVMSnapshot) 

    $groupBoxDeleteVMObject = New-Object System.Windows.Forms.GroupBox
    $groupBoxDeleteVMObject.Location = New-Object System.Drawing.Size(555,10) 
    $groupBoxDeleteVMObject.size = New-Object System.Drawing.Size(195,90) 
    $groupBoxDeleteVMObject.text = "Delete Virtual Machine:" 
    $VMTab.Controls.Add($groupBoxDeleteVMObject)

    $groupBoxDeleteVMSnapshot = New-Object System.Windows.Forms.GroupBox
    $groupBoxDeleteVMSnapshot.Location = New-Object System.Drawing.Size(755,10) 
    $groupBoxDeleteVMSnapshot.size = New-Object System.Drawing.Size(195,90) 
    $groupBoxDeleteVMSnapshot.text = "Delete Snapshot:" 
    $VMTab.Controls.Add($groupBoxDeleteVMSnapshot)
        
    $groupBoxVMDK = New-Object System.Windows.Forms.GroupBox
    $groupBoxVMDK.Location = New-Object System.Drawing.Size(20,85) 
    $groupBoxVMDK.size = New-Object System.Drawing.Size(500,50) 
    $groupBoxVMDK.text = "Virtual Disk:" 
    
    $groupBoxRDM = New-Object System.Windows.Forms.GroupBox
    $groupBoxRDM.Location = New-Object System.Drawing.Size(20,85) 
    $groupBoxRDM.size = New-Object System.Drawing.Size(500,50) 
    $groupBoxRDM.text = "Raw Device Mapping:" 

    $groupBoxRecoverVM = New-Object System.Windows.Forms.GroupBox
    $groupBoxRecoverVM.Location = New-Object System.Drawing.Size(555,110) 
    $groupBoxRecoverVM.size = New-Object System.Drawing.Size(395,190) 
    $groupBoxRecoverVM.text = "Restore/Clone Virtual Machine:" 
    $VMTab.Controls.Add($groupBoxRecoverVM)
    
    $groupBoxRestoreVM = New-Object System.Windows.Forms.GroupBox
    $groupBoxRestoreVM.Location = New-Object System.Drawing.Size(10,20) 
    $groupBoxRestoreVM.size = New-Object System.Drawing.Size(375,50) 
    $groupBoxRestoreVM.text = "Restore:" 
    $groupBoxRecoverVM.Controls.Add($groupBoxRestoreVM)

    $groupBoxRestoreRDM = New-Object System.Windows.Forms.GroupBox
    $groupBoxRestoreRDM.Location = New-Object System.Drawing.Size(10,20) 
    $groupBoxRestoreRDM.size = New-Object System.Drawing.Size(375,50) 
    $groupBoxRestoreRDM.text = "Restore:" 
    
    $groupBoxCloneVM = New-Object System.Windows.Forms.GroupBox
    $groupBoxCloneVM.Location = New-Object System.Drawing.Size(10,80) 
    $groupBoxCloneVM.size = New-Object System.Drawing.Size(375,100) 
    $groupBoxCloneVM.text = "Clone:" 
    $groupBoxRecoverVM.Controls.Add($groupBoxCloneVM)

    ################## Host GroupBox Definition

    $groupBoxiSCSI = New-Object System.Windows.Forms.GroupBox
    $groupBoxiSCSI.Location = New-Object System.Drawing.Size(220,20) 
    $groupBoxiSCSI.size = New-Object System.Drawing.Size(200,100) 
    $groupBoxiSCSI.text = "iSCSI Setup:" 
    $HostTab.Controls.Add($groupBoxiSCSI) 

    $groupBoxHGroup = New-Object System.Windows.Forms.GroupBox
    $groupBoxHGroup.Location = New-Object System.Drawing.Size(10,20) 
    $groupBoxHGroup.size = New-Object System.Drawing.Size(200,100) 
    $groupBoxHGroup.text = "Host Group Creation:" 
    $HostTab.Controls.Add($groupBoxHGroup) 

    $groupBoxAddHost = New-Object System.Windows.Forms.GroupBox
    $groupBoxAddHost.Location = New-Object System.Drawing.Size(10,130) 
    $groupBoxAddHost.size = New-Object System.Drawing.Size(200,160) 
    $groupBoxAddHost.text = "Add New ESXi Host to Host Group:" 
    $HostTab.Controls.Add($groupBoxAddHost)

    $groupBoxMultipathing = New-Object System.Windows.Forms.GroupBox
    $groupBoxMultipathing.Location = New-Object System.Drawing.Size(430,20) 
    $groupBoxMultipathing.size = New-Object System.Drawing.Size(200,100) 
    $groupBoxMultipathing.text = "ESXi Multipathing Configuration:" 
    $HostTab.Controls.Add($groupBoxMultipathing) 

    ################## Pgroup GroupBox Definition

    $groupBoxFilterPgroup = New-Object System.Windows.Forms.GroupBox
    $groupBoxFilterPgroup.Location = New-Object System.Drawing.Size(10,245) 
    $groupBoxFilterPgroup.size = New-Object System.Drawing.Size(695,120) 
    $groupBoxFilterPgroup.text = "Filter Protection Groups:" 

    $groupBoxPgrp = New-Object System.Windows.Forms.GroupBox
    $groupBoxPgrp.Location = New-Object System.Drawing.Size(10,10) 
    $groupBoxPgrp.size = New-Object System.Drawing.Size(730,290) 
    $groupBoxPgrp.text = "Recover Volumes from Protection Group:" 
    $PgrpTab.Controls.Add($groupBoxPgrp) 

    $groupBoxVMFSPgrp = New-Object System.Windows.Forms.GroupBox
    $groupBoxVMFSPgrp.Location = New-Object System.Drawing.Size(750,10) 
    $groupBoxVMFSPgrp.size = New-Object System.Drawing.Size(195,290) 
    $groupBoxVMFSPgrp.text = "Add Datastores to Group:" 
    $PgrpTab.Controls.Add($groupBoxVMFSPgrp) 


    ################## Host Radio Select Definition

    $RadioButtoniSCSI = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtoniSCSI.Location = new-object System.Drawing.Point(10,30) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtoniSCSI.size = New-Object System.Drawing.Size(60,20) #the size in px of the radio button (length, height)
    $RadioButtoniSCSI.Text = "iSCSI" #labeling the radio button
    $RadioButtoniSCSI.Enabled = $false
    $groupBoxHGroup.Controls.Add($RadioButtoniSCSI) #activate the inside the group box

    $RadioButtonFC = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonFC.Location = new-object System.Drawing.Point(90,30) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonFC.size = New-Object System.Drawing.Size(100,20) #the size in px of the radio button (length, height)
    $RadioButtonFC.Text = "Fibre Channel" #labeling the radio button
    $RadioButtonFC.Enabled = $false
    $groupBoxHGroup.Controls.Add($RadioButtonFC) #activate the inside the group box

    $RadioButtonHostiSCSI = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonHostiSCSI.Location = new-object System.Drawing.Point(10,30) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonHostiSCSI.size = New-Object System.Drawing.Size(60,20) #the size in px of the radio button (length, height)
    $RadioButtonHostiSCSI.Text = "iSCSI" #labeling the radio button
    $RadioButtonHostiSCSI.Enabled = $false
    $groupBoxAddHost.Controls.Add($RadioButtonHostiSCSI) #activate the inside the group box

    $RadioButtonHostFC = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonHostFC.Location = new-object System.Drawing.Point(90,30) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonHostFC.size = New-Object System.Drawing.Size(100,20) #the size in px of the radio button (length, height)
    $RadioButtonHostFC.Text = "Fibre Channel" #labeling the radio button
    $RadioButtonHostFC.Enabled = $false
    $groupBoxAddHost.Controls.Add($RadioButtonHostFC) #activate the inside the group box


    ##################VM Radio Select Definition

    $RadioButtonVM = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonVM.Location = new-object System.Drawing.Point(20,22) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonVM.size = New-Object System.Drawing.Size(150,20) #the size in px of the radio button (length, height)
    $RadioButtonVM.Text = "Entire Virtual Machine" #labeling the radio button
    $RadioButtonVM.Enabled = $false
    $RadioButtonVM.add_CheckedChanged({radioSelectChanged})
    $groupBoxVM.Controls.Add($RadioButtonVM) #activate the inside the group box

    $RadioButtonVMDK = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonVMDK.Location = new-object System.Drawing.Point(170,22) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonVMDK.size = New-Object System.Drawing.Size(130,20) #the size in px of the radio button (length, height)
    $RadioButtonVMDK.Text = "Specific Virtual Disk" #labeling the radio button
    $RadioButtonVMDK.Enabled = $false
    $RadioButtonVMDK.add_CheckedChanged({radioSelectChanged})
    $groupBoxVM.Controls.Add($RadioButtonVMDK) #activate the inside the group box

    $RadioButtonRDM = New-Object System.Windows.Forms.RadioButton #create the radio button
    $RadioButtonRDM.Location = new-object System.Drawing.Point(320,22) #location of the radio button(px) in relation to the group box's edges (length, height)
    $RadioButtonRDM.size = New-Object System.Drawing.Size(180,20) #the size in px of the radio button (length, height)
    $RadioButtonRDM.Text = "Specific Raw Device Mapping" #labeling the radio button
    $RadioButtonRDM.Enabled = $false
    $RadioButtonRDM.add_CheckedChanged({radioSelectChanged})
    $groupBoxVM.Controls.Add($RadioButtonRDM) #activate the inside the group box

################## Connection Label Definition

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
    $LabelFA.Location = New-Object System.Drawing.Point(10, 50)
    $LabelFA.Size = New-Object System.Drawing.Size(120, 14)
    $LabelFA.Text = "IP Address or FQDN:"
    $groupBoxFA.Controls.Add($LabelFA)
    
    $LabelFAuser = New-Object System.Windows.Forms.Label
    $LabelFAuser.Location = New-Object System.Drawing.Point(10, 100)
    $LabelFAuser.Size = New-Object System.Drawing.Size(120, 14)
    $LabelFAuser.Text = "Username:"
    $groupBoxFA.Controls.Add($LabelFAuser) 

    $LabelFApass = New-Object System.Windows.Forms.Label
    $LabelFApass.Location = New-Object System.Drawing.Point(10, 150)
    $LabelFApass.Size = New-Object System.Drawing.Size(120, 14)
    $LabelFApass.Text = "Password:"
    $groupBoxFA.Controls.Add($LabelFApass) 

    $LabelAbout = New-Object System.Windows.Forms.Label
    $LabelAbout.Location = New-Object System.Drawing.Point(10, 20)
    $LabelAbout.Size = New-Object System.Drawing.Size(190, 300)
    $LabelAbout.Text = "Pure Storage FlashArray VMware Storage Manager`r`n`r`nVersion 2.8.0`r`n`r`nBy Cody Hosterman`r`n`r`nwww.codyhosterman.com`r`n`r`n@codyhosterman`r`n`r`nRequires:`r`n---------------------------------------`r`nVMware PowerCLI 6.3+`r`n`r`nPure Storage PowerShell SDK 1.7+`r`n`r`nFlashArray//M or`r`n`r`nFlashArray 400 Series`r`n`r`nhttps://github.com/codyhosterman/powercli/blob/master/PureStorageVMwareStorageTool.ps1"
    $groupBoxInfo.Controls.Add($LabelAbout)  

    $LabelClusterFilter = New-Object System.Windows.Forms.Label
    $LabelClusterFilter.Location = New-Object System.Drawing.Point(10, 52)
    $LabelClusterFilter.Size = New-Object System.Drawing.Size(80, 14)
    $LabelClusterFilter.Text = "Cluster Filter:"
    $groupBoxRadio.Controls.Add($LabelClusterFilter)  

    $LabelExplainFilter = New-Object System.Windows.Forms.Label
    $LabelExplainFilter.Location = New-Object System.Drawing.Point(10, 22)
    $LabelExplainFilter.Size = New-Object System.Drawing.Size(500, 14)
    $LabelExplainFilter.Text = "Optionally choose a cluster to filter VMFS/VM results and/or a string to filter by the VMFS/VM name."
    $groupBoxRadio.Controls.Add($LabelExplainFilter) 

    $LabelNameFilter = New-Object System.Windows.Forms.Label
    $LabelNameFilter.Location = New-Object System.Drawing.Point(10, 87)
    $LabelNameFilter.Size = New-Object System.Drawing.Size(70, 14)
    $LabelNameFilter.Text = "Name Filter:"
    $groupBoxRadio.Controls.Add($LabelNameFilter)

################## VMFS Label Definition

    $LabelCluster = New-Object System.Windows.Forms.Label
    $LabelCluster.Location = New-Object System.Drawing.Point(410, 62)
    $LabelCluster.Size = New-Object System.Drawing.Size(80, 28)
    $LabelCluster.Text = "Target Cluster:"
    $groupBoxVMFS.Controls.Add($LabelCluster)

    $LabelCluster = New-Object System.Windows.Forms.Label
    $LabelCluster.Location = New-Object System.Drawing.Point(10, 40)
    $LabelCluster.Size = New-Object System.Drawing.Size(80, 28)
    $LabelCluster.Text = "Target Cluster:"
    $groupBoxVMFSClone.Controls.Add($LabelCluster)

    $LabelNewSnapError = New-Object System.Windows.Forms.Label
    $LabelNewSnapError.Location = New-Object System.Drawing.Point(10, 69)
    $LabelNewSnapError.Size = New-Object System.Drawing.Size(400, 13)
    $LabelNewSnapError.Text = ""
    $groupBoxCreateVMFSSnapshot.Controls.Add($LabelNewSnapError)

    $LabelNewSnap = New-Object System.Windows.Forms.Label
    $LabelNewSnap.Location = New-Object System.Drawing.Point(10, 23)
    $LabelNewSnap.Size = New-Object System.Drawing.Size(110, 14)
    $LabelNewSnap.Text = "New snapshot name:"
    $groupBoxCreateVMFSSnapshot.Controls.Add($LabelNewSnap)

    $LabelNewVMFSError = New-Object System.Windows.Forms.Label
    $LabelNewVMFSError.Location = New-Object System.Drawing.Point(95, 42)
    $LabelNewVMFSError.Size = New-Object System.Drawing.Size(400, 14)
    $LabelNewVMFSError.Text = ""
    $groupBoxVMFS.Controls.Add($LabelNewVMFSError)

    $LabelNewVMFSSizeError = New-Object System.Windows.Forms.Label
    $LabelNewVMFSSizeError.Location = New-Object System.Drawing.Point(490, 42)
    $LabelNewVMFSSizeError.Size = New-Object System.Drawing.Size(400, 14)
    $LabelNewVMFSSizeError.Text = ""
    $groupBoxVMFS.Controls.Add($LabelNewVMFSSizeError)

    $LabelNewVMFS = New-Object System.Windows.Forms.Label
    $LabelNewVMFS.Location = New-Object System.Drawing.Point(10, 23)
    $LabelNewVMFS.Size = New-Object System.Drawing.Size(76, 14)
    $LabelNewVMFS.Text = "Name:"
    $groupBoxVMFS.Controls.Add($LabelNewVMFS)

    $LabelChooseFA = New-Object System.Windows.Forms.Label
    $LabelChooseFA.Location = New-Object System.Drawing.Point(10, 62)
    $LabelChooseFA.Size = New-Object System.Drawing.Size(66, 14)
    $LabelChooseFA.Text = "FlashArray:"
    $groupBoxVMFS.Controls.Add($LabelChooseFA)

    $LabelNewVMFSSize = New-Object System.Windows.Forms.Label
    $LabelNewVMFSSize.Location = New-Object System.Drawing.Point(410, 23)
    $LabelNewVMFSSize.Size = New-Object System.Drawing.Size(60, 14)
    $LabelNewVMFSSize.Text = "Capacity:"
    $groupBoxVMFS.Controls.Add($LabelNewVMFSSize)

    $LabelChooseVMFS = New-Object System.Windows.Forms.Label
    $LabelChooseVMFS.Location = New-Object System.Drawing.Point(10, 24)
    $LabelChooseVMFS.Size = New-Object System.Drawing.Size(73, 14)
    $LabelChooseVMFS.Text = "Select VMFS:"
    $groupBoxManageVMFS.Controls.Add($LabelChooseVMFS)

    $LabelChooseSnapshot = New-Object System.Windows.Forms.Label
    $LabelChooseSnapshot.Location = New-Object System.Drawing.Point(395, 24)
    $LabelChooseSnapshot.Size = New-Object System.Drawing.Size(90, 14)
    $LabelChooseSnapshot.Text = "Select Snapshot:"
    $groupBoxManageVMFS.Controls.Add($LabelChooseSnapshot)

################## VM Label Definition

    $LabelVM = New-Object System.Windows.Forms.Label
    $LabelVM.Location = New-Object System.Drawing.Point(10, 60)
    $LabelVM.Size = New-Object System.Drawing.Size(50, 14)
    $LabelVM.Text = "Select:"
    $groupBoxVM.Controls.Add($LabelVM)

    $LabelChooseVMSnapshot = New-Object System.Windows.Forms.Label
    $LabelChooseVMSnapshot.Location = New-Object System.Drawing.Point(10, 30)
    $LabelChooseVMSnapshot.Size = New-Object System.Drawing.Size(50, 14)
    $LabelChooseVMSnapshot.Text = "Select:"
    $groupBoxVMSnapshot.Controls.Add($LabelChooseVMSnapshot)

    $LabelNewVMSnap = New-Object System.Windows.Forms.Label
    $LabelNewVMSnap.Location = New-Object System.Drawing.Point(10, 73)
    $LabelNewVMSnap.Size = New-Object System.Drawing.Size(110, 14)
    $LabelNewVMSnap.Text = "New snapshot name:"
    $groupBoxVMSnapshot.Controls.Add($LabelNewVMSnap)

    $LabelNewVMSnapError = New-Object System.Windows.Forms.Label
    $LabelNewVMSnapError.Location = New-Object System.Drawing.Point(130, 92)
    $LabelNewVMSnapError.Size = New-Object System.Drawing.Size(300, 13)
    $LabelNewVMSnapError.Text = ""
    $groupBoxVMSnapshot.Controls.Add($LabelNewVMSnapError)

    $LabelTargetVM = New-Object System.Windows.Forms.Label
    $LabelTargetVM.Size = New-Object System.Drawing.Size(80, 14)
    $LabelTargetVM.Text = "Target VM:"

    $LabelTargetDatastore = New-Object System.Windows.Forms.Label
    $LabelTargetDatastore.Size = New-Object System.Drawing.Size(80, 14)
    $LabelTargetDatastore.Text = "Target VMFS:"

    $LabelTargetCluster = New-Object System.Windows.Forms.Label
    $LabelTargetCluster.Size = New-Object System.Drawing.Size(80, 14)
    $LabelTargetCluster.Text = "Target Cluster:"

    ################## Host Label Definition

    $LabelClusterConfig = New-Object System.Windows.Forms.Label
    $LabelClusterConfig.Location = New-Object System.Drawing.Point(10, 40)
    $LabelClusterConfig.Size = New-Object System.Drawing.Size(80, 14)
    $LabelClusterConfig.Text = "Select Cluster:"
    $groupBoxChooseHost.Controls.Add($LabelClusterConfig)

    $LabelFlashArrayConfig = New-Object System.Windows.Forms.Label
    $LabelFlashArrayConfig.Location = New-Object System.Drawing.Point(10, 77)
    $LabelFlashArrayConfig.Size = New-Object System.Drawing.Size(105, 14)
    $LabelFlashArrayConfig.Text = "Select FlashArray:"
    $groupBoxChooseHost.Controls.Add($LabelFlashArrayConfig)

    $LabeliSCSI = New-Object System.Windows.Forms.Label
    $LabeliSCSI.Location = New-Object System.Drawing.Point(10, 15)
    $LabeliSCSI.Size = New-Object System.Drawing.Size(180, 50)
    $LabeliSCSI.Text = "Creates Software iSCSI Adapter (if needed) adds FlashArray iSCSI targets with best practices (delayedAck and LoginTimeout):"
    $groupBoxiSCSI.Controls.Add($LabeliSCSI)

    $LabelChooseHost = New-Object System.Windows.Forms.Label
    $LabelChooseHost.Location = New-Object System.Drawing.Point(10, 70)
    $LabelChooseHost.Size = New-Object System.Drawing.Size(180, 20)
    $LabelChooseHost.Text = "Choose an ESXi host:"
    $groupBoxAddHost.Controls.Add($LabelChooseHost)

    $LabSATP = New-Object System.Windows.Forms.Label
    $LabSATP.Location = New-Object System.Drawing.Point(10, 15)
    $LabSATP.Size = New-Object System.Drawing.Size(180, 50)
    $LabSATP.Text = "Creates FlashArray default multipathing rule on hosts in cluster (Round Robin & IO Operations Limit to 1):"
    $groupBoxMultipathing.Controls.Add($LabSATP)

    ################## Pgroup Label Definition

    $LabelPgroupFA = New-Object System.Windows.Forms.Label
    $LabelPgroupFA.Location = New-Object System.Drawing.Point(10, 40)
    $LabelPgroupFA.Size = New-Object System.Drawing.Size(100, 14)
    $LabelPgroupFA.Text = "Select FlashArray:"
    $groupBoxFilterPgroup.Controls.Add($LabelPgroupFA)

    $LabelChoosePG = New-Object System.Windows.Forms.Label
    $LabelChoosePG.Location = New-Object System.Drawing.Point(10, 30)
    $LabelChoosePG.Size = New-Object System.Drawing.Size(130, 14)
    $LabelChoosePG.Text = "Select Protection Group:"
    $groupBoxPgrp.Controls.Add($LabelChoosePG)

    $LabelChoosePiT = New-Object System.Windows.Forms.Label
    $LabelChoosePiT.Location = New-Object System.Drawing.Point(10, 60)
    $LabelChoosePiT.Size = New-Object System.Drawing.Size(130, 14)
    $LabelChoosePiT.Text = "Select Point-in-Time:"
    $groupBoxPgrp.Controls.Add($LabelChoosePiT)

    $LabelChooseSnap = New-Object System.Windows.Forms.Label
    $LabelChooseSnap.Location = New-Object System.Drawing.Point(10, 90)
    $LabelChooseSnap.Size = New-Object System.Drawing.Size(130, 28)
    $LabelChooseSnap.Text = "Select Volume(s) to Recover:"
    $groupBoxPgrp.Controls.Add($LabelChooseSnap)

    $LabelChooseClusterPgrp = New-Object System.Windows.Forms.Label
    $LabelChooseClusterPgrp.Location = New-Object System.Drawing.Point(10, 180)
    $LabelChooseClusterPgrp.Size = New-Object System.Drawing.Size(130, 14)
    $LabelChooseClusterPgrp.Text = "Select Cluster:"
    $groupBoxPgrp.Controls.Add($LabelChooseClusterPgrp)

##################Connection Button Definition

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
    $buttonDisconnect.Left=235
    $buttonDisconnect.Enabled = $false #Disabled by default
    $groupBoxVC.Controls.Add($buttonDisconnect) #Member of groupBoxVC

    $flasharrayButtonConnect = New-Object System.Windows.Forms.Button
    $flasharrayButtonConnect.add_click({connectFlashArray})
    $flasharrayButtonConnect.Text = "Connect"
    $flasharrayButtonConnect.Top=200
    $flasharrayButtonConnect.Left=7
    $flasharrayButtonConnect.Enabled = $false #Disabled by default
    $groupBoxFA.Controls.Add($flasharrayButtonConnect) #Member of groupBoxFA

    $flasharrayButtonDisconnect = New-Object System.Windows.Forms.Button
    $flasharrayButtonDisconnect.add_click({disconnectFlashArray})
    $flasharrayButtonDisconnect.Text = "Disconnect"
    $flasharrayButtonDisconnect.Top=200
    $flasharrayButtonDisconnect.Left=235
    $flasharrayButtonDisconnect.Enabled = $false #Disabled by default
    $groupBoxFA.Controls.Add($flasharrayButtonDisconnect) #Member of groupBoxFA

    ##################VMFS Button Definition

    $buttonDatastores = New-Object System.Windows.Forms.Button
    $buttonDatastores.add_click({getDatastores})
    $buttonDatastores.Text = "Refresh"
    $buttonDatastores.Top=20
    $buttonDatastores.Left=330
    $buttonDatastores.Width=55
    $buttonDatastores.Enabled = $false #Disabled by default
    $groupBoxManageVMFS.Controls.Add($buttonDatastores)

    $buttonDeleteVMFS = New-Object System.Windows.Forms.Button
    $buttonDeleteVMFS.add_click({deleteVMFS})
    $buttonDeleteVMFS.Text = "Delete VMFS"
    $buttonDeleteVMFS.Top=70
    $buttonDeleteVMFS.Left=40
    $buttonDeleteVMFS.Width=100
    $buttonDeleteVMFS.Enabled = $false #Disabled by default
    $groupBoxDeleteVMFSSnapshot.Controls.Add($buttonDeleteVMFS)
      
    $buttonSnapshots = New-Object System.Windows.Forms.Button
    $buttonSnapshots.add_click({getSnapshots})
    $buttonSnapshots.Text = "Refresh"
    $buttonSnapshots.Top=20
    $buttonSnapshots.Left=865
    $buttonSnapshots.Width=55
    $buttonSnapshots.Enabled = $false #Disabled by default
    $groupBoxManageVMFS.Controls.Add($buttonSnapshots) 

    $buttonNewSnapshot = New-Object System.Windows.Forms.Button
    $buttonNewSnapshot.add_click({newSnapshot})
    $buttonNewSnapshot.Text = "Create Snapshot"
    $buttonNewSnapshot.Top=85
    $buttonNewSnapshot.Left=210
    $buttonNewSnapshot.Width=100
    $buttonNewSnapshot.Enabled = $false #Disabled by default
    $groupBoxCreateVMFSSnapshot.Controls.Add($buttonNewSnapshot) 

    $buttonNewVMFS = New-Object System.Windows.Forms.Button
    $buttonNewVMFS.add_click({newVMFS})
    $buttonNewVMFS.Text = "Create VMFS"
    $buttonNewVMFS.Top=59
    $buttonNewVMFS.Left=815
    $buttonNewVMFS.Width=85
    $buttonNewVMFS.Enabled = $false #Disabled by default
    $groupBoxVMFS.Controls.Add($buttonNewVMFS) 
    
    $buttonRecover = New-Object System.Windows.Forms.Button
    $buttonRecover.add_click({cloneVMFS})
    $buttonRecover.Text = "Clone VMFS"
    $buttonRecover.Top=80
    $buttonRecover.Left=110
    $buttonRecover.Width=120
    $buttonRecover.Enabled = $false #Disabled by default
    $groupBoxVMFSClone.Controls.Add($buttonRecover) 

    $buttonDelete = New-Object System.Windows.Forms.Button
    $buttonDelete.add_click({deleteSnapshot})
    $buttonDelete.Text = "Delete Snapshot"
    $buttonDelete.Top=30
    $buttonDelete.Left=40
    $buttonDelete.Width=100
    $buttonDelete.Enabled = $false #Disabled by default
    $groupBoxDeleteVMFSSnapshot.Controls.Add($buttonDelete) 

    ##################VM Button Definition

    $buttonVMs = New-Object System.Windows.Forms.Button
    $buttonVMs.add_click({getVMs})
    $buttonVMs.Text = "Refresh"
    $buttonVMs.Top=54
    $buttonVMs.Left=475
    $buttonVMs.Width=55
    $buttonVMs.Enabled = $false #Disabled by default
    $groupBoxVM.Controls.Add($buttonVMs) 

    $buttonNewVMSnapshot = New-Object System.Windows.Forms.Button
    $buttonNewVMSnapshot.add_click({newSnapshot})
    $buttonNewVMSnapshot.Text = "Create Snapshot"
    $buttonNewVMSnapshot.Top=69
    $buttonNewVMSnapshot.Left=430
    $buttonNewVMSnapshot.Width=100
    $buttonNewVMSnapshot.Enabled = $false #Disabled by default
    $groupBoxVMSnapshot.Controls.Add($buttonNewVMSnapshot) 

    $buttonDeleteVM = New-Object System.Windows.Forms.Button
    $buttonDeleteVM.add_click({deleteVMObject})
    $buttonDeleteVM.Text = "Delete VM"
    $buttonDeleteVM.Top=55
    $buttonDeleteVM.Left=55
    $buttonDeleteVM.Width=90
    $buttonDeleteVM.Enabled = $false #Disabled by default
    $groupBoxDeleteVMObject.Controls.Add($buttonDeleteVM) 

    $buttonDeleteVMSnapshot = New-Object System.Windows.Forms.Button
    $buttonDeleteVMSnapshot.add_click({deleteVMsnapshot})
    $buttonDeleteVMSnapshot.Text = "Delete Snapshot"
    $buttonDeleteVMSnapshot.Top=55
    $buttonDeleteVMSnapshot.Left=45
    $buttonDeleteVMSnapshot.Width=100
    $buttonDeleteVMSnapshot.Enabled = $false #Disabled by default
    $groupBoxDeleteVMSnapshot.Controls.Add($buttonDeleteVMSnapshot) 

    $buttonGetVMSnapshots = New-Object System.Windows.Forms.Button
    $buttonGetVMSnapshots.add_click({getVMSnapshots})
    $buttonGetVMSnapshots.Text = "Refresh"
    $buttonGetVMSnapshots.Top=24
    $buttonGetVMSnapshots.Left=475
    $buttonGetVMSnapshots.Width=55
    $buttonGetVMSnapshots.Enabled = $false #Disabled by default
    $groupBoxVMSnapshot.Controls.Add($buttonGetVMSnapshots)

    $buttonRestoreVM = New-Object System.Windows.Forms.Button
    $buttonRestoreVM.add_click({restoreVMObject})
    $buttonRestoreVM.Text = "Restore from Snapshot"
    $buttonRestoreVM.Top=17
    $buttonRestoreVM.Left=235
    $buttonRestoreVM.Width=130
    $buttonRestoreVM.Enabled = $false #Disabled by default
    $groupBoxRestoreVM.Controls.Add($buttonRestoreVM)

    $buttonRestoreRDM = New-Object System.Windows.Forms.Button
    $buttonRestoreRDM.add_click({restoreRDM})
    $buttonRestoreRDM.Text = "Restore from Snapshot"
    $buttonRestoreRDM.Top=17
    $buttonRestoreRDM.Left=135
    $buttonRestoreRDM.Width=130
    $buttonRestoreRDM.Enabled = $false #Disabled by default
    $groupBoxRestoreRDM.Controls.Add($buttonRestoreRDM)

    $buttonCloneVM = New-Object System.Windows.Forms.Button
    $buttonCloneVM.add_click({cloneVMObject})
    $buttonCloneVM.Text = "Clone from Snapshot"
    $buttonCloneVM.Top=70
    $buttonCloneVM.Left=100
    $buttonCloneVM.Width=130
    $buttonCloneVM.Enabled = $false #Disabled by default
    $groupBoxCloneVM.Controls.Add($buttonCloneVM)

     ##################Host Button Definition

    $buttonCreateHostGroup = New-Object System.Windows.Forms.Button
    $buttonCreateHostGroup.add_click({createHostGroup})
    $buttonCreateHostGroup.Text = "Create Host Group"
    $buttonCreateHostGroup.Top=71
    $buttonCreateHostGroup.Left=35
    $buttonCreateHostGroup.Width=120
    $buttonCreateHostGroup.Enabled = $false #Disabled by default
    $groupBoxHGroup.Controls.Add($buttonCreateHostGroup) 

    $buttonAddHosts = New-Object System.Windows.Forms.Button
    $buttonAddHosts.add_click({addHost})
    $buttonAddHosts.Text = "Add Host"
    $buttonAddHosts.Top=131
    $buttonAddHosts.Left=35
    $buttonAddHosts.Width=120
    $buttonAddHosts.Enabled = $false #Disabled by default
    $groupBoxAddHost.Controls.Add($buttonAddHosts) 

    $buttonConfigureiSCSI = New-Object System.Windows.Forms.Button
    $buttonConfigureiSCSI.add_click({configureiSCSI})
    $buttonConfigureiSCSI.Text = "Configure iSCSI"
    $buttonConfigureiSCSI.Top=71
    $buttonConfigureiSCSI.Left=34
    $buttonConfigureiSCSI.Width=120
    $buttonConfigureiSCSI.Enabled = $false #Disabled by default
    $groupBoxiSCSI.Controls.Add($buttonConfigureiSCSI) 

    $buttonConfigureSATP = New-Object System.Windows.Forms.Button
    $buttonConfigureSATP.add_click({createMultipathingrule})
    $buttonConfigureSATP.Text = "Configure Rule"
    $buttonConfigureSATP.Top=71
    $buttonConfigureSATP.Left=34
    $buttonConfigureSATP.Width=120
    $buttonConfigureSATP.Enabled = $false #Disabled by default
    $groupBoxMultipathing.Controls.Add($buttonConfigureSATP)

    ##################Pgroup Button Definition

    $buttonRecoverPgroup = New-Object System.Windows.Forms.Button
    $buttonRecoverPgroup.add_click({recoverPgroup})
    $buttonRecoverPgroup.Text = "Recover"
    $buttonRecoverPgroup.Top=250
    $buttonRecoverPgroup.Left=300
    $buttonRecoverPgroup.Width=100
    $buttonRecoverPgroup.Enabled = $false #Disabled by default
    $groupBoxPgrp.Controls.Add($buttonRecoverPgroup) 

    $buttonCreatePgroupSnap = New-Object System.Windows.Forms.Button
    $buttonCreatePgroupSnap.add_click({createPgroupSnap})
    $buttonCreatePgroupSnap.Text = "Create Point-in-Time"
    $buttonCreatePgroupSnap.Top=27
    $buttonCreatePgroupSnap.Left=600
    $buttonCreatePgroupSnap.Width=120
    $buttonCreatePgroupSnap.Enabled = $false #Disabled by default
    $groupBoxPgrp.Controls.Add($buttonCreatePgroupSnap) 

    $buttonDeletePgroupSnap = New-Object System.Windows.Forms.Button
    $buttonDeletePgroupSnap.add_click({deletePgroupSnap})
    $buttonDeletePgroupSnap.Text = "Delete Point-in-Time"
    $buttonDeletePgroupSnap.Top=57
    $buttonDeletePgroupSnap.Left=600
    $buttonDeletePgroupSnap.Width=120
    $buttonDeletePgroupSnap.Enabled = $false #Disabled by default
    $groupBoxPgrp.Controls.Add($buttonDeletePgroupSnap) 


    $buttonAddVMFStoPgroup = New-Object System.Windows.Forms.Button
    $buttonAddVMFStoPgroup.add_click({addToPgroup})
    $buttonAddVMFStoPgroup.Text = "<< Add to Protection Group"
    $buttonAddVMFStoPgroup.Top=255
    $buttonAddVMFStoPgroup.Left=20
    $buttonAddVMFStoPgroup.Width=150
    $buttonAddVMFStoPgroup.Enabled = $false #Disabled by default
    $groupBoxVMFSPgrp.Controls.Add($buttonAddVMFStoPgroup)

##################Connection TextBox Definition

    $serverTextBox = New-Object System.Windows.Forms.TextBox 
    $serverTextBox.Location = New-Object System.Drawing.Size(10,40)
    $serverTextBox.Size = New-Object System.Drawing.Size(300,20)
    $serverTextBox.add_TextChanged({isVCTextChanged}) 
    $groupBoxVC.Controls.Add($serverTextBox) 

    $usernameTextBox = New-Object System.Windows.Forms.TextBox 
    $usernameTextBox.Location = New-Object System.Drawing.Size(10,90)
    $usernameTextBox.Size = New-Object System.Drawing.Size(300,20) 
    $usernameTextBox.add_TextChanged({isVCTextChanged}) 
    $groupBoxVC.Controls.Add($usernameTextBox) 

    $passwordTextBox = New-Object System.Windows.Forms.MaskedTextBox
    $passwordTextBox.PasswordChar = '*'
    $passwordTextBox.Location = New-Object System.Drawing.Size(10,140)
    $passwordTextBox.Size = New-Object System.Drawing.Size(300,20)
    $passwordTextBox.add_TextChanged({isVCTextChanged}) 
    $groupBoxVC.Controls.Add($passwordTextBox) 

    $outputTextBox = New-Object System.Windows.Forms.TextBox 
    $outputTextBox.Location = New-Object System.Drawing.Size(10,20)
    $outputTextBox.Size = New-Object System.Drawing.Size(940,115)
    $outputTextBox.MultiLine = $True 
    $outputTextBox.ReadOnly = $True
    $outputTextBox.ScrollBars = "Vertical"
    $outputTextBox.text = " "  
    $groupBoxLog.Controls.Add($outputTextBox) 

    $flasharrayTextBox = New-Object System.Windows.Forms.TextBox 
    $flasharrayTextBox.Location = New-Object System.Drawing.Size(10,70)
    $flasharrayTextBox.Size = New-Object System.Drawing.Size(300,20) 
    $flasharrayTextBox.add_TextChanged({isFATextChanged}) 
    $groupBoxFA.Controls.Add($flasharrayTextBox) 

    $flasharrayUsernameTextBox = New-Object System.Windows.Forms.TextBox 
    $flasharrayUsernameTextBox.Location = New-Object System.Drawing.Size(10,120)
    $flasharrayUsernameTextBox.Size = New-Object System.Drawing.Size(300,20)
    $flasharrayUsernameTextBox.add_TextChanged({isFATextChanged}) 
    $groupBoxFA.Controls.Add($flasharrayUsernameTextBox) 

    $flasharrayPasswordTextBox = New-Object System.Windows.Forms.MaskedTextBox
    $flasharrayPasswordTextBox.PasswordChar = '*'
    $flasharrayPasswordTextBox.Location = New-Object System.Drawing.Size(10,170)
    $flasharrayPasswordTextBox.Size = New-Object System.Drawing.Size(300,20)
    $flasharrayPasswordTextBox.add_TextChanged({isFATextChanged})    
    $groupBoxFA.Controls.Add($flasharrayPasswordTextBox) 

    $nameFilterTextBox = New-Object System.Windows.Forms.MaskedTextBox
    $nameFilterTextBox.Location = New-Object System.Drawing.Size(100,87)
    $nameFilterTextBox.Size = New-Object System.Drawing.Size(460,20)
    $nameFilterTextBox.Enabled = $false
    $groupBoxRadio.Controls.Add($nameFilterTextBox) 

##################VMFS TextBox Definition

    $newSnapshotTextBox = New-Object System.Windows.Forms.TextBox 
    $newSnapshotTextBox.Location = New-Object System.Drawing.Size(10,46)
    $newSnapshotTextBox.Size = New-Object System.Drawing.Size(280,20) 
    $newSnapshotTextBox.add_TextChanged({isSnapshotTextChanged}) 
    $newSnapshotTextBox.Enabled = $false
    $groupBoxCreateVMFSSnapshot.Controls.Add($newSnapshotTextBox) 

    $newVMFSTextBox = New-Object System.Windows.Forms.TextBox 
    $newVMFSTextBox.Location = New-Object System.Drawing.Size(95,20)
    $newVMFSTextBox.Size = New-Object System.Drawing.Size(305,20) 
    $newVMFSTextBox.add_TextChanged({isVMFSTextChanged}) 
    $newVMFSTextBox.Enabled = $false
    $groupBoxVMFS.Controls.Add($newVMFSTextBox) 

    $newVMFSSizeTextBox = New-Object System.Windows.Forms.TextBox 
    $newVMFSSizeTextBox.Location = New-Object System.Drawing.Size(490,20)
    $newVMFSSizeTextBox.Size = New-Object System.Drawing.Size(208,20) 
    $newVMFSSizeTextBox.add_TextChanged({sizeChanged}) 
    $newVMFSSizeTextBox.Enabled = $false
    $groupBoxVMFS.Controls.Add($newVMFSSizeTextBox) 

    ##################VM TextBox Definition

    $newVMSnapshotTextBox = New-Object System.Windows.Forms.TextBox 
    $newVMSnapshotTextBox.Location = New-Object System.Drawing.Size(130,70)
    $newVMSnapshotTextBox.Size = New-Object System.Drawing.Size(290,20) 
    $newVMSnapshotTextBox.add_TextChanged({isSnapshotTextChanged}) 
    $newVMSnapshotTextBox.Enabled = $false
    $groupBoxVMSnapshot.Controls.Add($newVMSnapshotTextBox) 

        
##################CheckBox Definition

    $migrateVMCheckBox = new-object System.Windows.Forms.checkbox
    $migrateVMCheckBox.Location = new-object System.Drawing.Size(15,19)
    $migrateVMCheckBox.Size = new-object System.Drawing.Size(230,20)
    $migrateVMCheckBox.Text = "Storage vMotion back to original VMFS"
    $migrateVMCheckBox.Checked = $false
    $migrateVMCheckBox.Enabled = $false
    $groupBoxRestoreVM.Controls.Add($migrateVMCheckBox) 

    $CheckBoxDeleteVMObject = new-object System.Windows.Forms.checkbox
    $CheckBoxDeleteVMObject.Location = new-object System.Drawing.Size(8,20)
    $CheckBoxDeleteVMObject.Size = new-object System.Drawing.Size(185,32)
    $CheckBoxDeleteVMObject.Text = "I confirm that I want to delete this virtual machine"
    $CheckBoxDeleteVMObject.add_CheckedChanged({vmDeleteCheckedChanged})
    $CheckBoxDeleteVMObject.Checked = $false
    $CheckBoxDeleteVMObject.Enabled = $false
    $groupBoxDeleteVMObject.Controls.Add($CheckBoxDeleteVMObject) 

    $CheckBoxDeleteVMObjectSnapshot = new-object System.Windows.Forms.checkbox
    $CheckBoxDeleteVMObjectSnapshot.Location = new-object System.Drawing.Size(8,20)
    $CheckBoxDeleteVMObjectSnapshot.Size = new-object System.Drawing.Size(185,32)
    $CheckBoxDeleteVMObjectSnapshot.Text = "I confirm that I want to delete this snapshot"
    $CheckBoxDeleteVMObjectSnapshot.add_CheckedChanged({vmDeleteSnapshotCheckedChanged})
    $CheckBoxDeleteVMObjectSnapshot.Checked = $false
    $CheckBoxDeleteVMObjectSnapshot.Enabled = $false
    $groupBoxDeleteVMSnapshot.Controls.Add($CheckBoxDeleteVMObjectSnapshot)
     
##################Pgroup CheckBox Definition

    $registerVMs = new-object System.Windows.Forms.checkbox
    $registerVMs.Location = new-object System.Drawing.Size(220,218)
    $registerVMs.Size = new-object System.Drawing.Size(150,20)
    $registerVMs.Text = "Register all VMs"
    $registerVMs.Checked = $false
    $registerVMs.Enabled = $false
    $registerVMs.add_CheckedChanged({registerVMchanged})
    $groupBoxPgrp.Controls.Add($registerVMs) 

    $powerOnVMs = new-object System.Windows.Forms.checkbox
    $powerOnVMs.Location = new-object System.Drawing.Size(380,218)
    $powerOnVMs.Size = new-object System.Drawing.Size(150,20)
    $powerOnVMs.Text = "Power-on all VMs"
    $powerOnVMs.Checked = $false
    $powerOnVMs.Enabled = $false
    $groupBoxPgrp.Controls.Add($powerOnVMs) 

##################Connection DropDownBox Definition

    $FlashArrayDropDownBox = New-Object System.Windows.Forms.ComboBox
    $FlashArrayDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $FlashArrayDropDownBox.Location = New-Object System.Drawing.Size(10,20) 
    $FlashArrayDropDownBox.Size = New-Object System.Drawing.Size(300,20) 
    $FlashArrayDropDownBox.DropDownHeight = 200
    $FlashArrayDropDownBox.Enabled=$false
    $groupBoxFA.Controls.Add($FlashArrayDropDownBox)
    $FlashArrayDropDownBox.Items.Add("Add new FlashArray...")|out-null
    $FlashArrayDropDownBox.SelectedIndex = 0
    $FlashArrayDropDownBox.add_SelectedIndexChanged({FlashArrayChanged})

    $ClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $ClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $ClusterDropDownBox.Location = New-Object System.Drawing.Size(100,50) 
    $ClusterDropDownBox.Size = New-Object System.Drawing.Size(460,20) 
    $ClusterDropDownBox.DropDownHeight = 200
    $ClusterDropDownBox.Enabled=$false 
    $ClusterDropDownBox.add_SelectedIndexChanged({clusterSelectionChanged})
    $groupBoxRadio.Controls.Add($ClusterDropDownBox)

##################VMFS DropDownBox Definition

    $DatastoreDropDownBox = New-Object System.Windows.Forms.ComboBox
    $DatastoreDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $DatastoreDropDownBox.Location = New-Object System.Drawing.Size(90,21) 
    $DatastoreDropDownBox.Size = New-Object System.Drawing.Size(235,20) 
    $DatastoreDropDownBox.DropDownHeight = 200
    $DatastoreDropDownBox.Enabled=$false 
    $DatastoreDropDownBox.add_SelectedIndexChanged({datastoreSelectionChanged})
    $groupBoxManageVMFS.Controls.Add($DatastoreDropDownBox)

    $UnitDropDownBox = New-Object System.Windows.Forms.ComboBox
    $UnitDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $UnitDropDownBox.Location = New-Object System.Drawing.Size(705,20) 
    $UnitDropDownBox.Size = New-Object System.Drawing.Size(40,20) 
    $UnitDropDownBox.DropDownHeight = 200
    $UnitDropDownBox.Enabled=$false 
    $groupBoxVMFS.Controls.Add($UnitDropDownBox)
    $UnitDropDownBox.Items.Add("MB") |Out-Null
    $UnitDropDownBox.Items.Add("GB") |Out-Null
    $UnitDropDownBox.Items.Add("TB") |Out-Null
    $UnitDropDownBox.SelectedIndex = 3 |Out-Null

    $CreateVMFSClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $CreateVMFSClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $CreateVMFSClusterDropDownBox.Location = New-Object System.Drawing.Size(490,60) 
    $CreateVMFSClusterDropDownBox.Size = New-Object System.Drawing.Size(295,20) 
    $CreateVMFSClusterDropDownBox.DropDownHeight = 200
    $CreateVMFSClusterDropDownBox.Enabled=$false 
    $CreateVMFSClusterDropDownBox.add_SelectedIndexChanged({enableCreateVMFS})
    $groupBoxVMFS.Controls.Add($CreateVMFSClusterDropDownBox)

    $ChooseFlashArrayDropDownBox = New-Object System.Windows.Forms.ComboBox
    $ChooseFlashArrayDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $ChooseFlashArrayDropDownBox.Location = New-Object System.Drawing.Size(95,60) 
    $ChooseFlashArrayDropDownBox.Size = New-Object System.Drawing.Size(305,20) 
    $ChooseFlashArrayDropDownBox.DropDownHeight = 200
    $ChooseFlashArrayDropDownBox.Enabled=$false 
    $ChooseFlashArrayDropDownBox.add_SelectedIndexChanged({enableCreateVMFS})
    $groupBoxVMFS.Controls.Add($ChooseFlashArrayDropDownBox)

    $RecoveryClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $RecoveryClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $RecoveryClusterDropDownBox.Location = New-Object System.Drawing.Size(95,37) 
    $RecoveryClusterDropDownBox.Size = New-Object System.Drawing.Size(265,20) 
    $RecoveryClusterDropDownBox.DropDownHeight = 200
    $RecoveryClusterDropDownBox.Enabled=$false 
    $RecoveryClusterDropDownBox.add_SelectedIndexChanged({enableRecovery})
    $groupBoxVMFSClone.Controls.Add($RecoveryClusterDropDownBox)
    
    $SnapshotDropDownBox = New-Object System.Windows.Forms.ComboBox
    $SnapshotDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $SnapshotDropDownBox.add_SelectedIndexChanged({snapshotChanged})
    $SnapshotDropDownBox.Location = New-Object System.Drawing.Size(490,21) 
    $SnapshotDropDownBox.Size = New-Object System.Drawing.Size(370,20) 
    $SnapshotDropDownBox.DropDownHeight = 200
    $SnapshotDropDownBox.Enabled=$false
    $groupBoxManageVMFS.Controls.Add($SnapshotDropDownBox)

    ##################VM DropDownBox Definition

    $VMDropDownBox = New-Object System.Windows.Forms.ComboBox
    $VMDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $VMDropDownBox.Location = New-Object System.Drawing.Size(70,55) 
    $VMDropDownBox.Size = New-Object System.Drawing.Size(400,20) 
    $VMDropDownBox.DropDownHeight = 200
    $VMDropDownBox.Enabled=$false
    $VMDropDownBox.add_SelectedIndexChanged({vmSelectionChanged}) 
    $groupBoxVM.Controls.Add($VMDropDownBox)

    $VMSnapshotDropDownBox = New-Object System.Windows.Forms.ComboBox
    $VMSnapshotDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $VMSnapshotDropDownBox.add_SelectedIndexChanged({vmSnapshotChanged})
    $VMSnapshotDropDownBox.Location = New-Object System.Drawing.Size(70,25) 
    $VMSnapshotDropDownBox.Size = New-Object System.Drawing.Size(400,20) 
    $VMSnapshotDropDownBox.DropDownHeight = 200
    $VMSnapshotDropDownBox.Enabled=$false
    $groupBoxVMSnapshot.Controls.Add($VMSnapshotDropDownBox)

    $VMDKDropDownBox = New-Object System.Windows.Forms.ComboBox
    $VMDKDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $VMDKDropDownBox.Location = New-Object System.Drawing.Size(15,20) 
    $VMDKDropDownBox.Size = New-Object System.Drawing.Size(460,20) 
    $VMDKDropDownBox.DropDownHeight = 200
    $VMDKDropDownBox.Enabled=$false 
    $VMDKDropDownBox.add_SelectedIndexChanged({vmDiskSelectionChanged})
    $groupBoxVMDK.Controls.Add($VMDKDropDownBox)

    $RDMDropDownBox = New-Object System.Windows.Forms.ComboBox
    $RDMDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $RDMDropDownBox.Location = New-Object System.Drawing.Size(15,20) 
    $RDMDropDownBox.Size = New-Object System.Drawing.Size(460,20) 
    $RDMDropDownBox.DropDownHeight = 200
    $RDMDropDownBox.Enabled=$false 
    $RDMDropDownBox.add_SelectedIndexChanged({vmDiskSelectionChanged})
    $groupBoxRDM.Controls.Add($RDMDropDownBox)


########################VM Recovery Drop Downs

    $TargetVMDropDownBox = New-Object System.Windows.Forms.ComboBox
    $TargetVMDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $TargetVMDropDownBox.Size = New-Object System.Drawing.Size(280,20) 
    $TargetVMDropDownBox.DropDownHeight = 200
    $TargetVMDropDownBox.Enabled=$false
    $TargetVMDropDownBox.add_SelectedIndexChanged({targetVMSelectionChanged})

    $TargetDatastoreDropDownBox = New-Object System.Windows.Forms.ComboBox
    $TargetDatastoreDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox 
    $TargetDatastoreDropDownBox.Size = New-Object System.Drawing.Size(280,20) 
    $TargetDatastoreDropDownBox.DropDownHeight = 200
    $TargetDatastoreDropDownBox.Enabled=$false
    $TargetDatastoreDropDownBox.add_SelectedIndexChanged({targetDatastoreSelectionChanged})

    $TargetClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $TargetClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $TargetClusterDropDownBox.Size = New-Object System.Drawing.Size(280,20) 
    $TargetClusterDropDownBox.DropDownHeight = 200
    $TargetClusterDropDownBox.Enabled=$false
    $TargetClusterDropDownBox.add_SelectedIndexChanged({targetClusterSelectionChanged})

    ######################## Host Drop Downs

    $HostClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $HostClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $HostClusterDropDownBox.Location = New-Object System.Drawing.Size(120,35) 
    $HostClusterDropDownBox.Size = New-Object System.Drawing.Size(550,20) 
    $HostClusterDropDownBox.DropDownHeight = 200
    $HostClusterDropDownBox.Enabled=$false
    $HostClusterDropDownBox.add_SelectedIndexChanged({clusterConfigSelectionChanged})
    $groupBoxChooseHost.Controls.Add($HostClusterDropDownBox)

    $HostFlashArrayDropDownBox = New-Object System.Windows.Forms.ComboBox
    $HostFlashArrayDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $HostFlashArrayDropDownBox.Location = New-Object System.Drawing.Size(120,72)
    $HostFlashArrayDropDownBox.Size = New-Object System.Drawing.Size(550,20) 
    $HostFlashArrayDropDownBox.DropDownHeight = 200
    $HostFlashArrayDropDownBox.Enabled=$false
    $HostFlashArrayDropDownBox.add_SelectedIndexChanged({clusterConfigSelectionChanged})
    $groupBoxChooseHost.Controls.Add($HostFlashArrayDropDownBox)

    $AddHostDropDownBox = New-Object System.Windows.Forms.ComboBox
    $AddHostDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $AddHostDropDownBox.Location = New-Object System.Drawing.Size(10,90)
    $AddHostDropDownBox.Size = New-Object System.Drawing.Size(180,20) 
    $AddHostDropDownBox.DropDownHeight = 200
    $AddHostDropDownBox.Enabled=$false
    $groupBoxAddHost.Controls.Add($AddHostDropDownBox)

    ######################## Pgroup Drop Downs

    $PgroupFADropDownBox = New-Object System.Windows.Forms.ComboBox
    $PgroupFADropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $PgroupFADropDownBox.Location = New-Object System.Drawing.Size(120,35) 
    $PgroupFADropDownBox.Size = New-Object System.Drawing.Size(550,20) 
    $PgroupFADropDownBox.DropDownHeight = 200
    $PgroupFADropDownBox.Enabled=$false
    $PgroupFADropDownBox.add_SelectedIndexChanged({pgroupFAChanged})
    $groupBoxFilterPgroup.Controls.Add($PgroupFADropDownBox)

    $PgroupPGDropDownBox = New-Object System.Windows.Forms.ComboBox
    $PgroupPGDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $PgroupPGDropDownBox.Location = New-Object System.Drawing.Size(140,28) 
    $PgroupPGDropDownBox.Size = New-Object System.Drawing.Size(450,20) 
    $PgroupPGDropDownBox.DropDownHeight = 200
    $PgroupPGDropDownBox.Enabled=$false
    $PgroupPGDropDownBox.add_SelectedIndexChanged({getProtectionGroupSnapshots})
    $groupBoxPgrp.Controls.Add($PgroupPGDropDownBox)

    $PgroupSnapDropDownBox = New-Object System.Windows.Forms.ComboBox
    $PgroupSnapDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $PgroupSnapDropDownBox.Location = New-Object System.Drawing.Size(140,58) 
    $PgroupSnapDropDownBox.Size = New-Object System.Drawing.Size(450,20) 
    $PgroupSnapDropDownBox.DropDownHeight = 200
    $PgroupSnapDropDownBox.Enabled=$false
    $PgroupSnapDropDownBox.add_SelectedIndexChanged({getPiTSnapshots})
    $groupBoxPgrp.Controls.Add($PgroupSnapDropDownBox)

    $PgroupClusterDropDownBox = New-Object System.Windows.Forms.ComboBox
    $PgroupClusterDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList #Disable user input in ComboBox
    $PgroupClusterDropDownBox.Location = New-Object System.Drawing.Size(140,178) 
    $PgroupClusterDropDownBox.Size = New-Object System.Drawing.Size(450,20) 
    $PgroupClusterDropDownBox.DropDownHeight = 200
    $PgroupClusterDropDownBox.Enabled=$false
    $PgroupClusterDropDownBox.add_SelectedIndexChanged({pgroupcheckboxes})
    $groupBoxPgrp.Controls.Add($PgroupClusterDropDownBox)
    
   ##################Pgroup CheckedList Box

    $SnapshotCheckedListBox = New-Object -TypeName System.Windows.Forms.CheckedListBox
    $SnapshotCheckedListBox.Location = New-Object System.Drawing.Size(140,88) 
    $SnapshotCheckedListBox.Size = New-Object System.Drawing.Size(450,80)
    $SnapshotCheckedListBox.Enabled=$false
    $SnapshotCheckedListBox.CheckOnClick = $true
    $SnapshotCheckedListBox.Add_Click({snapshotSelectAll})
    $groupBoxPgrp.Controls.Add($SnapshotCheckedListBox)

    $AddToPgroupCheckedListBox = New-Object -TypeName System.Windows.Forms.CheckedListBox
    $AddToPgroupCheckedListBox.Location = New-Object System.Drawing.Size(10,20) 
    $AddToPgroupCheckedListBox.Size = New-Object System.Drawing.Size(175,240)
    $AddToPgroupCheckedListBox.Enabled=$false
    $AddToPgroupCheckedListBox.CheckOnClick = $true
    $AddToPgroupCheckedListBox.Add_Click({enableAddtoPG})
    $groupBoxVMFSPgrp.Controls.Add($AddToPgroupCheckedListBox)


##################Show Form

    $main_form.Add_Shown({$main_form.Activate()})
    [void] $main_form.ShowDialog()




