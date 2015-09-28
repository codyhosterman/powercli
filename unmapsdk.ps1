Write-Host '             __________________________'
Write-Host '            /++++++++++++++++++++++++++\'           
Write-Host '           /++++++++++++++++++++++++++++\'           
Write-Host '          /++++++++++++++++++++++++++++++\'         
Write-Host '         /++++++++++++++++++++++++++++++++\'        
Write-Host '        /++++++++++++++++++++++++++++++++++\'       
Write-Host '       /++++++++++++/----------\++++++++++++\'     
Write-Host '      /++++++++++++/            \++++++++++++\'    
Write-Host '     /++++++++++++/              \++++++++++++\'   
Write-Host '    /++++++++++++/                \++++++++++++\'  
Write-Host '   /++++++++++++/                  \++++++++++++\' 
Write-Host '   \++++++++++++\                  /++++++++++++/' 
Write-Host '    \++++++++++++\                /++++++++++++/' 
Write-Host '     \++++++++++++\              /++++++++++++/'  
Write-Host '      \++++++++++++\            /++++++++++++/'    
Write-Host '       \++++++++++++\          /++++++++++++/'     
Write-Host '        \++++++++++++\'                   
Write-Host '         \++++++++++++\'                           
Write-Host '          \++++++++++++\'                          
Write-Host '           \++++++++++++\'                         
Write-Host '            \------------\'
Write-Host
Write-Host
Write-host 'Pure Storage VMware ESXi UNMAP Script v3.0'
write-host '----------------------------------------------'
write-host
#For info, refer to www.codyhosterman.com 

#Enter the following parameters. Put all entries inside the quotes.
#One or more FlashArrays are supported. Remove/add additional ,''s for more/less arrays.
#Remove '<array IP or FQDN #>' and replace that entire string with a FlashArray IP or FQDN like '192.168.0.10'. Separate each array by a comma.
#**********************************
$vcenter = ''
$vcuser = ''
$vcpass = ''
$flasharrays = @('<array IP or FQDN 1>','<array IP or FQDN 2>','<array IP or FQDN 3>')
$pureuser = ''
$pureuserpwd = ''
$logfolder = 'C:\folder\folder\etc\'
$unmaplogfile = 'unmap.txt'
#End of parameters

#Requires -Version 3

<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will identify Pure Storage FlashArray volumes and issue UNMAP against them. The script uses the best practice 
recommendation block count of 1% of the free capacity of the datastore. All operations are logged to a file and also 
output to the screen. REST API calls to the array before and after UNMAP will report on how much (if any) space has been reclaimed.

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-PowerShell 3.0 or later
-Pure Storage PowerShell SDK 1.0 or later
-PowerCLI 6.0 Release 1 or later (5.5/5.8 is likely fine, but not tested with this script version)
-REST API 1.4 and later
-Purity 4.1 and later
-FlashArray 400 Series and //m
-vCenter 5.5 and later
-Each FlashArray datastore must be present to at least one ESXi version 5.5 or later host or it will not be reclaimed
#>

#Create log folder if non-existent
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + $unmaplogfile

#Connect to FlashArray via REST
$facount=0
$purevols=$null
$purevol=$null
$EndPoint= @()

$Pwd = ConvertTo-SecureString $pureuserpwd -AsPlainText -Force
$Creds = New-Object System.Management.Automation.PSCredential ($pureuser, $pwd)

<#Connect to FlashArray via REST with the SDK

Creates an array of connections for as many FlashArrays as you have entered into the $flasharrays variable. Assumes the same credentials are in use for every FlashArray

#>

foreach ($flasharray in $flasharrays)
{
    if ($facount -eq 0)
    {
        $EndPoint = @(New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError)
        $purevolumes = @(Get-PfaVolumes -Array $EndPoint[$facount])
        $tempvols = @(Get-PfaVolumes -Array $EndPoint[$facount])  
        $arraysnlist = @(@{$tempvols[0].serial.substring(0,16) = $facount})
    }
    else
    {
        $EndPoint += New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError
        $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
        $tempvols = Get-PfaVolumes -Array $EndPoint[$facount]   
        $arraysnlist += @{$tempvols[0].serial.substring(0,16) = $facount}
    }
    $facount = $facount + 1
}

write-host 'Connection to FlashArray successful' -foregroundcolor green
write-host
add-content $logfile 'Connected to FlashArray:'
add-content $logfile $purevip
add-content $logfile '----------------'

#Important PowerCLI if not done and connect to vCenter
if ( (Get-PSSnapin -Name VMware.* -ErrorAction SilentlyContinue) -eq $null )
{
    Add-PsSnapin VMware.VimAutomation.Core
}
#Set-PowerCLIConfiguration -invalidcertificateaction 'ignore' -confirm:$false |out-null
#Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -confirm:$false |out-null
connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
write-host 'Connection to vCenter successful' -foregroundcolor green
write-host
add-content $logfile 'Connected to vCenter:'
add-content $logfile $vcenter
add-content $logfile '----------------'

#Gather VMFS Datastores and identify how many are Pure Storage volumes
write-host 'Initiating VMFS UNMAP for all Pure Storage volumes in the vCenter' -foregroundcolor Cyan
write-host 'Searching for VMFS volumes to reclaim (UNMAP)'
$datastores = get-datastore
write-host 'Found ' $datastores.count ' VMFS volume(s).'
write-host
write-host 'Iterating through VMFS volumes and running a reclamation on Pure Storage volumes only'
write-host
write-host 'Please be patient, this process can take a long time depending on how many volumes and their capacity'
write-host '------------------------------------------------------------------------------------------------------'
write-host
add-content $logfile 'Found the following datastores:'
add-content $logfile $datastores
add-content $logfile '***************'

#Starting UNMAP Process on datastores
$volcount=0
$purevol = $null
foreach ($datastore in $datastores)
{
    write-host '--------------------------------------------------------------------------'
    write-host 'Analyzing the following volume:'
    write-host
    $esx = $datastore | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.0.*')} |Select-Object -last 1
    if ($datastore.Type -ne 'VMFS')
    {
        write-host 'This volume is not a VMFS volume and cannot be reclaimed. Skipping...'
        write-host $datastore.Type
        add-content $logfile 'This volume is not a VMFS volume and cannot be reclaimed. Skipping...'
        add-content $logfile $datastore.Type
    }
    else
    {
        $lun = get-scsilun -datastore $datastore | select-object -last 1
        $esxcli=get-esxcli -VMHost $esx
        add-content $logfile 'The following datastore is being examined:'
        add-content $logfile $datastore 
        add-content $logfile 'The following ESXi is the chosen source:'
        add-content $logfile $esx 
        write-host 'VMFS Datastore:' $datastore.Name $lun.CanonicalName

        if ($lun.canonicalname -like 'naa.624a9370*')
        {
            write-host $datastore.name 'is a Pure Storage Volume and will be reclaimed.' -foregroundcolor Cyan
            write-host
            $volserial = ($lun.CanonicalName.ToUpper()).substring(12)
            $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
            $arraychoice = $arraysnlist.($volserial.substring(0,16))
            $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
            $volreduction = '{0:N3}' -f ($volinfo.data_reduction)
            $volphysicalcapacity = '{0:N3}' -f ($volinfo.volumes/1024/1024/1024)
            add-content $logfile 'This datastore is a Pure Storage Volume.'
            add-content $logfile $lun.CanonicalName
            add-content $logfile 'The current data reduction for this volume prior to UNMAP is:'
            add-content $logfile $volreduction
            add-content $logfile 'The current physical space consumption in GB of this device prior to UNMAP is:'
            add-content $logfile $volphysicalcapacity
            write-host 'This volume has a data reduction ratio of' $volreduction 'to 1 prior to reclamation.' -foregroundcolor green
            write-host 'This volume has' $volphysicalcapacity 'GB of data physically written to the SSDs on the FlashArray prior to reclamation.' -foregroundcolor green
            write-host
            write-host 'Determining maximum allowed block count for this datastore (1 % of free capacity)'
            $blockcount = [math]::floor($datastore.FreeSpaceMB * .01)
            write-host 'The maximum allowed block count for this datastore is' $blockcount -foregroundcolor green
            add-content $logfile 'The maximum allowed block count for this datastore is'
            add-content $logfile $blockcount
            write-host 'Initiating reclaim...Operation time will vary depending on block count, free capacity of volume and other factors.'
            $esxcli.storage.vmfs.unmap($blockcount, $datastore.Name, $null) |out-null
            write-host
            Start-Sleep -s 10
            write-host 'Reclaim complete.'
            write-host
            write-host 'Results:'
            write-host '-----------'
            $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
            $volreduction = '{0:N3}' -f ($volinfo.data_reduction)
            $volphysicalcapacitynew = '{0:N3}' -f ($volinfo.volumes/1024/1024/1024)
            write-host 'This volume now has a data reduction ratio of' $volreduction 'to 1 after reclamation.' -foregroundcolor green
            write-host 'This volume now has' $volphysicalcapacitynew 'GB of data physically written to the SSDs on the FlashArray after reclamation.' -foregroundcolor green
            $unmapsavings = ($volphysicalcapacity - $volphysicalcapacitynew)
            write-host
            write-host 'The UNMAP process has reclaimed' $unmapsavings 'GB of space from this volume on the FlashArray.' -foregroundcolor green
            $volcount=$volcount+1
            add-content $logfile 'The new data reduction for this volume after UNMAP is:'
            add-content $logfile $volreduction
            add-content $logfile 'The new physical space consumption in GB of this device after UNMAP is:'
            add-content $logfile $volphysicalcapacitynew
            add-content $logfile 'The following capacity in GB has been reclaimed from the FlashArray from this volume:'
            add-content $logfile $unmapsavings
            add-content $logfile '---------------------'
            Start-Sleep -s 5
        }
        else
        {
            add-content $logfile 'This datastore is NOT a Pure Storage Volume. Skipping...'
            add-content $logfile $lun.CanonicalName
            add-content $logfile '---------------------'
            write-host $datastore.name ' is not a Pure Volume and will not be reclaimed. Skipping...' -foregroundcolor red
        }
    }
}
write-host '--------------------------------------------------------------------------'
write-host 'Reclamation finished. A total of' $volcount 'Pure Storage volume(s) were reclaimed'

#disconnecting sessions
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $flasharrays)
{
    Disconnect-PfaArray -Array $flasharray
}