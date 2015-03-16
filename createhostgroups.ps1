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
Write-host "Pure Storage VMware Setup Script"
write-host "----------------------------------------------"
write-host

#Enter the following parameters. Put all entries inside the quotes:
#**********************************
#vCenter IP and username/password:
$vcenter = ""
$vcuser = ""
$vcpass = ""
#FlashArray IP and username/password
$flasharray = ""
$fauser = ""
$fapass = ""
#Target VMware Cluster Name
$cluster = ""
#Desired Storage Protocol. Valid entries are FC for Fibre Channel or iscsi for iSCSI
$protocol = ""
#**********************************

#Connect to vCenter server
connect-viserver -Server $vcenter -user $vcuser -password $vcpass

#Import Pure Storage PowerShell Toolkit (must be installed on local machine)
Import-Module PureStoragePowerShell

#Connect to FlashArray
$FAToken = Get-PfaApiToken -FlashArray $flasharray -Username $fauser -Password $fapass
$FASession = Connect-PfaController -FlashArray $flasharray -API_Token $FAToken.api_token

#Instantiate Cluster and Host variables
$esxicluster = get-cluster $cluster
$esxhosts = $esxicluster | Get-VMHost

#-----------------------------------------------------------------------------------------------------------------------------------------------------------
#Configure the VMware cluster as a new host group on the FlashArray. Using the cluster name as the host group name.
#-----------------------------------------------------------------------------------------------------------------------------------------------------------

#FlashArray only supports Alphanumeric or the dash - character in host group names. Checking for VMware cluster name compliance and removing invalid characters.
if ($cluster -match "^[a-zA-Z0-9\-]+$")
{
    $clustername = $cluster
}
else
{
    $clustername = $cluster -replace "[^\w\-]", ""
    $clustername = $clustername -replace "[_]", ""
    
}

#FlashArray host group names must have at least one letter. Checking VMware Cluster name for compliance and prefixing ESXiCluster if no letters exist for the respective new host group on the array.
if ($clustername -match "[a-zA-Z]")
{
}
else
{
    $clustername = "ESXiCluster" + $clustername
}

#FlashArray Host Group names must have no more than 63 characters. Checking VMware Cluster name length for compliance and cutting the name short if invalid for the new respective host group on the array.
#Also rechecking to make sure a truncation does not invalidate the "at least one letter" requirement
if ($clustername.length -ge 64 )
{
    $clustername = $clustername.substring(0,63)
    if ($clustername -match "[a-zA-Z]")
    {
    }
    else
    {
        $clustername = "ESXiCluster" + $clustername
    }
}

#Checking if the host group name already exists on the FlashArray, if the name exists a random number between 1000 and 9999 will be appended.
$hgroupnamecheck = Get-PFAHostGroups -FlashArray $flasharray -Session $FASession -Name $clustername -ErrorAction SilentlyContinue
while ($hgroupnamecheck -ne $null)
{
    $randomsuffix = Get-Random -Minimum 1000 -Maximum 9999
    $clustername = $clustername + "$randomsuffix"
    $hgroupnamecheck = Get-PFAHostGroups -FlashArray $flasharray -Session $FASession -Name $clustername -ErrorAction SilentlyContinue
}
#Creating the host group
New-PfaHostGroup -FlashArray $flasharray -Name $clustername -Session $FASession

#-----------------------------------------------------------------------------------------------------------------------------------------------------------
#Configure the ESXi hosts. This process does the following:
# 1) Checks ESXi host name and conforms it to FlashArray host naming rules
# 2) Gets the WWNs (for FC) or IQNs (for iSCSI) of each host
# 3) Creates the host on the FlashArray and adds the initiators
# 4) Creates a SATP rule so all FlashArray devices are from this point on set to Round Robin and have an IO Operations Limit of 1
# 5) Only for iSCSI: Get an iSCSI target and add it to each software iSCSI initiators on the ESXi hosts. The initiators need to be created first. Also sets iSCSI best practices
#-----------------------------------------------------------------------------------------------------------------------------------------------------------
foreach ($esx in $esxhosts)
{
    #Check the ESXi names. Only alphanumberic and dashes. Replacing invalid characters with a dash. Must have at least one letter and no more than 63 characters.
    $esxcli=get-esxcli -VMHost $esx
    if ($esx.Name -match "^[a-zA-Z0-9\-]+$")
    {
            $flashhost = $esx.Name
    }
    else
    {
        $flashhost = $esx.Name -replace "\.", "-"
        $flashhost = $flashhost -replace "_", "-"
    }
    if ($flashhost -match "[a-zA-Z]")
    {
    }
    else
    {
        $flashhost = "ESXiHost" + $flashhost 
    }
if ($flashhost.length -ge 64 )
{
    $flashhost = $flashhost.substring(0,63)
    if ($flashhost -match "[a-zA-Z]")
    {
    }
    else
    {
        $flashhost = "ESXiHost" + $flashhost
    }
}
#gather the WWNs if Fibre Channel is used
if ($protocol -eq "fc")
{
    $wwns = $esx | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
    $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
    $wwns = (&{for ($i = 0;$i -lt $wwns.length;$i += 16)
    {
         $wwns.substring($i,16)
    }}) -join ","
    $createhost = "New-PfaHost -FlashArray `$flasharray -Name `$flashhost -WWNList $wwns -Session `$FASession" 
    Invoke-Expression $createhost -ErrorAction Stop
}
#gather the IQNs if iSCSI is used
if ($protocol -eq "iscsi")
{
    $iscsi = $esx | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
    New-PfaHost -FlashArray $flasharray -Name $flashhost -IQNList $iscsi.iscsiname -Session $FASession
    $targets = Get-PfaInitiators -FlashArray $flasharray -Session $FASession
    $target = $null
    $count = 1
    while ($target -eq $null)
    {
        $target = $targets[$count].target_portal
        $count++
    }
    #Adds the FlashArray ports to the software iSCSI adapter and configures best practices.
    New-IScsiHbaTarget -IScsiHba $iscsi -Address $target
    Start-Sleep -Seconds 2
    $esxcli.iscsi.adapter.discovery.sendtarget.param.set($iscsi.device, $target, $false, $false, "DelayedAck", "false")
    $esxcli.iscsi.adapter.discovery.sendtarget.param.set($iscsi.device, $target, $false, $false, "LoginTimeout", "30")
    $esx | Get-VMHostStorage -RescanAllHba
}
else
{
    write-host "Please enter a protocol choice."
}
#Sets FlashArray best practices on the ESXi host
$esx | Get-AdvancedSetting -Name DataMover.MaxHWTransferSize | Set-AdvancedSetting -Value 16384 -Confirm:$false
$esxcli.storage.nmp.satp.rule.add($null, $null, "PURE FlashArray IO Operation Limit Rule", $null, $null, $null, "FlashArray", $null, "VMW_PSP_RR", $iops, "VMW_SATP_ALUA", $null, $null, "PURE")
if ($hostlist -eq $null)
{
    $hostlist = [array] $flashhost
}
else
{
        $hostlist += $flashhost
}
}
#Adds the hosts to the host group.
Update-PfaHostGroupHosts -FlashArray $flasharray -Name $clustername -HostList $hostlist -Session $FASession