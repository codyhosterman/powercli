#***************************************************************************************************
#VMWARE POWERCLI AND PURE STORAGE POWERSHELL SDK MUST BE INSTALLED ON THE MACHINE THIS IS RUNNING ON
#***************************************************************************************************
#
#For info, refer to www.codyhosterman.com
#
#*****************************************************************
#Enter the following parameters. Put all entries inside the quotes.
#One or more FlashArrays are supported. Remove/add additional ,''s for more/less arrays.
#Remove '<array IP or FQDN>' and replace that entire string with a FlashArray IP or FQDN like '192.168.0.10'. Separate each array by a comma.
#*****************************************************************
$vcenter = ""
$vcuser = ""
$vcpass = ""
$flasharrays = @('<array IP or FQDN>','<array IP or FQDN>')
$pureuser = ""
$pureuserpwd = ""
$logfolder = 'C:\folder\folder\etc\'

#Optional settings. Leave equal to $null if not needed. Otherwise add a IP or FQDN inside of double quotes and a UUID for the agentID.
$loginsightserver = $null
$loginsightagentID = ""

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
-Pure Storage PowerShell SDK 1.5 or later
-PowerCLI 6.3 Release 1
-REST API 1.4 and later
-Purity 4.1 and later
-FlashArray 400 Series and //m
-vCenter 5.5 and later
-Each FlashArray datastore must be present to at least one ESXi version 5.5 or later host or it will not be reclaimed
#>
#Create log folder if non-existent
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "unmap.txt"

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
add-content $logfile 'Pure Storage VMware ESXi UNMAP Script v4.0'
add-content $logfile '----------------------------------------------------------------------------------------------------'

#A function to make REST Calls to Log Insight
function logInsightRestCall
{
    $restvmfs = [ordered]@{
                    name = "Datastore"
                    content = $datastore.Name
                    }
    $restarray = [ordered]@{
                    name = "FlashArray"
                    content = $endpoint[$arraychoice].endpoint
                    }
    $restvol = [ordered]@{
                    name = "FlashArrayvol"
                    content = $purevol.name
                    }
    $restunmap = [ordered]@{
                    name = "ReclaimedSpace"
                    content = $unmapsavings
                    }
    $esxhost = [ordered]@{
                    name = "ESXihost"
                    content = $esx
                    }
    $devicenaa = [ordered]@{
                    name = "SCSINaa"
                    content = $lun
                    }
    $fields = @($restvmfs,$restarray,$restvol,$restunmap,$esxhost,$devicenaa)
    $restcall = @{
                 messages =    ([Object[]]($messages = [ordered]@{
                        text = ("Completed an UNMAP operation on the VMFS volume named " + $datastore.Name + " that is on the FlashArray named " + $endpoint[$arraychoice].endpoint + ".")
                        fields = ([Object[]]$fields)
                        }))
                } |convertto-json -Depth 4
    $loginsightserver = "loginsight.csgvmw.local"
    $resturl = ("http://" + $loginsightserver + ":9000/api/v1/messages/ingest/" + $loginsightagentID)
    add-content $logfile ""
    add-content $logfile ("Posting results to Log Insight server: " + $loginsightserver)
    try
    {
        $response = Invoke-RestMethod $resturl -Method Post -Body $restcall -ContentType 'application/json' -ErrorAction stop
        add-content $logfile "REST Call to Log Insight server successful"
        $response| out-string |add-content $logfile
    }
    catch
    {
        add-content $logfile "REST Call failed to Log Insight server"
        add-content $logfile $error[0]
        add-content $logfile $resturl
    }
}

#Connect to FlashArray via REST
$facount=0
$purevolumes=@()
$purevol=$null
$EndPoint= @()
$Pwd = ConvertTo-SecureString $pureuserpwd -AsPlainText -Force
$Creds = New-Object System.Management.Automation.PSCredential ($pureuser, $pwd)
write-host "Script information can be found at $logfile" -ForegroundColor Green

<#
Connect to FlashArray via REST with the SDK
Creates an array of connections for as many FlashArrays as you have entered into the $flasharrays variable. 
Assumes the same credentials are in use for every FlashArray
#>

foreach ($flasharray in $flasharrays)
{
    if ($facount -eq 0)
    {
        try
        {
            $EndPoint += (New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError -ErrorAction stop)
        }
        catch
        {
            write-host ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN") -BackgroundColor Red
            write-host $Error[0]
            write-host "Terminating Script" -BackgroundColor Red
            add-content $logfile ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN")
            add-content $logfile $Error[0]
            add-content $logfile "Terminating Script" 
            return
        }
        $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
        $tempvols = @(Get-PfaVolumes -Array $EndPoint[$facount])  
        $arraysnlist = @($tempvols.serial[0].substring(0,16))
    }
    else
    {
        try
        {
            $EndPoint += New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError
            $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
            $tempvols = Get-PfaVolumes -Array $EndPoint[$facount]   
            $arraysnlist += $tempvols.serial[0].substring(0,16)
        }
        catch
        {
            write-host ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN") -BackgroundColor Red
            write-host $Error[0]
            add-content $logfile ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN")
            add-content $logfile $Error[0]
            return
        }
    }
    $facount = $facount + 1
}

add-content $logfile 'Connected to the following FlashArray(s):'
add-content $logfile $flasharrays
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Important PowerCLI if not done and connect to vCenter. 

if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1" 
}
Set-PowerCLIConfiguration -invalidcertificateaction 'ignore' -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -confirm:$false |out-null
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
    add-content $logfile "Get it here: https://my.vmware.com/group/vmware/get-download?downloadGroup=PCLI630R1"
    return
}

try
{
    connect-viserver -Server $vcenter -username $vcuser -password $vcpass -ErrorAction Stop |out-null
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

write-host "No further information is printed to the screen."
add-content $logfile ('Connected to vCenter at ' + $vcenter)
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Gather VMFS Datastores and identify how many are Pure Storage volumes
$datastores = get-datastore
add-content $logfile 'Found the following datastores:'
add-content $logfile $datastores
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Starting UNMAP Process on datastores
$volcount=0
$purevol = $null
$totalspacereclaimed = 0
foreach ($datastore in $datastores)
{
    add-content $logfile (get-date)
    add-content $logfile ('The datastore named ' + $datastore + ' is being examined')
    $esx = $datastore | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.0.*')}| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1
    if ($datastore.Type -ne 'VMFS')
    {
        add-content $logfile ('This volume is not a VMFS volume, it is of type ' + $datastore.Type + ' and cannot be reclaimed. Skipping...')
        add-content $logfile ''
        add-content $logfile '----------------------------------------------------------------------------------------------------'
    }
    elseif ($esx.count -eq 0)
    {
        add-content $logfile ('This datastore has no 5.5 or later hosts to run UNMAP from. Skipping...')
        add-content $logfile ''
        add-content $logfile '----------------------------------------------------------------------------------------------------'

    } 
    else
    {
        $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique 
        if ($lun.count -eq 1)
        {
            add-content $logfile "The UUID for this volume is:"
            add-content $logfile ($datastore.ExtensionData.Info.Vmfs.Extent.DiskName)
            $esxcli=get-esxcli -VMHost $esx -v2
            if ($lun -like 'naa.624a9370*')
            {
                $volserial = ($lun.ToUpper()).substring(12)
                $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
                if ($purevol.name -eq $null)
                {
                   add-content $logfile 'ERROR: This volume has not been found. Please make sure that all of the FlashArrays presented to this vCenter are entered into this script.'
                   add-content $logfile ''
                   add-content $logfile '----------------------------------------------------------------------------------------------------'

                }
                else
                {
                    for($i=0; $i -lt $arraysnlist.count; $i++)
                    {
                        if ($arraysnlist[$i] -eq ($volserial.substring(0,16)))
                        {
                            $arraychoice = $i
                        }
                    }
                    add-content $logfile ('The volume is on the FlashArray ' + $endpoint[$arraychoice].endpoint)
                    add-content $logfile ('This datastore is a Pure Storage volume named ' + $purevol.name)
                    add-content $logfile ''
                    add-content $logfile ('The ESXi named ' + $esx + ' will run the UNMAP/reclaim operation')
                    add-content $logfile ''
                    $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
                    $volreduction = '{0:N3}' -f ($volinfo.data_reduction)
                    $volphysicalcapacity = '{0:N3}' -f ($volinfo.volumes/1024/1024)
                    add-content $logfile ''
                    add-content $logfile ('The current data reduction for this volume before UNMAP is ' + $volreduction + " to 1")
                    add-content $logfile ('The  physical space consumption in MB of this device before UNMAP is ' + $volphysicalcapacity)
                    add-content $logfile ''
                    #Calculating optimal block count. If VMFS is 75% full or more the count must be 200 MB only. Ideal block count is 1% of free space of the VMFS in MB
                    if ((1 - $datastore.FreeSpaceMB/$datastore.CapacityMB) -ge .75)
                    {
                        $blockcount = 200
                        add-content $logfile 'The volume is 75% or more full so the block count is overridden to 200 MB. This will slow down the reclaim dramatically'
                        add-content $logfile 'It is recommended to either free up space on the volume or increase the capacity so it is less than 75% full'
                        add-content $logfile ("The block count in MB will be " + $blockcount)
                    }
                    else
                    {
                        $blockcount = [math]::floor($datastore.FreeSpaceMB * .01)
                        add-content $logfile ("The maximum allowed block count for this datastore is " + $blockcount)
                    }
                    $unmapargs = $esxcli.storage.vmfs.unmap.createargs()
                    $unmapargs.volumelabel = $datastore.Name
                    $unmapargs.reclaimunit = $blockcount
                    try
                    {
                        $esxcli.storage.vmfs.unmap.invoke($unmapargs) |out-null
                    }
                    catch
                    {
                        add-content $logfile "Failed to run UNMAP to this volume. Most common cause is the device is locked by another process."
                        add-content $logfile $Error[0]
                        add-content $logfile "Skipping volume..."
                    }
                    Start-Sleep -s 10
                    $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
                    $volreduction = '{0:N3}' -f ($volinfo.data_reduction)
                    $volphysicalcapacitynew = '{0:N3}' -f ($volinfo.volumes/1024/1024)
                    $unmapsavings = [math]::Round(($volphysicalcapacity - $volphysicalcapacitynew),2)
                    $volcount=$volcount+1
                    add-content $logfile ''
                    add-content $logfile ('The new data reduction for this volume after UNMAP is ' + $volreduction + " to 1")
                    add-content $logfile ('The new physical space consumption in MB of this device after UNMAP is ' + $volphysicalcapacitynew)
                    add-content $logfile ("$unmapsavings" + ' in MB has been reclaimed from the FlashArray from this volume')
                    $totalspacereclaimed = $totalspacereclaimed + $unmapsavings
                    if ($loginsightserver -ne $null){logInsightRestCall}
                    add-content $logfile ''
                    add-content $logfile '----------------------------------------------------------------------------------------------------'
                    Start-Sleep -s 5
                }
            }
            else
            {
                add-content $logfile ('The volume is not a FlashArray device, skipping the UNMAP operation')
                add-content $logfile ''
                add-content $logfile '----------------------------------------------------------------------------------------------------'
            }
        }
        elseif ($lun.count -gt 1)
            {
                add-content $logfile ('The volume spans more than one SCSI device, skipping UNMAP operation')
                add-content $logfile ''
                add-content $logfile '----------------------------------------------------------------------------------------------------'
            }
    }
}
add-content $logfile ("Space reclaim operation for all volumes is complete. Total immediate space reclaimed is " + $totalspacereclaimed + " MB")
add-content $logfile "Note that more space will likely reclaim over time."
add-content $logfile ""
#disconnecting sessions
add-content $logfile ("Disconnecting vCenter and FlashArray sessions")
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}