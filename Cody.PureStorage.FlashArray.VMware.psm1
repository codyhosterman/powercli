function get-faVolumeNameFromVvolUuid{
    <#
    .SYNOPSIS
      Connects to vCenter and FlashArray to return the FA volume that is a VVol virtual disk.
    .DESCRIPTION
      Takes in a VVol UUID to identify what volume it is on the FlashArray. If a VVol UUID is not specified it will ask you for a VM and then a VMDK and will find the UUID for you.
    .INPUTS
      FA REST session, FA FQDN/IP and VVol UUID.
    .OUTPUTS
      Returns volume name.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/06/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    #Import PowerCLI. Requires PowerCLI version 6.3 or later. Will fail here if PowerCLI cannot be installed
    #Will try to install PowerCLI with PowerShellGet if PowerCLI is not present.

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true)]
            [string]$purevip,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [Microsoft.PowerShell.Commands.WebRequestSession]$faSession,

            [Parameter(Position=2)]
            [string]$vvolUUID
    )
if (($vvolUUID -eq $null) -or ($vvolUUID -eq ""))
{
    #Choose VM
    Write-Host
    if ($null -eq $global:defaultviserver)
    {
        Write-Error -Message "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
        return $null
    }
    $vmExists = $true
    do
    { 
        try {
            $vmName = Read-Host "Please enter in the name of your VM" 
            $vm = get-vm -name $vmName -ErrorAction Stop 
            $vmExists = $true
        }
        catch {
            Write-Warning -Message $Global:Error[0]
            Write-Host
            $vmExists = $false
        }
    } while ($vmExists -eq $false)

    #Get disks
    try {
        $disks = $vm |Get-HardDisk -ErrorAction Stop
    }
    catch {
        Write-Warning -Message $Global:Error[0]
    }

    #Find disks that are VVols
    try {
        $vvolDisks = @()
        foreach ($disk in $disks)
        {
            $datastore = $disk |Get-datastore 
            if ($datastore.type -eq "VVOL")
            {
                $vvolDisks += $disk
            }
    
        }
        if ($vvolDisks.count -eq 0)
        {
            throw "No VVol disks found on this VM."
        }
    }
    catch {
        Write-Error -Message $Global:Error[0]
        return $null
    }

    #List and Choose disk
    Write-Host
    $chooseDisk = $true
    do {
        try {
            Write-Host
            Write-Host "Found the following disk(s):" 
            $Global:seq = 1; $vvolDisks | Format-Table -Property @{Label = '#'; Expression = {$Global:seq; $Global:seq++;}; Alignment = "center"}, Name,Filename,CapacityGB -AutoSize
            $diskChoice = Read-Host "Please type your disk choice number [1-$($vvolDisks.count)]"
            $validOptions = 1..$vvolDisks.count
            if ($validOptions -contains $diskChoice)
            {
                $chosenDisk = $vvolDisks[$diskChoice-1]
                $vvolUUID = $chosenDisk.ExtensionData.backing.backingObjectId
                $chooseDisk = $true
            }
            else {
                throw "Invalid choice."
            }
        }
        catch {
            Write-Warning -Message $Global:Error[0]
            Write-Host
            $chooseDisk = $false
        }
    } while ($chooseDisk -eq $false)

    Write-Host
    Write-Host "The VVol UUID is $($vvolUUID)"
    }

   #Pull tags that match the volume with that UUID
    try {
        $volumeTags = Invoke-RestMethod -Method Get -Uri "https://${purevip}/api/1.14/volume?tags=true&filter=value='${vvolUUID}'" -WebSession $faSession -ErrorAction Stop
        $volumeName = $volumeTags |where-object {$_.key -eq "PURE_VVOL_ID"}
    }
    catch {
        Write-Error -message $Error[0] 
        return $null
    }
    try {
        if ($null -ne $volumeName)
        {
            write-host
            return $volumeName.name
        }
        else {
            Write-Error "The VVol was not found on this FlashArray" 
            return $null
        }
    }
    catch {
            Write-Error -Message $Global:Error[0]
            return $null
        }
}

function new-pureflasharrayRestSession {

     <#
    .SYNOPSIS
      Connects to FlashArray and creates a REST connection.
    .DESCRIPTION
      For operations that are in the FlashArray REST, but not in the Pure Storage PowerShell SDK yet, this provides a connection for invoke-restmethod to use.
    .INPUTS
      FlashArray IP/FQDN and credentials
    .OUTPUTS
      Returns REST session
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/06/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            
        [Parameter(Position=0)]
        [string]$purevip,
        
        [Parameter(Position=1,ValueFromPipeline=$True)]
        [System.Management.Automation.PSCredential]$faCreds
    )

    #Connect to FlashArray
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    #Get FA API token
    $faConnected = $true
    do {
        try {
                if (($null -eq $purevip) -or ($purevip -eq "") -or ($faConnected -eq $false))
                {
                    Write-Host
                    $purevip = read-host "Please enter the mgmt IP or FQDN of your FlashArray"
                }                
                if (($null -eq $faCreds) -or ($faConnected -eq $false))
                {
                    Write-Host
                    $faCreds = Get-Credential -Message "Please enter your FlashArray credentials"
                    $tempPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($faCreds.Password)
                    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($tempPass)
                    $AuthAction = @{
                        password = ${UnsecurePassword}
                        username = ${faCreds}.UserName
                    }
                }
                else
                {
                    $tempPass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($faCreds.Password)
                    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($tempPass)
                    $AuthAction = @{
                        password = ${UnsecurePassword}
                        username = ${faCreds}.UserName
                    }
                }
                $ApiToken = Invoke-RestMethod -Method Post -Uri "https://${purevip}/api/1.14/auth/apitoken" -Body $AuthAction -ErrorAction Stop
                $faConnected = $true
        }
        catch {
                write-Warning -message $Error[0] 
                $faConnected = $false
        }
    } while ($faConnected -eq $false)

    #Create FA session
    try {
        $SessionAction = @{
            api_token = $ApiToken.api_token
        }
        Invoke-RestMethod -Method Post -Uri "https://${purevip}/api/1.14/auth/session" -Body $SessionAction -SessionVariable Session -ErrorAction Stop |Out-Null
        return $Session
    }
    catch {
           Write-Error -Message $Error[0]
           return $null  
    }
}

function remove-pureflasharrayRestSession {
    <#
    .SYNOPSIS
      Disconnects a FlashArray REST session
    .DESCRIPTION
      Takes in a FlashArray PowerShell REST session and disconnects on the FlashArray.
    .INPUTS
      FA REST session, FA FQDN/IP.
    .OUTPUTS
      Returns success or failure.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/06/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true)]
            [string]$purevip,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [Microsoft.PowerShell.Commands.WebRequestSession]$faSession
    )

     #Delete FA session
     try {
        Invoke-RestMethod -Method Delete -Uri "https://${purevip}/api/1.14/auth/session"  -WebSession $faSession -ErrorAction Stop |Out-Null
        Write-Host "FlashArray session disconnected."
        return $true
    }
    catch {
           Write-Error -Message $Error[0] 
           return $false 
    }
}

function get-vmdkFromWindowsDisk {
    <#
    .SYNOPSIS
      Returns the VM disk object that corresponds to a given Windows file system
    .DESCRIPTION
      Takes in a drive letter and a VM object and returns a matching VMDK object
    .INPUTS
      VM, Drive Letter
    .OUTPUTS
      Returns VMDK object 
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/24/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$false,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

            [Parameter(Position=1,mandatory=$false)]
            [string]$driveLetter
    )
    if ($null -eq $global:defaultviserver)
    {
       throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
    }
    if ($null -eq $vm)
    {
        try {
            $vmName = Read-Host "Please enter in the name of your VM" 
            $vm = get-vm -name $vmName -ErrorAction Stop 
        }
        catch {
            throw $Global:Error[0]
        }
    }
    try {
        $guest = $vm |Get-VMGuest
    }
    catch {
        throw $Error[0]
    }
    if ($guest.State -ne "running")
    {
        throw "This VM does not have VM tools running"
    }
    if ($guest.GuestFamily -ne "windowsGuest")
    {
        throw "This is not a Windows VM--it is $($guest.OSFullName)"
    }
    try {
        $advSetting = Get-AdvancedSetting -Entity $vm -Name Disk.EnableUUID -ErrorAction Stop
    }
    catch {
        throw $Error[0]
    }
    if ($advSetting.value -eq "FALSE")
    {
        throw "The VM $($vm.name) has the advanced setting Disk.EnableUUID set to FALSE. This must be set to TRUE for this cmdlet to work."    
    }
    if (($null -eq $driveLetter) -or ($driveLetter -eq ""))
    {
        try {
            $driveLetter = Read-Host "Please enter in a drive letter" 
            if (($null -eq $driveLetter) -or ($driveLetter -eq ""))
            {
                throw "No drive letter entered"
            }
        }
        catch {
            throw $Global:Error[0]
        }
    }
    try {
        $VMdiskSerialNumber = $vm |Invoke-VMScript -ScriptText "get-partition -driveletter $($driveLetter) | get-disk | ConvertTo-CSV -NoTypeInformation"  -WarningAction silentlyContinue -ErrorAction Stop |ConvertFrom-Csv
    }
    catch {
            throw $Error[0]
        }
    if (![bool]($VMDiskSerialNumber.PSobject.Properties.name -match "serialnumber"))
    {
        throw ($VMdiskSerialNumber |Out-String) 
    }
    try {
        $vmDisk = $vm | Get-HardDisk |Where-Object {$_.ExtensionData.backing.uuid.replace("-","") -eq $VMdiskSerialNumber.SerialNumber}
    }
    catch {
        throw $Global:Error[0]
    }
    if ($null -ne $vmDisk)
    {
        return $vmDisk
    }
    else {
        throw "Could not match the VM disk to a VMware virtual disk"
    }
}

function new-faHostFromVmHost {
    <#
    .SYNOPSIS
      Create a FlashArray host from an ESXi vmhost object
    .DESCRIPTION
      Takes in a vCenter ESXi host and creates a FlashArray host
    .INPUTS
      FlashArray connection, a vCenter ESXi vmHost, and iSCSI/FC option
    .OUTPUTS
      Returns new FlashArray host object.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/09/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi,

            [Parameter(Position=1,mandatory=$true)]
            [string]$protocolType,

            [Parameter(Position=2,mandatory=$true,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray
    )
    if (($protocolType -ne "FC") -and ($protocolType -ne "iSCSI"))
    {
        throw 'No valid protocol entered. Please make sure $protocolType is set to either "FC" or "iSCSI"'
    }
    if ($null -eq $global:defaultviserver)
    {
       throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
    }
    if ($protocolType -eq "iSCSI")
    {
        $iscsiadapter = $esxi | Get-VMHostHBA -Type iscsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
        if ($null -eq $iscsiadapter)
        {
            throw "No Software iSCSI adapter found on host $($esxi.NetworkInfo.HostName)."
        }
        else
        {
            $iqn = $iscsiadapter.ExtensionData.IScsiName
        }
        try
        {
            $newFaHost = New-PfaHost -Array $flasharray -Name $esxi.NetworkInfo.HostName -IqnList $iqn -ErrorAction stop
            return $newFaHost
        }
        catch
        {
            Write-Error $Global:Error[0]
            return 
        }
    }
    if ($protocolType -eq "FC")
    {
        $wwns = $esxi | Get-VMHostHBA -Type FibreChannel | Select-Object VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
        {
                $wwns.substring($i,16)
        }}
        try
        {
            $newFaHost = New-PfaHost -Array $flasharray -Name $esxi.NetworkInfo.HostName -WwnList $wwns -ErrorAction stop
            return $newFaHost
        }
        catch
        {
            Write-Error $Global:Error[0]
            return 
        }
    }
}

function get-faHostFromVmHost {
    <#
    .SYNOPSIS
      Gets a FlashArray host object from a ESXi vmhost object
    .DESCRIPTION
      Takes in a vmhost and returns a matching FA host if found
    .INPUTS
      FlashArray connection and a vCenter ESXi host
    .OUTPUTS
      Returns FA host if matching one is found.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/09/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi,

        [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    if ($null -eq $global:defaultviserver)
    {
       throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
    }
    $iscsiadapter = $esxi | Get-VMHostHBA -Type iscsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
    $wwns = $esxi | Get-VMHostHBA -Type FibreChannel | Select-Object VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
        {
                $wwns.substring($i,16)
        }}
    $fahosts = Get-PFAHosts -array $flasharray -ErrorAction Stop
    if ($null -ne $iscsiadapter)
    {
        $iqn = $iscsiadapter.ExtensionData.IScsiName
        foreach ($fahost in $fahosts)
        {
            if ($fahost.iqn.count -ge 1)
            {
                foreach ($fahostiqn in $fahost.iqn)
                {
                    if ($iqn.ToLower() -eq $fahostiqn.ToLower())
                    {
                        return $fahost
                    }
                }
            }
        }   
    }
    if ($null -ne $wwns)
    {
        foreach ($wwn in $wwns)
        {
            foreach ($fahost in $fahosts)
            {
                if ($fahost.wwn.count -ge 1)
                {
                    foreach($fahostwwn in $fahost.wwn)
                    {
                        if ($wwn.ToLower() -eq $fahostwwn.ToLower())
                        {
                            return $fahost
                        }
                    }
                }
            }
        }
    }
    else {
        throw "No matching host could be found on the FlashArray"
    }
}

function get-faHostGroupfromVcCluster {
    <#
    .SYNOPSIS
      Retrieves a FA host group from an ESXi cluster
    .DESCRIPTION
      Takes in a vCenter Cluster and retrieves corresonding host group
    .INPUTS
      FlashArray connection and a vCenter cluster
    .OUTPUTS
      Returns success or failure.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/09/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

        [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    if ($null -eq $global:defaultviserver)
    {
       throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
    }
    $esxiHosts = $cluster |Get-VMHost
    $faHostGroups = @()
    $faHostGroupNames = @()
    foreach ($esxiHost in $esxiHosts)
    {
        try {
            $faHost = $esxiHost | get-faHostFromVmHost -flasharray $flasharray
            if ($null -ne $faHost.hgroup)
            {
                if ($faHostGroupNames.contains($faHost.hgroup))
                {
                    continue
                }
                else {
                     $faHostGroupNames += $faHost.hgroup
                     $faHostGroup = Get-PfaHostGroup -Array $flasharray -Name $faHost.hgroup
                     $faHostGroups += $faHostGroup
                }
            }
        }
        catch{
            continue
        }
    }
    if ($null -eq $faHostGroup)
    {
        throw "No host group found for this cluster"
    }
    if ($faHostGroups.count -gt 1)
    {
        Write-Warning -Message "This cluster spans more than one host group. The recommendation is to have only one host group per cluster"
    }
    return $faHostGroups
}

function new-faHostGroupfromVcCluster {
    <#
    .SYNOPSIS
      Create a host group from an ESXi cluster
    .DESCRIPTION
      Takes in a vCenter Cluster and creates hosts (if needed) and host group
    .INPUTS
      FlashArray connection, a vCenter cluster, and iSCSI/FC option
    .OUTPUTS
      Returns success or failure.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/06/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,
        
        [Parameter(Position=1,mandatory=$true)]
        [string]$protocolType,

        [Parameter(Position=2,mandatory=$true,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    if ($null -eq $global:defaultviserver)
    {
       throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
    }
    if (($protocolType -ne "FC") -and ($protocolType -ne "iSCSI"))
    {
        throw 'No valid protocol entered. Please make sure $protocolType is set to either "FC" or "iSCSI"'
    }

    $hostGroup = $cluster |get-faHostGroupfromVcCluster -flasharray $flasharray -ErrorAction SilentlyContinue
    if ($hostGroup.count -gt 1)
    {
        throw "The cluster already is configured on the FlashArray and spans more than one host group. This cmdlet does not support a multi-hostgroup configuration."
    }
    if ($hostGroup.count -eq 1)
    {
        $clustername = $hostGroup.name
    }
    $esxiHosts = $cluster |Get-VMHost
    $faHosts = @()
    foreach ($esxiHost in $esxiHosts)
    {
        $faHost = $null
        try {
            $faHost = $esxiHost |get-faHostFromVmHost -flasharray $flasharray
        }
        catch {}
        if ($null -eq $faHost)
        {
            try {
                $faHost = $esxiHost |new-faHostFromVmHost -flasharray $flasharray -protocolType $protocolType -ErrorAction Stop
                $faHosts += $faHost
            }
            catch {
                Write-Error $Global:Error[0]
                throw "Could not create host. Cannot create host group." 
            }
            
        }
        else {
            $faHosts += $faHost
        }
    }
    #FlashArray only supports Alphanumeric or the dash - character in host group names. Checking for VMware cluster name compliance and removing invalid characters.
    if ($null -eq $hostGroup)
    {
        if ($cluster.Name -match "^[a-zA-Z0-9\-]+$")
        {
            $clustername = $cluster.Name
        }
        else
        {
            $clustername = $cluster.Name -replace "[^\w\-]", ""
            $clustername = $clustername -replace "[_]", ""
            $clustername = $clustername -replace " ", ""
        }
        $hg = Get-PfaHostGroup -Array $flasharray -Name $clustername -ErrorAction SilentlyContinue
        if ($null -ne $hg)
        {
            if ($hg.hosts.count -ne 0)
            {
                #if host group name is already in use and has only unexpected hosts i will create a new one with a random number at the end
                $nameRandom = get-random -Minimum 1000 -Maximum 9999
                $hostGroup = New-PfaHostGroup -Array $flasharray -Name "$($clustername)-$($nameRandom)" -ErrorAction stop
                $clustername = "$($clustername)-$($nameRandom)"
            }
        }
        else {
            #if there is no host group, it will be created
            $hostGroup = New-PfaHostGroup -Array $flasharray -Name $clustername -ErrorAction stop
        }
    }
    $faHostNames = @()
    foreach ($faHost in $faHosts)
    {
        if ($null -eq $faHost.hgroup)
        {
            $faHostNames += $faHost.name
        }
    }
    #any hosts that are not already in the host group will be added
    Add-PfaHosts -Array $flasharray -Name $clustername -HostsToAdd $faHostNames -ErrorAction Stop |Out-Null
    $fahostGroup = Get-PfaHostGroup -Array $flasharray -Name $clustername
    return $fahostGroup
}

function set-vmHostPureFaiSCSI{
    <#
    .SYNOPSIS
      Configure FlashArray iSCSI target information on ESXi host
    .DESCRIPTION
      Takes in an ESXi hosts and configures FlashArray iSCSI target info
    .INPUTS
      FlashArray connection and an ESXi host
    .OUTPUTS
      Returns ESXi iSCSI targets.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/09/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi,

        [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    if ($esxi.ExtensionData.Runtime.ConnectionState -ne "connected")
    {
        Write-Warning "Host $($esxi.NetworkInfo.HostName) is not in a connected state and cannot be configured."
        return
    }
    $ESXitargets = @()
    $faiSCSItargets = Get-PfaNetworkInterfaces -Array $flasharray |Where-Object {$_.services -eq "iscsi"}
    if ($null -eq $faiSCSItargets)
    {
        throw "The target FlashArray does not currently have any iSCSI targets configured."
    }
    $iscsi = $esxi |Get-VMHostStorage
    if ($iscsi.SoftwareIScsiEnabled -ne $true)
    {
        $esxi | get-vmhoststorage |Set-VMHostStorage -SoftwareIScsiEnabled $True |out-null
    }
    foreach ($faiSCSItarget in $faiSCSItargets)
    {
        $iscsiadapter = $esxi | Get-VMHostHba -Type iScsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
        if (!(Get-IScsiHbaTarget -IScsiHba $iscsiadapter -Type Send -ErrorAction stop | Where-Object {$_.Address -cmatch $faiSCSItarget.address}))
        {
            New-IScsiHbaTarget -IScsiHba $iscsiadapter -Address $faiSCSItarget.address -ErrorAction stop 
        }
        $esxcli = $esxi |Get-esxcli -v2 
        $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.CreateArgs()
        $iscsiargs.adapter = $iscsiadapter.Device
        $iscsiargs.address = $faiSCSItarget.address
        $delayedAck = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "DelayedAck"}
        $loginTimeout = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "LoginTimeout"}
        if ($delayedAck.Current -eq "true")
        {
            $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
            $iscsiargs.adapter = $iscsiadapter.Device
            $iscsiargs.address = $faiSCSItarget.address
            $iscsiargs.value = "false"
            $iscsiargs.key = "DelayedAck"
            $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
        }
        if ($loginTimeout.Current -ne "30")
        {
            $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
            $iscsiargs.adapter = $iscsiadapter.Device
            $iscsiargs.address = $faiSCSItarget.address
            $iscsiargs.value = "30"
            $iscsiargs.key = "LoginTimeout"
            $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
        }
        $ESXitargets += Get-IScsiHbaTarget -IScsiHba $iscsiadapter -Type Send -ErrorAction stop | Where-Object {$_.Address -cmatch $faiSCSItarget.address}
    }
    return $ESXitargets
}

function set-clusterPureFAiSCSI {
    <#
    .SYNOPSIS
      Configure an ESXi cluster with FlashArray iSCSI information
    .DESCRIPTION
      Takes in a vCenter Cluster and configures iSCSI on each host.
    .INPUTS
      FlashArray connection and a vCenter cluster.
    .OUTPUTS
      Returns iSCSI targets.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/09/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

        [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    $esxihosts = $cluster |Get-VMHost
    $esxiiSCSItargets = @()
    $hostCount = 0
    foreach ($esxihost in $esxihosts)
    {
        if ($hostCount -eq 0)
        {
             Write-Progress -Activity "Configuring iSCSI" -status "Host: $esxihost" -percentComplete 0
        }
        else {
            Write-Progress -Activity "Configuring iSCSI" -status "Host: $esxihost" -percentComplete (($hostCount / $esxihosts.count) *100)
        }
        $esxiiSCSItargets += $esxihost | set-vmHostPureFaiSCSI -flasharray $flasharray
        $hostCount++
    }
    return $esxiiSCSItargets
}

function get-faVolfromVMFS {
    <#
    .SYNOPSIS
      Retrieves the FlashArray volume that hosts a VMFS datastore.
    .DESCRIPTION
      Takes in a VMFS datastore and one or more FlashArrays and returns the volume if found.
    .INPUTS
      FlashArray connection(s) and a VMFS datastore.
    .OUTPUTS
      Returns FlashArray volume or null if not found.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/10/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray
    )
    if ($datastore.Type -ne 'VMFS')
    {
        throw "This is not a VMFS datastore."
    }
    $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
    if ($lun -like 'naa.624a9370*')
    {
        $pureVolumes = Get-PfaVolumes -Array  $flasharray
        $volserial = ($lun.ToUpper()).substring(12)
        $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
        if ($null -ne $purevol.name)
        {
            return $purevol
        }
        else {
            return $null
        }
    }
    else {
        throw "This VMFS is not hosted on FlashArray storage."
    }
    
}

function new-faVolVmfs {
    <#
    .SYNOPSIS
      Create a new VMFS on a new FlashArray volume 
    .DESCRIPTION
      Creates a new FlashArray-based VMFS and presents it to a cluster.
    .INPUTS
      FlashArray connection, a vCenter cluster, a volume size, and name.
    .OUTPUTS
      Returns a VMFS object.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/10/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray,

            [Parameter(Position=2,mandatory=$true)]
            [string]$volName,

            [Parameter(Position=3)]
            [int]$sizeInGB,

            [Parameter(Position=4)]
            [int]$sizeInTB
    )
    if (($sizeInGB -eq 0) -and ($sizeInTB -eq 0))
    {
        throw "Please enter a size in GB or TB"
    }
    elseif (($sizeInGB -ne 0) -and ($sizeInTB -ne 0)) {
        throw "Please only enter a size in TB or GB, not both."
    }
    elseif ($sizeInGB -ne 0) {
        $volSize = $sizeInGB * 1024 *1024 *1024   
    }
    else {
        $volSize = $sizeInTB * 1024 *1024 *1024 * 1024
    }
    try {
        $hostGroup = $cluster | get-faHostGroupfromVcCluster -flasharray $flasharray -ErrorAction Stop
    }
    catch {
        throw $Global:Error[0]
    }
    $newVol = New-PfaVolume -Array $flasharray -Size $volSize -VolumeName $volName -ErrorAction Stop
    New-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $newVol.name -HostGroupName $hostGroup.name |Out-Null
    $esxi = $cluster | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.*')}| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1
    $cluster| Get-VMHost | Get-VMHostStorage -RescanAllHba |Out-Null
    $newNAA =  "naa.624a9370" + $newVol.serial.toLower()
    $ESXiApiVersion = $esxi.ExtensionData.Summary.Config.Product.ApiVersion
    try {
        if (($ESXiApiVersion -eq "5.5") -or ($ESXiApiVersion -eq "6.0") -or ($ESXiApiVersion -eq "5.1"))
        {
            $newVMFS = $esxi |new-datastore -name $newVol.name -vmfs -Path $newNAA -FileSystemVersion 5 -ErrorAction Stop
        }
        else
        {
            $newVMFS = $esxi |new-datastore -name $newVol.name -vmfs -Path $newNAA -FileSystemVersion 6 -ErrorAction Stop
        }
        return $newVMFS
    }
    catch {
        Write-Error $Global:Error[0]
        Remove-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $newVol.name -HostGroupName $hostGroup.name
        Remove-PfaVolumeOrSnapshot -Array $flasharray -Name $newVol.name 
        Remove-PfaVolumeOrSnapshot -Array $flasharray -Name $newVol.name -Eradicate
        return $null
    }
}

function add-faVolVmfsToCluster {
    <#
    .SYNOPSIS
      Add an existing FlashArray-based VMFS to another VMware cluster.
    .DESCRIPTION
      Takes in a vCenter Cluster and a datastore and the corresponding FlashArray
    .INPUTS
      FlashArray connection, a vCenter cluster, and a datastore
    .OUTPUTS
      Returns the FlashArray host group connection.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/10/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray,

            [Parameter(Position=2,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
    )
    try {
        $pureVol = $datastore | get-faVolfromVMFS -flasharray $flasharray -ErrorAction Stop
        $hostGroup = $cluster |get-faHostGroupfromVcCluster -flasharray $flasharray -ErrorAction Stop
        $faConnection = New-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $pureVol.name -HostGroupName $hostGroup.name -ErrorAction Stop
    }
    catch {
        Write-Error $Global:Error
        return $null
    }
    try {
        $cluster| Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs -ErrorAction Stop |Out-Null
    }
    catch {
        Write-Error $Global:Error[0]
        Remove-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $pureVol.name -HostGroupName $hostGroup.name |Out-Null
        return $null
    }
    return $faConnection
}

function set-faVolVmfsCapacity {
    <#
    .SYNOPSIS
      Increase the size of a FlashArray-based VMFS datastore.
    .DESCRIPTION
      Takes in a datastore, the corresponding FlashArray, and a new size. Both the volume and the VMFS will be grown.
    .INPUTS
      FlashArray connection, a size, and a datastore
    .OUTPUTS
      Returns the datastore.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/11/2018
      Purpose/Change: Initial script development
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=2)]
            [int]$sizeInGB,

            [Parameter(Position=3)]
            [int]$sizeInTB
    )
    if (($sizeInGB -eq 0) -and ($sizeInTB -eq 0))
    {
        throw "Please enter a size in GB or TB"
    }
    elseif (($sizeInGB -ne 0) -and ($sizeInTB -ne 0)) {
        throw "Please only enter a size in TB or GB, not both."
    }
    elseif ($sizeInGB -ne 0) {
        $volSize = $sizeInGB * 1024 *1024 *1024   
    }
    else {
        $volSize = $sizeInTB * 1024 *1024 *1024 * 1024
    }
    if ($volSize -le $pureVol.size)
    {
        throw "The new size cannot be smaller than the existing size. VMFS volumes cannot be shrunk."
        return $null
    }
    try {
        $pureVol = $datastore | get-faVolfromVMFS -flasharray $flasharray -ErrorAction Stop
        Resize-PfaVolume -Array $flasharray -VolumeName $pureVol.name -NewSize $volSize |Out-Null
    }
    catch {
        Write-Error $Global:Error
        return $null
    }
    try {
        $datastore| Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs -ErrorAction Stop |Out-Null
        $esxiView = Get-View -Id ($Datastore.ExtensionData.Host |Select-Object -last 1 | Select-Object -ExpandProperty Key)
        $datastoreSystem = Get-View -Id $esxiView.ConfigManager.DatastoreSystem
        $expandOptions = $datastoreSystem.QueryVmfsDatastoreExpandOptions($datastore.ExtensionData.MoRef)
        $expandedDS = $datastoreSystem.ExpandVmfsDatastore($datastore.ExtensionData.MoRef,$expandOptions[0].spec)
    }
    catch {
        Write-Error $Global:Error[0]
        return $null
    }
    return $expandedDS
}

