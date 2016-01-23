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
Write-host "Pure Storage VMware Volume Refresh Script v1.0"
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
$purevolumes=@()
$EndPoint= @()
$FACreds = New-Object System.Management.Automation.PSCredential ($pureuser, $pureuserpwd)
$VCCreds = New-Object System.Management.Automation.PSCredential ($vcuser, $vcpass)
$facount = 0
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
connect-viserver -Server $vcenter -Credential $VCCreds|out-null
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
    if ($vms.count -ge 1)
    {
        write-host ("There are VMs registered to the recovery datastore. Unregister them first then re-run this script.")
    }
    else
    {
        $hosts = $recoverydatastore |get-vmhost
        $hosts | Get-VMHostStorage -RescanAllHba |out-null
        $recoverydatastore | Remove-Datastore -vmhost $hosts[0] -Confirm:$false
        Start-Sleep -s 5
        $hosts | Get-VMHostStorage -RescanAllHba |out-null
        Start-Sleep -s 10
        $esxcli = $hosts[0] | get-esxcli
        $snapshots = Get-PfaVolumeSnapshots -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
        New-PfaVolume -Array $EndPoint[$arraychoice] -VolumeName $recoverypurevol.name -Source $snapshots[0].name -overwrite |out-null
        $hosts | Get-VMHostStorage -RescanAllHba |out-null
        Start-Sleep -s 30
        $hosts | Get-VMHostStorage -RescanAllHba |out-null
        Start-Sleep -s 30
        $esxcli.storage.vmfs.snapshot.resignature($vmfsname) |out-null
        $hosts | Get-VMHostStorage -RescanAllHba |out-null
        $datastores = $hosts[0] | Get-Datastore
        foreach ($ds in $datastores)
        {
            $naa = $ds.ExtensionData.Info.Vmfs.Extent.DiskName
            if ($naa -eq $recoverylun)
            {
                $resigds = $ds
            }
        } 
        $resigds | Set-Datastore -Name $recoveryvmfsname |out-null
        Start-Sleep -s 20
        $hosts | Get-VMHostStorage -RescanAllHba |out-null
    }

}
#disconnecting sessions
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}