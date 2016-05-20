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
#Enter the following parameters. Put all entries inside the quotes:
#**********************************
#vCenter IP and username/password:
$vcenter = ""
$vcuser = ""
$vcpass = ""
#FlashArray IP and username/password
$flasharrays = @('<array IP or FQDN>','<array IP or FQDN>')
$pureuser = ""
$pureuserpwd = ""
#Target VMware Cluster Name
$cluster = ""
#Desired Storage Protocol in $protocol. Valid entries are "FC" for Fibre Channel or "iSCSI" for iSCSI
$protocol = ""
$logfolder = 'C:\folder\folder\etc\'
#**********************************


<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************

This script will create host groups and populate it with hosts it creates based on the VMware ESXi cluster passed into the script. It will create this on each FlashArray entered.

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-PowerShell 3.0 or later
-Pure Storage PowerShell SDK 1.5 or later
-PowerCLI 6.3 Release 1
-REST API 1.4 and later
-Purity 4.1 and later
-FlashArray 400 Series and //m
-vCenter 5.5 and later (not tested with 5.1, but probably will work)

#>
#Create log folder if non-existent
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "createhostgroups.txt"

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
add-content $logfile 'Pure Storage VMware ESXi Host Group Creation Script v2.2'
add-content $logfile '----------------------------------------------------------------------------------------------------'

$facount=0
$EndPoint= @()
$failedFAs = @()
$successfulFAs = @()
$Pwd = ConvertTo-SecureString $pureuserpwd -AsPlainText -Force
$Creds = New-Object System.Management.Automation.PSCredential ($pureuser, $pwd)
write-host "Script information can be found at $logfile" -ForegroundColor Green

function disconnectvCenter
{
    #a function to disconnect sessions
    add-content $logfile ("Disconnecting vCenter session")
    disconnect-viserver -Server $vcenter -confirm:$false
}
function disconnectFlashArray
{
    #a function to disconnect sessions
    add-content $logfile ("Disconnecting FlashArray session(s)")
    foreach ($flasharray in $endpoint)
    {
        Disconnect-PfaArray -Array $flasharray
    }
}

if (($protocol -ne "FC") -and ($protocol -ne "iSCSI"))
{
    add-content $logfile 'No valid protocol entered. Please make sure $protocol is set to either "FC" or "iSCSI"'
    write-host ( 'No valid protocol entered. Please make sure $protocol is set to either "FC" or "iSCSI"') -BackgroundColor Red
}
else
{

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
                disconnectFlashArray 
                return
            }
        }
        else
        {
            try
            {
                $EndPoint += New-PfaArray -EndPoint $flasharray -Credentials $Creds -IgnoreCertificateError
            }
            catch
            {
                write-host ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN") -BackgroundColor Red
                write-host $Error[0]
                add-content $logfile ("Connection to FlashArray " + $flasharray + " failed. Please check credentials or IP/FQDN")
                add-content $logfile $Error[0]
                disconnectFlashArray
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
    . "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1" |Out-Null
    } Out-Null
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
        disconnectFlashArray
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
        disconnectFlashArray
        return
    }

    add-content $logfile ('Connected to vCenter at ' + $vcenter)
    add-content $logfile '----------------------------------------------------------------------------------------------------'
    #Instantiate Cluster and Host variables
    try
    {
        $esxicluster = get-cluster $cluster -ErrorAction Stop
    }
    catch
    {
        add-content $logfile ("A cluster with the name " + $cluster + " could not be found. Verify cluster name. Terminating script.")
        write-host ("A cluster with the name " + $cluster + " could not be found. Verify cluster name. Terminating script.") -BackgroundColor Red
        add-content $logfile $error[0]
        disconnectFlashArray
        disconnectvCenter
        return
    }
    $esxihosts = $esxicluster | Get-VMHost -ErrorAction Stop
    if ($esxihosts.Count -eq 0)
    {
        add-content $logfile ("No ESXi hosts were found in the cluster named " + $cluster + ". Verify cluster configuration/permissions. Terminating script.")
        write-host ("No ESXi hosts were found in the cluster named " + $cluster + ". Verify cluster configuration/permissions. Terminating script.") -BackgroundColor Red
        disconnectFlashArray
        disconnectvCenter
        return
    }
}
#-----------------------------------------------------------------------------------------------------------------------------------------------------------
#Configure the VMware cluster as a new host group on the FlashArray. Using the cluster name as the host group name.
#-----------------------------------------------------------------------------------------------------------------------------------------------------------
foreach ($flasharray in $endpoint)
{
    $hostgroupfailed = $false
    if ($protocol -eq "iSCSI")
    {
        add-content $logfile "-------------------------------------------------------------------"
        add-content $logfile ("")
        add-content $logfile ("*********************************************************")
        add-content $logfile ("Creating host group on FlashArray " + $flasharray.endpoint)
        add-content $logfile "Configuring iSCSI host group"
        add-content $logfile ("*********************************************************")
        add-content $logfile ("")
        add-content $logfile ("Verifying that the initiators do not currently exist on the FlashArray")
        try
        {
            $fahosts = Get-PFAHosts -array $flasharray -ErrorAction Stop
            $fahostgroups = Get-PFAHostGroups -array $flasharray -ErrorAction Stop
        }
        catch
        {
            add-content $logfile ("")
            add-content $logfile ("********ERROR********")
            add-content $logfile ("Could not obtain host information from the FlashArray. Check FlashArray for errors. Skipping the FlashArray named " + $flasharray.endpoint)
        } 
        $iqnexist = $false
        if ($hostgroupfailed -eq $false)
        {
            foreach ($esxihost in $esxihosts)
            {
                add-content $logfile ("Looking at the following host")
                add-content $logfile $esxihost.NetworkInfo.HostName
                $iscsiadapter = $esxihost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
                if ($iscsiadapter -eq $null)
                {
                    add-content $logfile ("No Software iSCSI adapter found on host " + $esxihost.NetworkInfo.HostName + ". Terminating script. No changes were made.")
                    write-host ("No Software iSCSI adapter found on host " + $esxihost.NetworkInfo.HostName + ". Terminating script. No changes were made.") -BackgroundColor Red
                    disconnectFlashArray
                    disconnectvCenter
                    return
                }
                else
                {
                    $iqn = $iscsiadapter.ExtensionData.IScsiName
                    foreach ($esxi in $fahosts)
                    {
                        add-content $logfile ("Found " + $iqn.Count + " IQN initiator:" )
                        $iqn | out-string | add-content $logfile
                        if ($esxi.iqn.count -ge 1)
                        {
                            foreach($fahostiqn in $esxi.iqn)
                            {
                                if ($iqn.ToLower() -eq $fahostiqn.ToLower())
                                {
                                    add-content $logfile ("********ERROR********")
                                    add-content $logfile ("The ESXi IQN " + $iqn + " exists on the FlashArray.")
                                    $hostgroupfailed = $true
                                    $iqnexist = $true
                                }
                            }
                        }
                    }
                }
            }
            if ($iqnexist -eq $true)
            {
                add-content $logfile ("ESXi host's IQNs have been found on this FlashArray. Skipping the FlashArray named " + $flasharray.endpoint)
            }
            else
            {
                $createhostfail = $false
                $newfahosts = @()
                foreach ($esxihost in $esxihosts)
                {
                    if ($createhostfail -eq $false)
                    {
                        $iscsiadapter = $esxihost | Get-VMHostHBA -Type iscsi | Where {$_.Model -eq "iSCSI Software Adapter"}
                        $iqn = $iscsiadapter.ExtensionData.IScsiName
                        try
                        {
                            $newfahosts += New-PfaHost -Array $flasharray -Name $esxihost.NetworkInfo.HostName -IqnList $iqn -ErrorAction stop
                        }
                        catch
                        {
                            add-content $logfile ("********ERROR********")
                            add-content $logfile ("The host " + $esxihost.NetworkInfo.HostName + " failed to create. Review error. Cleaning up this FlashArray and moving on.")
                            $hostgroupfailed = $true
                            add-content $logfile $error[0]
                            $createhostfail = $true
                            if ($newfahosts.count -ge 1)
                            {
                                add-content $logfile ("Deleting the " + $newfahosts.count + " hosts on this FlashArray that were created by this script")
                                foreach ($removehost in $newfahosts)
                                {
                                    Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                    add-content $logfile ("Removed host " + $removehost.Name)
                                }
                            }
                        }
                    }
                }
                if ($createhostfail -eq $false)
                {
                    add-content $logfile "Created the following hosts"
                    foreach ($newhost in $newfahosts)
                    {
                        Get-PfaHost -Array $flasharray -Name $newhost.name | out-string | add-content $logfile
                    }
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
                    add-content $logfile "Creating the host group"
                    $clustersuccess = $false
                    try
                    {
                        $newcluster = New-PfaHostGroup -Array $flasharray -Name $clustername -ErrorAction stop
                        $newcluster | out-string | add-content $logfile
                        $clustersuccess = $true
                    }
                    catch
                    {
                        add-content $logfile ("********ERROR********")
                        add-content $logfile ("The host group " + $clustername + " failed to create. Review error below. Cleaning up this FlashArray and moving on.")
                        $hostgroupfailed = $true
                        add-content $logfile $error[0]
                        if ($newfahosts.count -ge 1)
                        {
                            add-content $logfile ("Deleting the " + $newfahosts.count + " hosts on this FlashArray that were created by this script")
                            foreach ($removehost in $newfahosts)
                            {
                                Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                add-content $logfile ("Removed host " + $removehost.Name)
                            }
                        }
                    }
                    if ($clustersuccess -eq $true)
                    {
                        add-content $logfile "Adding the hosts to the host group"
                        foreach ($newfahost in $newfahosts)
                        {
                            Add-PfaHosts -Array $flasharray -Name $clustername -hoststoadd $newfahost.name |Out-Null
                        }
                        Get-PfaHostGroup -Array $flasharray -Name $clustername | out-string | add-content $logfile
                    }
                }
            }
        }
    }
    elseif ($protocol -eq "FC")
    {
        add-content $logfile "-------------------------------------------------------------------"
        add-content $logfile ("")
        add-content $logfile ("*********************************************************")
        add-content $logfile ("Creating host group on FlashArray " + $flasharray.endpoint)
        add-content $logfile "Configuring Fibre Channel host group"
        add-content $logfile ("*********************************************************")
        add-content $logfile ("")
        add-content $logfile ("Verifying that the initiators do not currently exist on the FlashArray")
        try
        {
            $fahosts = Get-PFAHosts -array $flasharray -ErrorAction Stop
            $fahostgroups = Get-PFAHostGroups -array $flasharray -ErrorAction Stop
        }
        catch
        {
            add-content $logfile ("")
            add-content $logfile ("********ERROR********")
            add-content $logfile ("Could not obtain host information from the FlashArray. Check FlashArray for errors. Skipping the FlashArray named " + $flasharray.endpoint)
            $hostgroupfailed = $true
        }
        $wwnsexist = $false
        if ($hostgroupfailed -eq $false)
        {
            foreach ($esxihost in $esxihosts)
            {
                add-content $logfile ("")
                add-content $logfile ("----------------------------------")
                add-content $logfile ("Looking at the following host")
                add-content $logfile $esxihost.NetworkInfo.HostName
                $wwns = $esxihost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
                $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
                $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
                {
                     $wwns.substring($i,16)
                }}
                if ($wwns -eq $null)
                {
                    add-content $logfile ("No FC WWNs found on host " + $esxihost.NetworkInfo.HostName + ". Terminating script. No changes were made.")
                    write-host  ("No FC WWNs found on host " + $esxihost.NetworkInfo.HostName + ". Terminating script. No changes were made.") -BackgroundColor Red
                    disconnectFlashArray
                    disconnectvCenter
                    return
                }
                else
                {
                    add-content $logfile ("Found " + $wwns.Count + " initiator(s):" )
                    $wwns | out-string | add-content $logfile
                    foreach ($wwn in $wwns)
                    {
                        foreach ($esxi in $fahosts)
                        {
                            if ($esxi.wwn.count -ge 1)
                            {
                                foreach($fahostwwn in $esxi.wwn)
                                {
                                    if ($wwn.ToLower() -eq $fahostwwn.ToLower())
                                    {
                                        add-content $logfile ("********ERROR********")
                                        add-content $logfile ("The ESXi WWN " + $wwn + " exists on the FlashArray.")
                                        $hostgroupfailed = $true
                                        $wwnsexist = $true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if ($wwnsexist -eq $true)
            {
                add-content $logfile ""
                add-content $logfile ("ESXi host's WWNs have been found on this FlashArray. Skipping the FlashArray named " + $flasharray.endpoint)
            }
            else
            {
                $createhostfail = $false
                $createwwnfail = $false
                $newfahosts = @()
                foreach ($esxihost in $esxihosts)
                {
                    if ($createhostfail -eq $false)
                    {
                        $wwns = $esxihost | Get-VMHostHBA -Type FibreChannel | Select VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
                        $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
                        $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
                        {
                             $wwns.substring($i,16)
                        }}
                        try
                        {
                            $newfahosts += New-PfaHost -Array $flasharray -Name $esxihost.NetworkInfo.HostName -ErrorAction stop
                                foreach ($wwn in $wwns)
                                {
                                    if ($createhostfail -eq $false)   
                                    {
                                        try
                                        {
                                            Add-PfaHostWwns -Array $flasharray -Name $esxihost.NetworkInfo.HostName -AddWwnList $wwn -ErrorAction stop |out-null
                                        }
                                        catch
                                        {
                                            add-content $logfile ("********ERROR********")
                                            add-content $logfile ("The WWN " + $wwn + " failed to add. Review error. Cleaning up this FlashArray and moving on.")
                                            $hostgroupfailed = $true
                                            add-content $logfile $error[0]
                                            $createhostfail = $true
                                            if ($newfahosts.count -ge 1)
                                            {
                                                add-content $logfile ("Deleting the " + $newfahosts.count + " hosts on this FlashArray that were created by this script")
                                                foreach ($removehost in $newfahosts)
                                                {
                                                    Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                                    add-content $logfile ("Removed host " + $removehost.Name)
                                                }
                                            }
                                        }
                                    }
                                }
                        }
                        catch
                        {
                            add-content $logfile ("********ERROR********")
                            add-content $logfile ("The host " + $esxihost.NetworkInfo.HostName + " failed to create. Review error. Cleaning up this FlashArray and moving on.")
                            $hostgroupfailed = $true
                            add-content $logfile $error[0]
                            $createhostfail = $true
                            if ($newfahosts.count -ge 1)
                            {
                                add-content $logfile ("Deleting the " + $newfahosts.count + " hosts on this FlashArray that were created by this script")
                                foreach ($removehost in $newfahosts)
                                {
                                    Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                    add-content $logfile ("Removed host " + $removehost.Name)
                                }
                            }
                        }
                    }
                }
                if ($createhostfail -eq $false)
                {
                    add-content $logfile "Created the following hosts"
                    foreach ($newhost in $newfahosts)
                    {
                        Get-PfaHost -Array $flasharray -Name $newhost.name | out-string | add-content $logfile
                    }
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
                    add-content $logfile "Creating the host group"
                    $clustersuccess = $false
                    try
                    {
                        $newcluster = New-PfaHostGroup -Array $flasharray -Name $clustername -ErrorAction stop
                        $newcluster | out-string | add-content $logfile
                        $clustersuccess = $true
                    }
                    catch
                    {
                        add-content $logfile ("********ERROR********")
                        add-content $logfile ("The host group " + $clustername + " failed to create. Review error below. Cleaning up this FlashArray and moving on.")
                        $hostgroupfailed = $true
                        add-content $logfile $error[0]
                        if ($newfahosts.count -ge 1)
                        {
                            add-content $logfile ("Deleting the " + $newfahosts.count + " hosts on this FlashArray that were created by this script")
                            foreach ($removehost in $newfahosts)
                            {
                                Remove-PfaHost -Array $flasharray -Name $removehost.Name |out-null
                                add-content $logfile ("Removed host " + $removehost.Name)
                            }
                        }
                    }
                    if ($clustersuccess -eq $true)
                    {
                        add-content $logfile "Adding the hosts to the host group"
                        foreach ($newfahost in $newfahosts)
                        {
                            Add-PfaHosts -Array $flasharray -Name $clustername -hoststoadd $newfahost.name |Out-Null
                        }
                        Get-PfaHostGroup -Array $flasharray -Name $clustername | out-string | add-content $logfile
                    }
                }
            }
        }
    }
    if ($hostgroupfailed -eq $true)
    {
        $failedFAs += $flasharray.endpoint
        $hostgroupfailure = $true
    }
    else
    {
        $successfulFAs += $flasharray.endpoint
    }
}

$templog = Get-Content $logfile
rm $logfile
if ($hostgroupfailure -eq $true)
{
    add-content -Path $logfile -Value ("****THERE IS AN ERROR WITH THE CREATION OF ONE OR MORE HOST GROUPS, REVIEW LOG BELOW FOR DETAILS. LOOK FOR LINES MARKED WITH ********ERROR********")
    add-content $logfile ""
    add-content $logfile "The creation of a host group on the following FlashArray(s) failed:" 
    $failedFAs | out-string | add-content $logfile
    add-content $logfile ""
    write-host "" 
    write-host ("Host groups on the following FlashArray(s) failed to create. Refer to the log for additional information.") -foregroundColor Red
    $failedFAs | out-string | write-host
}

if ($successfulFAs.count -ge 1)
{
    add-content $logfile ("Host groups on the following FlashArray(s) successfully created. Refer to the log for additional information.")
    $successfulFAs | out-string | add-content $logfile
    write-host ""
    write-host ("Host groups on the following FlashArray(s) successfully created.") -foregroundColor green
    $successfulFAs | out-string | write-host
}

$templog | out-string | add-content $logfile
disconnectFlashArray
disconnectvCenter