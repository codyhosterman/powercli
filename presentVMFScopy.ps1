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
Write-host "Pure Storage VMware Volume Refresh Script v1.1"
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
    $flasharrays = @()
    $arraycount = Read-Host "How many FlashArrays do you want to search? [Enter a whole number 1 or higher]"
    Write-Host "Please enter each FlashArray FQDN or IP one at a time and press enter after each entry"
    for ($faentry=1; $faentry -le $arraycount; $faentry++)
    {
        $flasharrays += Read-Host "Enter FlashArray FQDN or IP"
    }
    $pureuser = Read-Host "Enter FlashArray user name"
    $pureuserpwd = Read-Host "Enter FlashArray password" -AsSecureString
    $vcenter = Read-Host "Enter vCenter FQDN or IP"
    $vcuser = Read-Host "Enter vCenter user name"
    $vcpass = Read-Host "Enter vCenter password" -AsSecureString
    $vmfsname = Read-Host "Enter Source VMFS Name"
    $recoveryvmfsname = Read-Host "Enter Recovery VMFS Name"
    write-host ""
    $varsCorrect = read-host "Are the above values entered accurately? Y/N"
}

$FACreds = New-Object System.Management.Automation.PSCredential ($pureuser, $pureuserpwd)
$VCCreds = New-Object System.Management.Automation.PSCredential ($vcuser, $vcpass)

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

#A function to unmount and detach the VMFS from all of the input ESXi servers. This starts all host operations in parallel and waits for them all to complete. Is called throughout as needed
function unmountandDetachVMFS
{
    foreach ($esxi in $hosts)
    {
        $argList = @($vcenter, $VCCreds, $esxi, $recoverydatastore)
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
#Connect to each FlashArray and get all of their volume information
$facount = 0
$purevolumes=@()
$EndPoint= @()
foreach ($flasharray in $flasharrays)
{
    if ($facount -eq 0)
    {
        $EndPoint = @(New-PfaArray -EndPoint $flasharray -Credentials $FACreds -IgnoreCertificateError)
        $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
        $tempvols = @(Get-PfaVolumes -Array $EndPoint[$facount])  
        $arraysnlist = @($tempvols.serial[0].substring(0,16))
    }
    else
    {
        $EndPoint += New-PfaArray -EndPoint $flasharray -Credentials $FACreds -IgnoreCertificateError
        $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
        $tempvols = Get-PfaVolumes -Array $EndPoint[$facount]   
        $arraysnlist += $tempvols.serial[0].substring(0,16)
    }
    $facount = $facount + 1
}
#Connect to vCenter
Set-PowerCLIConfiguration -DisplayDeprecationWarnings:$false -confirm:$false| Out-Null
connect-viserver -Server $vcenter -Credential $VCCreds|out-null
write-host "*****************************************************************"
write-host ""

#Find which FlashArray the source VMFS volume is on
$datastore = get-datastore $vmfsname
$lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName 
if ($lun -like 'naa.624a9370*')
{
    $volserial = ($lun.ToUpper()).substring(12)
    $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
    for($i=0; $i -lt $arraysnlist.count; $i++)
    {
        if ($arraysnlist[$i] -eq ($volserial.substring(0,16)))
        {
            $arraychoice = $i
        }
    }
    write-host ("The VMFS named " + $vmfsname + " is on a FlashArray named " + $EndPoint[$arraychoice].EndPoint)
    write-host ("The FlashArray volume is named " + $purevol.name)
    $volumeexists = 1
}
else
{
    write-host 'This datastore is NOT a Pure Storage Volume.'
}

#Find which FlashArray the target VMFS volume is on
$recoverydatastore = get-datastore $recoveryvmfsname
$recoverylun = $recoverydatastore.ExtensionData.Info.Vmfs.Extent.DiskName 
if ($recoverylun -like 'naa.624a9370*')
{
    $recoveryvolserial = ($recoverylun.ToUpper()).substring(12)
    $recoverypurevol = $purevolumes | where-object { $_.serial -eq $recoveryvolserial }
    for($i=0; $i -lt $arraysnlist.count; $i++)
    {
        if ($arraysnlist[$i] -eq ($recoveryvolserial.substring(0,16)))
        {
            $recoveryarraychoice = $i
        }
    }
    write-host ("The VMFS named " + $recoveryvmfsname + " is on a FlashArray named " + $EndPoint[$recoveryarraychoice].EndPoint)
    write-host ("The FlashArray volume is named " + $recoverypurevol.name)
    $recoveryvolumeexists = 1
}
else
{
    write-host 'This datastore is NOT a Pure Storage Volume.'
}

if (($volumeexists -eq 1) -and ($recoveryvolumeexists -eq 1))
{
    $vms = $recoverydatastore |get-vm
    #Make sure there are no VMs on the recovery VMFS
    if ($vms.count -ge 1)
    {
        write-host ("There are VMs registered to the recovery datastore. Unregister them first then re-run this script.")
    }
    else
    {
        $hosts = $recoverydatastore |get-vmhost
        write-host "Unmounting and detaching the VMFS volume from the following ESXi hosts:"
        write-host $hosts
        unmountandDetachVMFS
        <# Does the following:
        1) Get the latest FlashArray snapshot from the source VMFS.
        2) Gets any host groups and host the recovery volume is connected to
        3) Removes the recovery volume from the hosts and/or host groups
        4) Deletes the volume
        5) Creates a new volume with the same name from the latest snapshot of the source 
        6) Adds the volume back to all of its hosts and host groups
        #>
        rescanESXiHosts |out-null
        $esxcli = $hosts[0] | get-esxcli
        $snapshots = Get-PfaVolumeSnapshots -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
        $fahosts = Get-PfaVolumeHostConnections -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name
        $fahosts = $fahosts.host
        $fahostgroups = Get-PfaVolumeHostGroupConnections -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name
        $fahostgroups = $fahostgroups.hgroup |get-unique
        if ($fahosts.count -ge 1)
        {
            write-host "The volume is presented privately to the following hosts:"
            write-host $fahosts
            write-host "Removing the volume from the host(s)..." -foregroundcolor "red"
            foreach($fahost in $fahosts)
            {
                Remove-PfaHostVolumeConnection -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name -HostName $fahost |out-null
            } 
        }
        if ($fahostgroups.count -ge 1)
        {
            write-host "The volume is presented to the following host groups:"
            write-host $fahostgroups
            write-host "Removing the volume from the host groups(s)..." -foregroundcolor "red"            
            foreach($fahostgroup in $fahostgroups)
            {
                Remove-PfaHostGroupVolumeConnection -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name -HostGroupName $fahostgroup |out-null
            } 
        }
        write-host "Deleting and permanently eradicating the volume named" $recoverypurevol.name -foregroundcolor "red"
        Remove-PfaVolumeOrSnapshot -Array $EndPoint[$arraychoice] -Name $recoverypurevol.name -Confirm:$false |out-null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint[$arraychoice] -Name $recoverypurevol.name -Confirm:$false -Eradicate |out-null
        $newvol = New-PfaVolume -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name -Source $snapshots[0].name
        write-host "Created a new volume with the name" $recoverypurevol.name "from the snapshot" $snapshots[0].name -foregroundcolor "green"
        if ($fahosts.count -ge 1)
        {
            write-host "Adding the new volume back privately to the following host(s)" -foregroundcolor "green"
            write-host $fahosts
            foreach($fahost in $fahosts)
            {
                New-PfaHostVolumeConnection -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name -HostName $fahost |out-null
            } 
        }
        if ($fahostgroups.count -ge 1)
        {
            write-host "Adding the new volume back to the following host group(s)" -foregroundcolor "green"
            write-host $fahostgroups
            foreach($fahostgroup in $fahostgroups)
            {
                New-PfaHostGroupVolumeConnection -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name -HostGroupName $fahostgroup |out-null
            } 
        }
        Start-Sleep -s 30
        rescanESXiHosts
        #resignatures the datastore after a rescan
        Start-sleep -s 10
        $unresolvedvmfs = $esxcli.storage.vmfs.snapshot.list($vmfsname)
        $recoverylun = ("naa.624a9370" + $newvol.serial)
        if ($unresolvedvmfs.UnresolvedExtentCount -ge 2)
        {
            write-host "ERROR: There are more than one unresolved copies of the source VMFS named" $vmfsname -foregroundcolor "red"
            write-host "Please remove the additional copies in order to mount"
        }
        else
        {
            write-host "Resignaturing the VMFS on the device" $recoverylun "and then mounting it..."
            $esxcli.storage.vmfs.snapshot.resignature($vmfsname) |out-null
            rescanESXiHosts
            $datastores = $hosts[0] | Get-Datastore
            #renames the VMFS back to the original recovery name
            foreach ($ds in $datastores)
            {
                $naa = $ds.ExtensionData.Info.Vmfs.Extent.DiskName
                if ($naa -eq $recoverylun.ToLower())
                {
                    $resigds = $ds
                }
            } 
            $resigds | Set-Datastore -Name $recoveryvmfsname |out-null
            write-host "Renaming the datastore" $resigds.name "back to" $recoveryvmfsname
        }

    }
}
#disconnecting sessions
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}