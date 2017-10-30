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
Write-host "Pure Storage SRM VVol Creator 1.0"
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

This script takes in a given VMFS and finds all VMs that have VVol-based virtual disks. It also takes in a target VVol datastore.
The script then creates the requisite number of VVols for each VM with the correct sizes on that target VVol datastore.

Requires:
-VMware PowerCLI 6.5+
-Microsoft PowerShell 4+ is highly recommended
-FlashArray Purity 5.0+
-vCenter 6.5+
#>
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "This script has not been run as an administrator."
    Write-Warning "Please re-run this script as an administrator!"
    write-host "Terminating Script" -BackgroundColor Red
    return
}
if ((!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable))) {
    if (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
      . “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    elseif (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
        . “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
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

function disconnectServers{
    disconnect-viserver -Server * -confirm:$false
    Remove-PSDrive -name VVol
}

#connect to source vCenter
$sourcevcenter = read-host "Please enter a source vCenter IP or FQDN"
$Creds = $Host.ui.PromptForCredential("vCenter Credentials", "Please enter your vCenter username and password.", "$env:userdomain\$env:username","")
try
{
    connect-viserver -Server $sourcevcenter -Credential $Creds -ErrorAction Stop |out-null
}
catch
{
    write-host "Failed to connect to vCenter. Refer to log for details." -BackgroundColor Red
    write-host "Terminating Script" -BackgroundColor Red
    return
}

#connect to target vCenter
$targetvcenter = read-host "Please enter a recovery site vCenter IP or FQDN"
$options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No", "&Quit")
[int]$defaultchoice = 1
$opt = $host.UI.PromptForChoice("vCenter Credentials" , "Use the same credentials as source vCenter?" , $Options,$defaultchoice)
if ($opt -eq 2)
{
    return
}
elseif ($opt -eq 1)
{
    $Creds = $Host.ui.PromptForCredential("vCenter Credentials", "Please enter your vCenter username and password.", "$env:userdomain\$env:username","")
}
try
{
    connect-viserver -Server $targetvcenter -Credential $Creds -ErrorAction Stop |out-null
}
catch
{
    write-host "Failed to connect to vCenter. Refer to log for details." -BackgroundColor Red
    write-host "Terminating Script" -BackgroundColor Red
    return
}

$datastore = Read-Host "Please enter a replicated VMFS datastore name"
$datacenter = Read-Host "Please enter a recovery datacenter name"
$vvolDatastore = Read-Host "Please enter a recovery VVol datastore name"#>
$dc = Get-Datacenter $datacenter -Server $targetvcenter
try
{
    $vvolDatastore = Get-Datastore $vvolDatastore -Server $targetvcenter
    $vms = Get-Datastore $datastore -Server $sourcevcenter|get-vm
    $vmfsUUID = get-datastore $datastore -Server $sourcevcenter|% {$_.ExtensionData.Info.Vmfs.Extent.DiskName} |% {$_.substring(11,17)}
}
catch
{
    write-host $Error[0]
    write-host "Exiting..."
    disconnectServers
    return
}
write-host "****************************"
write-host "Identifying all VMs on the datastore $($datastore) and their virtual disks that are VVols"
write-host ""

#checking for VMs on the VMFS that have VVols and ensuring they are on the same array as the VMFS. Will fail if it finds any elsewhere.
$vvolVMs = @()
foreach ($vm in $vms)
{
    $vmdevices = $vm.ExtensionData.Config.Hardware.Device 
    $foundVVols = 0
    foreach ($vmdevice in $vmdevices)
    {
        if ($vmdevice.gettype().Name -eq "VirtualDisk")
        {
            if ($vmdevice.Backing.gettype().Name -eq "VirtualDiskFlatVer2BackingInfo")
            {
                $tempds = $vmdevice.Backing.Datastore 
                $tempds = Get-Datastore -id $tempds -Server $sourcevcenter
                if ($tempds.type -eq "VVOL")
                {
                    #parses VMFS serial number an compares it to VVol datastore UUID to see if they are the same array
                    $vvolUUID = $tempds.ExtensionData.Info.vvolDS.StorageArray.uuid |% {$_.replace("-","")} |% {$_.substring(16,17)}
                    if ($vmfsUUID -ne $vvolUUID)
                    {
                        write-host "ERROR: The VM $($vm.name) has VVols on a different array that hosts the source datastore $($datastore)" -BackgroundColor Red
                        write-host "Found a VVol on FlashArray $($vmdevice.Backing.datastore.ExtensionData.Info.vvolDS.StorageArray.name)." -BackgroundColor Red
                        write-host "Exiting script..."
                        disconnectServers
                        return
                    }
                    $foundVVols++
                }
            }
        } 
    }
    if ($foundVVols -gt 0)
    {
        write-host "Found $($foundVVols) VVols on VM $($VM.name)"
        $vvolVMs += $vm

    }
    else {write-host "Found ZERO VVols on VM $($VM.name)"}
}
#actually creating the VMDKs for each respective VVol for each VM on the entered datastore. Non-VVol VMDKs (VMFS, NFS, RDMs, will be skipped.
#if the VVol already exists it will be skipped

write-host ""
write-host "****************************"
write-host "Creating VVol Virtual Disks on $($vvolDatastore.Name)..."
write-host ""
New-PSDrive -Name VVol -Location $vvolDatastore -PSProvider VimDatastore -Root '\' |out-null
$SCfiles = get-childitem -path VVol: -recurse 
$vvolVMDKs = $SCfiles| where-object {$_.Name -like "*.vmdk"}
$vvolFolders = $SCfiles| where-object {$_.ItemType -eq "Folder" -and $_.Name -ne ".sdd.sf"}
$virtualDiskManager = Get-View (Get-View ServiceInstance -Server $targetvcenter).Content.virtualDiskManager -Server $targetvcenter

foreach ($vm in $vvolVMs)
{
    write-host ""
    write-host "Configuring remote VVols for VM $($vm.name)..." -ForegroundColor Green
    $vmdevices = $vm.ExtensionData.Config.Hardware.Device 
    $foundVVol = $false
    $foundFolder = $false
    foreach ($vmdevice in $vmdevices)
    {
        if ($vmdevice.gettype().Name -eq "VirtualDisk")
        {
            if ($vmdevice.Backing.gettype().Name -eq "VirtualDiskFlatVer2BackingInfo")
            {
                $tempds = $vmdevice.Backing.Datastore 
                $tempds = Get-Datastore -id $tempds -Server $sourcevcenter
                if ($tempds.type -eq "VVOL")
                {
                    #look to see if VM folder is there
                    if (($vvolFolders -ne $null) -and ($foundFolder -eq $false))
                    {
                        $foundFolder = $vvolFolders.name.contains($vm.Name)
                    }
                    if ($foundFolder -eq $false)
                    {
                        write-host "Creating datastore directory for $($VM.name)..." 
                        New-Item -Path VVol:/ -Name $vm.Name -ItemType directory -Confirm:$false -Force:$true |out-null
                        $foundFolder = $true
                        start-sleep 2
                    }
                    #create VMDK pointer file name
                    $fileCount = $vmdevice.Backing.fileName |% {$_.indexof("/")}
                    $fileName = $vmdevice.Backing.fileName |% {$_.substring($fileCount + 1)}       
                    $FilePath ="[$($vvolDatastore.name)] $($vm.name)/$($fileName)"
                    #check if VVol already exists on target VVol datastore
                    if ($vvolVMDKs -ne $null)
                    {
                        $foundVVol = $vvolVMDKs.name.contains($fileName)
                    }
                    if ($foundVVol)
                    {
                        write-host "NOTICE: The VVol $($fileName) has already been created. Skipping..." 
                        continue
                    }
                    else
                    {
                        #create disk configuration
                        $vHddSpec = new-Object VMWare.Vim.FileBackedVirtualDiskSpec
                        $vHddSpec.CapacityKB = $vmdevice.CapacityInKB
                        $vHddSpec.DiskType = "thin"     
                        $vHddSpec.AdapterType = "lsiLogic"
                        write-host $FilePath
                        #create VVol VMDK
                        $virtualDiskManager.CreateVirtualDisk($FilePath, $dc.ExtensionData.moref, $vHddSpec) |out-null

                    }
                }
            }
        } 
    }
}
disconnectServers