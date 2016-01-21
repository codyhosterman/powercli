
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
$vmfsname = Read-Host "Enter VMFS Name"
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
    write-host ("The FlashArray volume named " + $purevol.name)
}
else
{
    write-host 'This datastore is NOT a Pure Storage Volume.'
}
#disconnecting sessions
disconnect-viserver -Server $vcenter -confirm:$false
foreach ($flasharray in $endpoint)
{
    Disconnect-PfaArray -Array $flasharray
}






