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
Write-host "Pure Storage VMware VMFS Force Mount Script v1.0"
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

This script will take in the source VMFS name and the target VMFS name and refresh the target with the latest snapshot of the source.
Enter in vCenter credentials and one or more FlashArrays. The FlashArrays must use the same credentials. If different credentials
are needed for each FlashArray the script must be altered slightly.

Supports:
-PowerShell 3.0 or later
-Pure Storage PowerShell SDK 1.0 or later
-PowerCLI 6.0 Release 1 or later (5.5/5.8 is likely fine, but not tested with this script version)
-REST API 1.4 and later
-Purity 4.1 and later
-FlashArray 400 Series and //m
#>

while ($varsCorrect -ne "Y")
{
    $srcarray = Read-Host "Enter the source FlashArray name (do not include DNS suffix)"
    $targetflasharray = Read-Host "Enter the target FlashArray IP or FQDN"
    $pureuser = Read-Host "Enter FlashArray user name"
    $pureuserpwd = Read-Host "Enter FlashArray password" -AsSecureString
    $vcenter = Read-Host "Enter vCenter FQDN or IP"
    $vcuser = Read-Host "Enter vCenter user name"
    $vcpass = Read-Host "Enter vCenter password" -AsSecureString
    $csvfile = Read-Host "Enter CSV file directory path"
    write-host ""
    $varsCorrect = read-host "Are the above values entered accurately? Y/N"
}

$FACreds = New-Object System.Management.Automation.PSCredential ($pureuser, $pureuserpwd)
$VCCreds = New-Object System.Management.Automation.PSCredential ($vcuser, $vcpass)
$volumes = import-csv $csvfile -UseCulture

#A function to rescan all of the input ESXi servers and rescan for VMFS volumes. This starts all host operations in parallel and waits for them all to complete. Is called throughout as needed
function rescanESXiHosts
{
    foreach ($esxi in $hosts) 
    {
         $argList = @($vcenter, $VCCreds, $esxi)
         $job = Start-Job -ScriptBlock{ 
             Connect-VIServer -Server $args[0] -Credential $args[1]
             Get-VMHost -Name $args[2] | Get-VMHostStorage -RescanAllHba -RescanVMFS
             Disconnect-VIServer -Confirm:$false
         } -ArgumentList $argList
    }
    Get-Job | Wait-Job |out-null
 }

 #A function to just refresh the VMFS storage information on a set of hosts
 function refreshESXiHoststorage
{
    foreach ($esxi in $hosts) 
    {
         $argList = @($vcenter, $VCCreds, $esxi)
         $job = Start-Job -ScriptBlock{ 
             Connect-VIServer -Server $args[0] -Credential $args[1]
             Get-VMHost -Name $args[2] | Get-VMHostStorage -RescanVMFS
             Disconnect-VIServer -Confirm:$false
         } -ArgumentList $argList
    }
    Get-Job | Wait-Job |out-null
 }

#A function to unmount and detach the VMFS from all of the input ESXi servers. This starts all host operations in parallel and waits for them all to complete. Is called throughout as needed
function unmountandDetachVMFS
{
    foreach ($esxi in $hosts)
    {
        $argList = @($vcenter, $VCCreds, $esxi, $tempdatastore)
        $job = Start-Job -ScriptBlock{
            Connect-VIServer -Server $args[0] -Credential $args[1]
            $esxihost = get-vmhost $args[2]
            $datastore = get-datastore $args[3]               
            $storageSystem = Get-View $esxihost.Extensiondata.ConfigManager.StorageSystem
	        $StorageSystem.UnmountVmfsVolume($datastore.ExtensionData.Info.vmfs.uuid) |out-null
            $storageSystem.DetachScsiLun((Get-ScsiLun -VmHost $esxihost | where {$_.CanonicalName -eq $datastore.ExtensionData.Info.Vmfs.Extent.DiskName}).ExtensionData.Uuid) |out-null
            Disconnect-VIServer -Confirm:$false
         } -ArgumentList $argList
    }
    Get-Job | Wait-Job |out-null
}

#disconnects all API connections
function disconnectsessions
{
    write-host "Disconnecting vCenter and FlashArrays" -foregroundcolor "red"
    disconnect-viserver -Server $vcenter -confirm:$false
    Disconnect-PfaArray -Array $targetEndPoint
}

#Connect to each FlashArray
write-host "Connecting to FlashArray" -foregroundcolor "green"
$targetEndPoint = New-PfaArray -EndPoint $targetflasharray -Credentials $FACreds -IgnoreCertificateError

#Connect to vCenter
Set-PowerCLIConfiguration -DisplayDeprecationWarnings:$false -confirm:$false| Out-Null
write-host "Connecting to vCenter" -foregroundcolor "green"
connect-viserver -Server $vcenter -Credential $VCCreds|out-null
write-host "*****************************************************************"
write-host ""

#kills all of the VM process on the affected datastores in the CSV file. Answers the data loss question if the VMs has been tagged with it
foreach ($volume in $volumes)
{
    $vms = get-datastore $volume.Source |get-vm 
    write-host "Killing VMs..." 
    foreach ($vm in $vms)
    {
        $vm |Get-VMQuestion |Set-VMQuestion –Option "button.abort" -confirm:$false |Out-Null
        $vm = Get-VM $vm.Name
        if ($vm.PowerState -eq "PoweredOn")
        {
            $vm |Stop-VM -Kill -Confirm:$false
        }
    }
}
#Gets all of the FlashArray snapshots on the target FlashArray
write-host ("Recovering the VMFS copies from the FlashArray named " + $targetEndPoint.EndPoint)
$snaps = Get-PfaallVolumeSnapshots -array $targetEndPoint
$newvols = @()
$finalvols = @()
$volcount = 0
<#The next statement does the following:
1)Finds the latest snapshot for the given volume
2) Finds the WWNs of the ESX hosts in that cluster
3)Find the matching hosts on the FlashArray and their host groups
4)Creates a new volume from that snapshot
5)Creates a second new volumes to move the VMs to eventually
6)Connects them both to the proper hosts or host groups
7)Will fail if a host group does not match the ESXi cluster (too many hosts, too little, incorrect WWNs)
#>
foreach ($volume in $volumes)
{
    write-host "----------------------------------------------------------"
    write-host "Starting recovery for the following volume pair:"
    write-host $volume 
    $fullpurevolname = $srcarray+":"+$volume.Source
    $snapshots = @()
    foreach ($snap in $snaps)
    {
        if ($snap.source -eq $fullpurevolname)
        {
            $snapshots += $snap
        }
    }
    $hosts = get-cluster $volume.Cluster |get-vmhost
    $hostwwns = @{} 
    foreach ($esx in $hosts)
    {
    
        $wwns = $esx | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
        {
             $wwns.substring($i,16)
        }} 
        $hostwwns.Add($esx.name, $wwns)
    }
    write-host
    $tgthostlist = Get-PfaHosts -Array $targetEndPoint 
    $hostlist = @()
    foreach ($h in $hostwwns.GetEnumerator()) 
    {
        write-host "Looking for host match on target FlashArray for ESXi host" $h.name"..."
        $foundhost = 0
        foreach ($fahost in $tgthostlist)
        {    
            if ((compare-object $h.value $fahost.wwn) -eq $null)
            {
                $hostlist += $fahost.name
                write-host "Found match for ESXi host name" $h.name "on the target FlashArray" $targetEndPoint.endpoint "named" $fahost.name 
                $foundhost = 1
            }
        }
        if ($foundhost -ne 1)
        {
            write-host "Could not find a matching host for ESXi host named" $h.name -foregroundcolor "red"
            disconnectsessions
            exit
        }
    }
    write-host
    write-host "Getting host groups for all of the discovered hosts"
    $hostgrouplist = @()
    $standalonehosts = @()
    foreach ($fahostname in $hostlist)
    {
        $fahost = Get-PfaHost -Array $targetEndPoint -Name $fahostname
        if ($fahost.hgroup -eq $null)
        {
            write-host "The host" $fahost.name "is not in a host group"
            $standalonehosts += $fahost.name
        }
        else
        {
            $hostgrouplist += $fahost.hgroup
        } 
    }
    try
    {
        $newvols += New-PfaVolume -Array $targetEndPoint -VolumeName $volume.Target -Source $snapshots[0].name -ErrorAction Stop
    }
    catch
    {
        write-host "The recovery volume failed to be created, script exiting" -foregroundcolor "red"
        write-host $_.Exception.Message
        disconnectsessions
        exit
    }
    write-host
    write-host "Created a new volume with the name" $volume.Target "from the snapshot for force mounting" $snapshots[0].name -foregroundcolor "green"
    try
    {
        $finalvols += New-PfaVolume -Array $targetEndPoint -VolumeName $volume.Source -Size $newvols[$volcount].size -ErrorAction Stop
    }
    catch
    {
        write-host "The final persistent volume failed to be created, script exiting" -foregroundcolor "red"
        write-host $_.Exception.Message
        Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volume.Target -Confirm:$false |out-null
        Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volume.Target -Confirm:$false -Eradicate |out-null
        disconnectsessions
        exit
    }
    write-host "Created a new volume with the name" $volume.Source "for persistent VM storage." -foregroundcolor "green"
    write-host
    if ($hostgrouplist -ge 1)
    {
        $hostcount = 0
        $hostgrouplist = $hostgrouplist |select-object -unique
        foreach ($hgroup in $hostgrouplist)
        {
            $hgroupinfo = Get-PfaHostGroup -Array $targetEndPoint -Name $hgroup
            $hostcount = $hostcount + $hgroupinfo.hosts.count
        }
        if (($hostcount + $standalonehosts.count) -ne $hosts.count)
        {
            write-host "There are a different number of hosts in the host groups ("$hostcount ") than the number of identified ESXi hosts (" ($hosts.count - $standalonehosts.count) ")" -foregroundcolor "red"
            Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volume.Target -Confirm:$false |out-null
            Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volume.Target -Confirm:$false -Eradicate |out-null
            Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volume.Source -Confirm:$false |out-null
            Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volume.Source -Confirm:$false -Eradicate |out-null
            disconnectsessions
            exit
        }
        write-host
        write-host $hostgrouplist.count "host group(s) has been identified. Adding the volume to the following host group(s)"
        write-host $hostgrouplist
        foreach ($hgroup in $hostgrouplist)
        {
             New-PfaHostGroupVolumeConnection -Array $targetEndPoint -VolumeName $volume.Target -HostGroupName $hgroup |out-null
             New-PfaHostGroupVolumeConnection -Array $targetEndPoint -VolumeName $volume.Source  -HostGroupName $hgroup |out-null
        }
        write-host "The new volume" $newvols[$volcount].name "has been added to the following host groups"
        write-host $hostgrouplist
    }
    if ($standalonehosts -gt 0)
    {
        write-host $standalonehosts.count "standalone hosts have been identified. Adding the volume to the following hosts"
        write-host $standalonehosts
        foreach ($standalonehost in $standalonehosts)
        {
            New-PfaHostVolumeConnection -Array $targetEndPoint -VolumeName $volume.Target -HostName $standalonehost |out-null
            New-PfaHostVolumeConnection -Array $targetEndPoint -VolumeName $volume.Source -HostName $standalonehost |out-null
        }
    }
    $volcount++
}
write-host "----------------------------------------------------------"
#Sets all of the hosts to allow snapshots to be force mounted automatically upon a rescan
$hosts = get-cluster $volumes.Cluster|get-vmhost
foreach ($esx in $hosts)
{
    $disallowsnapshot = $esx | Get-AdvancedSetting -Name LVM.DisallowSnapshotLUN
    if ($disallowsnapshot.value -eq 1)
    {
        $snapboolean = "enabled"
    }
    else
    {
        $snapboolean = "disabled"
    }
    write-host
    write-host "LVM.DisallowSnapshotLun is currently set to" $snapboolean "on ESXi host" $esx.Name
    if ($disallowsnapshot.value -ne 0)
    {
        write-host "Disabling LVM.DisallowSnapshotLun..."
        $disallowsnapshot |Set-AdvancedSetting -Value 0 -Confirm:$false |out-null
        write-host "LVM.DisallowSnapshotLun is now disabled."
    }
    else
    {
        write-host "Setting is correct. No need to change."
    }
}
write-host "----------------------------------------------------------"
write-host
write-host "Rescanning host HBAs..."
rescanESXiHosts
start-sleep -s 10
#Powers on all of the VMs
write-host "Powering on the VMs..."
foreach($volume in $volumes)
{
    get-datastore $volume.source |get-vm |Start-VM -RunAsync |Out-Null
}
$hosts = get-cluster $volumes.Cluster|get-vmhost
start-sleep -s 10
$skippeddatastores = @()
#Formats the second volume for each pair as VMFS and renames the original one. Moves all of the VMs to the respective new volume
#Old volumes will be unmounted, detached and destroyed on the FlashArray
for($vmfscount=0;$vmfscount -lt $newvols.count; $vmfscount++)
{

    write-host "----------------------------------------------------------"
    $hosts = get-datastore $finalvols[$vmfscount].name | get-vmhost
    $datastore = Get-Datastore -Name $finalvols[$vmfscount].name
    write-host "Renaming datastore" $finalvols[$vmfscount].name "to" $datastore.Name
    $tempdatastore = $datastore | Set-Datastore -Name $newvols[$vmfscount].name
    $newvolserial = ("naa.624a9370" + $finalvols[$vmfscount].serial)
    write-host "Formatting new target datastore with VMFS..."
    $targetdatastore = $hosts[0] |New-Datastore -Name $finalvols[$vmfscount].name -Path $newvolserial.ToLower() -Vmfs
    $vms = $tempdatastore |get-vm
    refreshESXiHoststorage
    write-host "Initiating Storage vMotion evacuation of datastore" $tempdatastore.Name "to final datastore."
    foreach ($vm in $vms)
    {
        $vm | Move-VM -Datastore $targetdatastore -RunAsync |Out-Null
        
    }
    $svmotioncount=0
    while ((Get-Datastore -Name $newvols[$vmfscount].name |get-vm) -ne $null)
    {
        if ($svmotioncount -eq 0)
        {
            write-host "Waiting for Storage vMotion evacuation of VMFS" $tempdatastore.Name "to target VMFS" $targetdatastore.Name "to complete..."
            $svmotioncount=1
        }
    }
    write-host "Virtual machine evacuation complete for VMFS" $tempdatastore.Name -foregroundcolor "green"
    Start-Sleep -s 10
    $vms = Get-Datastore -Name $newvols[$vmfscount].name
    if ($vms -ne $null)
    {
        write-host "Unmounting, detaching, disconnecting and deleting original force-mounted volume..."
        $hosts = $datastore | Get-VMHost
        unmountandDetachVMFS
        $fahosts = Get-PfaVolumeHostConnections -Array $targetEndPoint -VolumeName $volumes[$vmfscount].Target
        $fahosts = $fahosts.host
        $fahostgroups = Get-PfaVolumeHostGroupConnections -Array $targetEndPoint -VolumeName $volumes[$vmfscount].Target
        $fahostgroups = $fahostgroups.hgroup |get-unique
        if ($fahosts.count -ge 1)
        {
            write-host "The volume" $volumes[$vmfscount].Target " is presented privately to the following hosts:"
            write-host $fahosts
            write-host "Removing the volume from the host(s)..." -foregroundcolor "red"
            foreach($fahost in $fahosts)
            {
                Remove-PfaHostVolumeConnection -Array $targetEndPoint -VolumeName $volumes[$vmfscount].Target -HostName $fahost |out-null
            } 
        }
        if ($fahostgroups.count -ge 1)
        {
            write-host "The volume" $volumes[$vmfscount].Target " is presented to the following host groups:"
            write-host $fahostgroups
            write-host "Removing the volume from the host groups(s)..." -foregroundcolor "red"            
            foreach($fahostgroup in $fahostgroups)
            {
                Remove-PfaHostGroupVolumeConnection -Array $targetEndPoint -VolumeName $volumes[$vmfscount].Target -HostGroupName $fahostgroup |out-null
            } 
        }
        write-host "Destroying the volume named" $volumes[$vmfscount].Target -foregroundcolor "red"
        Remove-PfaVolumeOrSnapshot -Array $targetEndPoint -Name $volumes[$vmfscount].Target -Confirm:$false |out-null
        write-host "The volume can be recovered from the FlashArray Destroyed Volumes folder for 24 hours."
    }
    else
    {
        write-host "The datastore" $tempdatastore.Name "has VMs on it still, skipping removal. Please manually migrate remaining VMs and then remove the volume" -foregroundcolor "red"
        $skippeddatastores += $tempdatastore
    }
    write-host "----------------------------------------------------------"
}
$hosts = get-cluster $volumes.Cluster|get-vmhost
rescanESXiHosts
#Turning off the force mount behavior
foreach ($esx in $hosts)
{
    $disallowsnapshot = $esx | Get-AdvancedSetting -Name LVM.DisallowSnapshotLUN
    if ($disallowsnapshot.value -eq 1)
    {
        $snapboolean = "enabled"
    }
    else
    {
        $snapboolean = "disabled"
    }
    write-host
    write-host "LVM.DisallowSnapshotLun is currently set to" $snapboolean "on ESXi host" $esx.Name
    if ($disallowsnapshot.value -ne 1)
    {
        write-host "Enabling LVM.DisallowSnapshotLun..."
        $disallowsnapshot |Set-AdvancedSetting -Value 1 -Confirm:$false |out-null
        write-host "LVM.DisallowSnapshotLun is now enabled."
    }
    else
    {
        write-host "Setting is correct. No need to change."
    }
}
#If any datastores could not be evacuated or another VM was moved to it, the volume was then not deleted. It will be listed here
if ($skippeddatastores -ne $null)
{
    write-host "The following datastores were skipped because they still have VMs that failed to migrate. Please manually migrate the VMs and delete the datastore:" 
    write-host $skippeddatastores -foregroundcolor "red"
}
write-host "----------------------------------------------------------"
write-host
#disconnecting sessions
disconnectsessions