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

This script will identify Pure Storage FlashArray volumes and issue UNMAP against them. The script uses the best practice 
recommendation block count of 1% of the free capacity of the datastore. All operations are logged to a file and also 
output to the screen. REST API calls to the array before and after UNMAP will report on how much (if any) space has been reclaimed.

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-PowerShell 3.0 or later
-Pure Storage PowerShell SDK 1.5 or later
-PowerCLI 6.3 Release 1+
-REST API 1.4 and later
-Purity 4.1 and later
-FlashArray 400 Series and //m
-vCenter 5.5 and later
-Each FlashArray datastore must be present to at least one ESXi version 5.5 or later host or it will not be reclaimed
#>

#Create log folder if non-existent
write-host "Please choose a directory to store the script log"
function ChooseFolder([string]$Message, [string]$InitialDirectory)
{
    $app = New-Object -ComObject Shell.Application
    $folder = $app.BrowseForFolder(0, $Message, 0, $InitialDirectory)
    $selectedDirectory = $folder.Self.Path 
    return $selectedDirectory
}
$logfolder = ChooseFolder -Message "Please select a log file directory" -InitialDirectory 'MyComputer' 
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "unmapresults.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green

#Configure optional Log Insight target
$useloginsight = read-host "Would you like to send the UNMAP results to a Log Insight instance (y/n)"
while (($useloginsight -ine "y") -and ($useloginsight -ine "n"))
{
    write-host "Invalid entry, please enter y or n"
    $useloginsight = read-host "Would you like to send the UNMAP results to a Log Insight instance (y/n)"
}
if ($useloginsight -ieq "y")
{
    $loginsightserver = read-host "Enter in the FQDN or IP of Log Insight"
    $loginsightagentID = read-host "Enter a Log Insight Agent ID"
    add-content $logfile ('Results will be sent to the following Log Insight instance ' + $loginsightserver + ' with the UUID of ' + $loginsightagentID)
}
elseif ($useloginsight -ieq "n")
{
    add-content $logfile ('Log Insight will not be used for external logging')
}

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
        add-content $logfile ("PowerCLI not found. Please verify installation and retry.")
        add-content $logfile "Get it here: https://my.vmware.com/web/vmware/details?downloadGroup=PCLI650R1&productId=614"
        add-content $logfile "Terminating Script" 
        return
    }
        
}
#Set
Set-PowerCLIConfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -confirm:$false |out-null

if ( !(Get-Module -ListAvailable -Name PureStoragePowerShellSDK -ErrorAction SilentlyContinue) ) {
    write-host ("FlashArray PowerShell SDK not found. Please verify installation and retry.") -BackgroundColor Red
    write-host "Get it here: https://github.com/PureStorage-Connect/PowerShellSDK"
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile ("FlashArray PowerShell SDK not found. Please verify installation and retry.")
    add-content $logfile "Get it here: https://github.com/PureStorage-Connect/PowerShellSDK"
    add-content $logfile "Terminating Script" 
    return
}
write-host '             __________________________'
write-host '            /++++++++++++++++++++++++++\'           
write-host '           /++++++++++++++++++++++++++++\'           
write-host '          /++++++++++++++++++++++++++++++\'         
write-host '         /++++++++++++++++++++++++++++++++\'        
write-host '        /++++++++++++++++++++++++++++++++++\'       
write-host '       /++++++++++++/----------\++++++++++++\'     
write-host '      /++++++++++++/            \++++++++++++\'    
write-host '     /++++++++++++/              \++++++++++++\'   
write-host '    /++++++++++++/                \++++++++++++\'  
write-host '   /++++++++++++/                  \++++++++++++\' 
write-host '   \++++++++++++\                  /++++++++++++/' 
write-host '    \++++++++++++\                /++++++++++++/' 
write-host '     \++++++++++++\              /++++++++++++/'  
write-host '      \++++++++++++\            /++++++++++++/'    
write-host '       \++++++++++++\          /++++++++++++/'     
write-host '        \++++++++++++\'                   
write-host '         \++++++++++++\'                           
write-host '          \++++++++++++\'                          
write-host '           \++++++++++++\'                         
write-host '            \------------\'
write-host 'Pure Storage FlashArray VMware ESXi UNMAP Script v5.0'
write-host '----------------------------------------------------------------------------------------------------'

$FAcount = 0
$inputOK = $false
do
{
  try
  {
    [int]$FAcount = Read-Host "How many FlashArrays do you need to enter (enter a number)"
    $inputOK = $true
  }
  catch
  {
    Write-Host -ForegroundColor red "INVALID INPUT!  Please enter a numeric value."
  } 
}
until ($inputOK)
$flasharrays = @()
for ($i=0;$i -lt $FAcount;$i++)
{
    $flasharray = read-host "Please enter a FlashArray IP or FQDN"
    $flasharrays += $flasharray
}
$Creds = $Host.ui.PromptForCredential("FlashArray Credentials", "Please enter your FlashArray username and password.", "","")
#Connect to FlashArray via REST
$purevolumes=@()
$purevol=$null
$EndPoint= @()
$arraysnlist = @()

<#
Connect to FlashArray via REST with the SDK 
Assumes the same credentials are in use for every FlashArray
#>

foreach ($flasharray in $flasharrays)
{
    try
    {
        $tempArray = (New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError -ErrorAction stop)
        $EndPoint +=  $temparray
        $purevolumes += Get-PfaVolumes -Array  $tempArray
        $arraySN = Get-PfaArrayAttributes -Array $tempArray
        
        if ($arraySN.id[0] -eq "0")
        {
          $arraySN = $arraySN.id.Substring(1)
          $arraySN = $arraySN.substring(0,19)
        } 
        else
        {
            $arraySN = $arraySN.id.substring(0,18)
        }
        $arraySN = $arraySN -replace '-','' 
        $arraysnlist += $arraySN
        add-content $logfile "FlashArray shortened serial is $($arraySN)"
    }
    catch
    {
        add-content $logfile ""
        add-content $logfile ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN")
        add-content $logfile $Error[0]
        add-content $logfile "Terminating Script" 
        return
    }
}

add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile 'Connected to the following FlashArray(s):'
add-content $logfile $flasharrays
add-content $logfile '----------------------------------------------------------------------------------------------------'
write-host ""
$vcenter = read-host "Please enter a vCenter IP or FQDN"
$newcreds = Read-host "Re-use the FlashArray credentials for vCenter? (y/n)"
while (($newcreds -ine "y") -and ($newcreds -ine "n"))
{
    write-host "Invalid entry, please enter y or n"
    $newcreds = Read-host "Re-use the FlashArray credentials for vCenter? (y/n)"
}
if ($newcreds -ieq "n")
{
    $Creds = $Host.ui.PromptForCredential("vCenter Credentials", "Please enter your vCenter username and password.", "","")
}
try
{
    connect-viserver -Server $vcenter -Credential $Creds -ErrorAction Stop |out-null
    add-content $logfile ('Connected to the following vCenter:')
    add-content $logfile $vcenter
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
                    name = "ReclaimedSpaceGB"
                    content = $reclaimedvirtualspace
                    }
    $esxhost = [ordered]@{
                    name = "ESXihost"
                    content = $esxchosen[$i].name
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
    $resturl = ("http://" + $loginsightserver + ":9000/api/v1/messages/ingest/" + $loginsightagentID)
    add-content $logfile ""
    if($i=0){add-content $logfile ("Posting results to Log Insight server: " + $loginsightserver)}
    try
    {
        $response = Invoke-RestMethod $resturl -Method Post -Body $restcall -ContentType 'application/json' -ErrorAction stop
        if($i=0){add-content $logfile "REST Call to Log Insight server successful"}
    }
    catch
    {
        add-content $logfile "REST Call failed to Log Insight server"
        add-content $logfile $error[0]
        add-content $logfile $resturl
    }
}
$arrayspacestart = @()
foreach ($flasharray in $endpoint)
{
    $arrayspacestart += Get-PfaArraySpaceMetrics -array $flasharray
}
#Gather VMFS Datastores and identify how many are Pure Storage volumes
$reclaimeddatastores = @()
$virtualspace = @()
$physicalspace = @()
$esxchosen = @()
$expectedreturns = @()
$datastores = get-datastore
add-content $logfile 'Found the following datastores:'
add-content $logfile $datastores
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Starting UNMAP Process on datastores
write-host "Please be patient--this process can take a long time"
$purevol = $null
foreach ($datastore in $datastores)
{
    add-content $logfile (get-date)
    add-content $logfile ('The datastore named ' + $datastore + ' is being examined')
    $esx = $datastore | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.*')}| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1
    $unmapconfig = ""
    if ($datastore.ExtensionData.Info.Vmfs.majorVersion -eq 6)
    {
        $esxcli=get-esxcli -VMHost $esx -v2
        add-content $logfile ("The datastore named " + $datastore.name + " is VMFS version 6. Checking Automatic UNMAP configuration...")
        $unmapargs = $esxcli.storage.vmfs.reclaim.config.get.createargs()
        $unmapargs.volumelabel = $datastore.name
        $unmapconfig = $esxcli.storage.vmfs.reclaim.config.get.invoke($unmapargs)
    }
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
    elseif ($unmapconfig.ReclaimPriority -eq "low")
    {
        add-content $logfile ('This VMFS has Automatic UNMAP enabled. No need to run a manual reclaim. Skipping...')
        add-content $logfile ''
        add-content $logfile '----------------------------------------------------------------------------------------------------'
    } 
    else
    {
        $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique 
        if ($lun.count -eq 1)
        {
            add-content $logfile ("The UUID for this volume is " + $datastore.ExtensionData.Info.Vmfs.Extent.DiskName)
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
                   continue

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
                    $arrayname = Get-PfaArrayAttributes -array $EndPoint[$arraychoice]
                    add-content $logfile ('The volume is on the FlashArray ' + $arrayname.array_name)
                    add-content $logfile ('This datastore is a Pure Storage volume named ' + $purevol.name)
                    add-content $logfile ''
                    add-content $logfile ('The ESXi named ' + $esx + ' will run the UNMAP/reclaim operation')
                    add-content $logfile ''
                    $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
                    $usedvolcap = ((1 - $volinfo.thin_provisioning)*$volinfo.size)/1024/1024/1024
                    $virtualspace += '{0:N0}' -f ($usedvolcap)
                    $physicalspace += '{0:N0}' -f ($volinfo.volumes/1024/1024/1024)
                    $usedspace = $datastore.CapacityGB - $datastore.FreeSpaceGB
                    $deadspace = '{0:N0}' -f ($usedvolcap - $usedspace)
                    if ($deadspace -lt 0)
                    {
                        $deadspace = 0
                    }
                    add-content $logfile ('The current used space of this VMFS is ' + ('{0:N0}' -f ($usedspace)) + " GB")
                    add-content $logfile ('The current used virtual space for its FlashArray volume is approximately ' + ('{0:N0}' -f ($usedvolcap)) + " GB")
                    $reclaimable = ('{0:N0}' -f ($deadspace))
                    if ($reclaimable -like "-*")
                    {
                        $reclaimable = 0
                    }
                    $expectedreturns += $reclaimable
                    add-content $logfile ('The minimum reclaimable virtual space for this FlashArray volume is ' + $reclaimable + ' GB')
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
                        $blockcount = [math]::floor($datastore.FreeSpaceMB * .008)
                        add-content $logfile ("The maximum allowed block count for this datastore is " + $blockcount)
                    }
                    $unmapargs = $esxcli.storage.vmfs.unmap.createargs()
                    $unmapargs.volumelabel = $datastore.Name
                    $unmapargs.reclaimunit = $blockcount
                    try
                    {
                        $reclaimeddatastores += $datastore
                        $esxchosen += $esx
                        write-host ("Running UNMAP on VMFS named " + $datastore.Name + "...")
                       $esxcli.storage.vmfs.unmap.invoke($unmapargs) |out-null
                    }
                    catch
                    {
                        add-content $logfile "Failed to complete UNMAP to this volume. Most common cause is a PowerCLI timeout which means UNMAP will continue to completion in the background for this VMFS."
                        add-content $logfile $Error[0]
                        add-content $logfile "Moving to the next volume"
                        continue
                    }
                    add-content $logfile ''
                    add-content $logfile '----------------------------------------------------------------------------------------------------'
                }
            }
            else
            {
                add-content $logfile ('The volume is not a FlashArray device, skipping the UNMAP operation')
                add-content $logfile ''
                add-content $logfile '----------------------------------------------------------------------------------------------------'
                continue
            }
        }
        elseif ($lun.count -gt 1)
            {
                add-content $logfile ('The volume spans more than one SCSI device, skipping UNMAP operation')
                add-content $logfile ''
                add-content $logfile '----------------------------------------------------------------------------------------------------'
                continue
            }
    }
}
$arrayspaceend = @()
$arraychanges = @()
$finaldatastores = @()
$totalreclaimedvirtualspace = 0
#start-sleep 120
for ($i=0;$i -lt $reclaimeddatastores.count;$i++)
{
    $lun = $reclaimeddatastores[$i].ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
    $volserial = ($lun.ToUpper()).substring(12) 
    $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
    for($a=0; $a -lt $arraysnlist.count; $a++)
    {
        if ($arraysnlist[$a] -eq ($volserial.substring(0,16)))
        {
            $arraychoice = $a
        }
    }
    $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
    $usedvolcap = '{0:N0}' -f (((1 - $volinfo.thin_provisioning)*$volinfo.size)/1024/1024/1024)
    $newphysicalspace = '{0:N0}' -f ($volinfo.volumes/1024/1024/1024)
    $reclaimedvirtualspace = $virtualspace[$i] - $usedvolcap
    $reclaimedphysicalspace = $physicalspace[$i] - $newphysicalspace
    $totalreclaimedvirtualspace += $reclaimedvirtualspace
    if ($reclaimedvirtualspace -like "-*")
    {
        $reclaimedvirtualspace = 0
    }
    if ($reclaimedphysicalspace -like "-*")
    {
        $reclaimedphysicalspace = 0
    }
    $finaldatastores += New-Object psobject -Property @{Datastore=$($reclaimeddatastores[$i].name);Volume=$($purevol.name);ExpectedMinimumVirtualSpaceGBReclaimed=$($expectedreturns[$i]);ActualVirtualSpaceGBReclaimed=$($reclaimedvirtualspace);ActualPhysicalSpaceGBReclaimed=$($reclaimedphysicalspace)}
    if ($useloginsight -ieq "y"){logInsightRestCall}
}

for ($i=0;$i -lt $endpoint.count;$i++)
{
    $arrayspaceend += Get-PfaArraySpaceMetrics -array $endpoint[$i]
    $physicalspacedifference = ($arrayspacestart[$i].volumes - $arrayspaceend[$i].volumes)/1024/1024/1024
    if ($physicalspacedifference -like "-*")
    {
        $physicalspacedifference = 0
    }
    if ($totalreclaimedvirtualspace[$i] -like "-*")
    {
        $virtualspacedifference = 0
    }
    else
    {
        $virtualspacedifference = $totalreclaimedvirtualspace[$i]
    }
    $arraychanges += New-Object psobject -Property @{FlashArray=$($arrayspaceend[$i].hostname);VirtualSpaceGBReclaimed=$('{0:N0}' -f ($virtualspacedifference));PhysicalSpaceGBReclaimed=$('{0:N0}' -f ($physicalspacedifference))}
}
add-content $logfile "FlashArray-level Reclamation Statistics:"
write-host "FlashArray-level Reclamation Statistics:"
write-host ($arraychanges |ft -autosize -Property FlashArray,VirtualSpaceGBReclaimed,PhysicalSpaceGBReclaimed | Out-String )
$arraychanges|ft -autosize -Property FlashArray,VirtualSpaceGBReclaimed,PhysicalSpaceGBReclaimed | Out-File -FilePath $logfile -Append -Encoding ASCII

add-content $logfile "Volume-level Reclamation Statistics:"
write-host "Volume-level Reclamation Statistics:"
write-host ($finaldatastores |ft -autosize -Property Datastore,Volume,ExpectedMinimumVirtualSpaceGBReclaimed,ActualVirtualSpaceGBReclaimed,ActualPhysicalSpaceGBReclaimed | Out-String )
$finaldatastores|ft -autosize -Property Datastore,Volume,ExpectedMinimumVirtualSpaceGBReclaimed,ActualVirtualSpaceGBReclaimed,ActualPhysicalSpaceGBReclaimed | Out-File -FilePath $logfile -Append -Encoding ASCII

add-content $logfile ("Space reclaim operation for all FlashArray VMFS volumes is complete.")
add-content $logfile ""
#disconnecting sessions
add-content $logfile ("Disconnecting vCenter and FlashArray sessions")
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}