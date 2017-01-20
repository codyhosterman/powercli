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
#Threshold is in GB. This will return only datastores with that number of GB of virtual dead space or more
#*****************************************************************

<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will identify VMware VMFS volumes on Pure Storage FlashArray volumes that have a certain amount of virtual dead space and return those datastores.

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI and the FlashArray PowerShell SDK must be installed on the local host regardless.

Supports:
-PowerShell 3.0 or later
-Pure Storage PowerShell SDK 1.5 or later
-PowerCLI 6.3 Release 1 and later
-Purity 4.1 and later
-FlashArray 400 Series and //m
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
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "deadspace.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green
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
        add-content $logfile "Terminating Script" 
        return
    }
        
}
set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
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
write-host 'Pure Storage VMware ESXi Dead Space Detection Script v1.0'
write-host '----------------------------------------------------------------------------------------------------'

$FAcount = 0
$inputOK = $false
do
{
  try
  {
    [int]$FAcount = Read-Host "How many FlashArrays do you want to search? (enter a number)"
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
$facount=0
$purevolumes=@()
$purevol=$null
$EndPoint= @()

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
$inputOK = $false
do
{
  try
  {
    [int]$unmapthreshold = Read-Host "What virtual dead space threshold in GB do you want to limit the results to? (enter a number)"
    $inputOK = $true
  }
  catch
  {
    Write-Host -ForegroundColor red "INVALID INPUT!  Please enter a numeric value."
  } 
}
until ($inputOK)
write-host ""
write-host ""
$datastorestounmap =@()
$totaldeadspace = 0
$datastores = get-datastore 
foreach ($datastore in $datastores)
{
    add-content $logfile (get-date)
    add-content $logfile ('The datastore named ' + $datastore + ' is being examined')
    if ($datastore.Type -ne 'VMFS')
    {
        add-content $logfile ('This volume is not a VMFS volume, it is of type ' + $datastore.Type + ' and cannot be reclaimed. Skipping...')
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
                    $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
                    $usedvolcap = ((1 - $volinfo.thin_provisioning)*$volinfo.size)/1024/1024/1024
                    $usedspace = $datastore.CapacityGB - $datastore.FreeSpaceGB
                    $deadspace = '{0:N0}' -f ($usedvolcap - $usedspace)
                    $deadspace = [convert]::ToInt32($deadspace, 10)
                    if ($deadspace -ge $unmapthreshold)
                    {
                        add-content $logfile ('This volume has ' + $deadspace + ' GB of dead space.')
                        add-content $logfile ('This is greater than the specified UNMAP threshold of ' + $unmapthreshold + ' GB and should be reclaimed.')
                        $datastorestounmap += New-Object psobject -Property @{DeadSpaceGB=$($deadspace);DatastoreName=$($datastore.name)}
                        $totaldeadspace = $totaldeadspace + $deadspace
                    }
                    else
                    {
                        add-content $logfile ('This volume has ' + $deadspace + ' GB of dead space.')
                        add-content $logfile ('This is less than the specified UNMAP threshold of ' + $unmapthreshold + ' GB and will be skipped.')
                    }
                    add-content $logfile ''
                    add-content $logfile '----------------------------------------------------------------------------------------------------'
                }
            }
            else
            {
                add-content $logfile ('The volume is not a FlashArray device, skipping...')
                add-content $logfile ''
                add-content $logfile '----------------------------------------------------------------------------------------------------'
            }
        }
        elseif ($lun.count -gt 1)
            {
                add-content $logfile ('The volume spans more than one SCSI device, skipping...')
                add-content $logfile ''
                add-content $logfile '----------------------------------------------------------------------------------------------------'
            }
    }
}
add-content $logfile ""
add-content $logfile ("Analysis for all volumes is complete. Total possible virtual space that can be reclaimed is " + $totaldeadspace + " GB:")
if ($datastorestounmap.count -gt 0)
{
    write-host ("Analysis for all volumes is complete. Total possible virtual space that can be reclaimed is " + $totaldeadspace + " GB:")
    write-host ("The following datastores have more than " + $unmapthreshold + " GB of virtual dead space and are recommended for UNMAP")
    write-host ($datastorestounmap |ft -autosize -Property DatastoreName,DeadSpaceGB | Out-String )
    $datastorestounmap|ft -autosize -Property DatastoreName,DeadSpaceGB | Out-File -FilePath $logfile -Append -Encoding ASCII
}
else
{
    write-host "No datastores were identified with dead virtual space above the threshold."
}
#disconnecting sessions
add-content $logfile ("Disconnecting vCenter and FlashArray sessions")
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}