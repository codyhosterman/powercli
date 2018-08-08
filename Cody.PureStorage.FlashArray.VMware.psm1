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

            [Parameter(Position=1,mandatory=$true)]
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
        
        [Parameter(Position=1)]
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

            [Parameter(Position=1,mandatory=$true)]
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