#***************************************************************************************************
#VMWARE POWERCLI AND PURE STORAGE POWERSHELL SDK MUST BE INSTALLED ON THE MACHINE THIS IS RUNNING ON
#***************************************************************************************************
#
#For info, refer to www.codyhosterman.com
#
#*****************************************************************
#Enter the following parameters. Put all entries inside the quotes.
#One or more FlashArrays are supported. Remove/add additional ,''s for more/less arrays.
#Remove '<array IP or FQDN #>' and replace that entire string with a FlashArray IP or FQDN like '192.168.0.10'. Separate each array by a comma.
#*****************************************************************
$vcenter = ''
$vcuser = ''
$vcpass = ''
$flasharrays = @('<array IP or FQDN #>','<array IP or FQDN #>','<array IP or FQDN #>')
$pureuser = ''
$pureuserpwd = ''
$logfolder = 'C:\folder\folder\etc\'
$unmaplogfile = 'unmap.txt'
$powercliversion = 6 #only change if your PowerCLI version is earlier than 6.0
#End of parameters
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
add-content $logfile 'Pure Storage VMware ESXi UNMAP Script v3.1'
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Connect to FlashArray via REST
$facount=0
$purevolumes=@()
$purevol=$null
$EndPoint= @()
$Pwd = ConvertTo-SecureString $pureuserpwd -AsPlainText -Force
$Creds = New-Object System.Management.Automation.PSCredential ($pureuser, $pwd)

<#Connect to FlashArray via REST with the SDK
Creates an array of connections for as many FlashArrays as you have entered into the $flasharrays variable. 
Assumes the same credentials are in use for every FlashArray
#>

foreach ($flasharray in $flasharrays)
{
    if ($facount -eq 0)
    {
        $EndPoint = @(New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError)
        $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
        $tempvols = @(Get-PfaVolumes -Array $EndPoint[$facount])  
        $arraysnlist = @($tempvols.serial[0].substring(0,16))
    }
    else
    {
        $EndPoint += New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError
        $purevolumes += Get-PfaVolumes -Array $EndPoint[$facount]
        $tempvols = Get-PfaVolumes -Array $EndPoint[$facount]   
        $arraysnlist += $tempvols.serial[0].substring(0,16)
    }
    $facount = $facount + 1
}

add-content $logfile 'Connected to the following FlashArray(s):'
add-content $logfile $flasharrays
add-content $logfile '----------------------------------------------------------------------------------------------------'

#Important PowerCLI if not done and connect to vCenter. Adds PowerCLI Snapin if 5.8 and earlier. For PowerCLI no import is needed since it is a module
$snapin = Get-PSSnapin -Name vmware.vimautomation.core -ErrorAction SilentlyContinue
if ($snapin.Name -eq $null )
{
    if ($powercliversion -ne 6) {Add-PsSnapin VMware.VimAutomation.Core} 
}
Set-PowerCLIConfiguration -invalidcertificateaction 'ignore' -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -confirm:$false |out-null
connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
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
foreach ($datastore in $datastores)
{
    $esx = $datastore | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.0.*')} |Select-Object -last 1
    if ($datastore.Type -ne 'VMFS')
    {
        add-content $logfile ('This volume is not a VMFS volume it is of type ' + $datastore.Type + ' and cannot be reclaimed. Skipping...')
        add-content $logfile '----------------------------------------------------------------------------------------------------'
    }
    else
    {
        $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName | select-object -last 1
        $datastore.ExtensionData.Info.Vmfs.Extent.DiskName
        $esxcli=get-esxcli -VMHost $esx
        add-content $logfile ('The datastore named ' + $datastore + ' is being examined')
        add-content $logfile ''
        add-content $logfile ('The ESXi named ' + $esx + ' will run the UNMAP/reclaim operation')
        add-content $logfile ''
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
            $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
            $volreduction = '{0:N3}' -f ($volinfo.data_reduction)
            $volphysicalcapacity = '{0:N3}' -f ($volinfo.volumes/1024/1024/1024)
            add-content $logfile 'This datastore is a Pure Storage Volume.'
            add-content $logfile $lun
            add-content $logfile ''
            add-content $logfile ('The current data reduction for this volume before UNMAP is ' + $volreduction + " to 1")
            add-content $logfile ('The  physical space consumption in GB of this device after UNMAP is ' + $volphysicalcapacity)
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
            $esxcli.storage.vmfs.unmap($blockcount, $datastore.Name, $null) |out-null
            Start-Sleep -s 10
            $volinfo = Get-PfaVolumeSpaceMetrics -Array $EndPoint[$arraychoice] -VolumeName $purevol.name
            $volreduction = '{0:N3}' -f ($volinfo.data_reduction)
            $volphysicalcapacitynew = '{0:N3}' -f ($volinfo.volumes/1024/1024/1024)
            $unmapsavings = ($volphysicalcapacity - $volphysicalcapacitynew)
            $volcount=$volcount+1
            add-content $logfile ''
            add-content $logfile ('The new data reduction for this volume after UNMAP is ' + $volreduction + " to 1")
            add-content $logfile ('The new physical space consumption in GB of this device after UNMAP is ' + $volphysicalcapacitynew)
            add-content $logfile ("$unmapsavings" + ' in GB has been reclaimed from the FlashArray from this volume')
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            Start-Sleep -s 5
        }
        else
        {
            add-content $logfile 'This datastore is NOT a Pure Storage Volume. Skipping...'
            add-content $logfile $lun
            add-content $logfile '----------------------------------------------------------------------------------------------------'
        }
    }
}
#disconnecting sessions
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}