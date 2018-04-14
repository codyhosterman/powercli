# |        Load VMware modules if not loaded             |
# +------------------------------------------------------+
 

$vcenter = "vcenter-1.purecloud.com"
$vCenterUser = "cody"
$vCenterPassword = "Holdem08"
$vSwitchName = "vSwitch0"

Set-PowerCLIConfiguration -ParticipateInCEIP $true -confirm:$false
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -confirm:$false
Connect-VIServer -Server $vcenter -User $vCenterUser -Password $vCenterPassword
Import-Module VMware.VimAutomation.Extensions

$parentVMs = @("Final_Kali-2.0", "Ubuntu_Server", "winvm1","winvm2")


$randomNumber = get-random -Maximum 9999 -Minimum 1000

$vms = @()
foreach ($parentVM in $parentVMs)
{
    $argList = @($vcenter, $vCenterUser, $vCenterPassword,$vSwitchName,$randomNumber,$parentVM)    
    Start-Job -ScriptBlock{
        Connect-VIServer -Server $args[0]  -User $args[1]  -Password $args[2] 
        Import-Module VMware.VimAutomation.Extensions
        $datacenter = Get-Datacenter -Name "Mountain View"
        $vswitch = $datacenter | Get-VirtualSwitch -Name $args[3] 
        $parentVM = $args[5]
        switch($parentVM) {
            'Final_Kali-2.0' {
                $guestUser = "pureuser"
                $guestPassword = "pureuser"
            }
            'Ubuntu_Server' {
                $guestUser = "pureuser"
                $guestPassword = "pureuser"
            }
            default {
                $guestUser = "administrator"
                $guestPassword = "Osmium76!"
            }
        }
        $parentVM = get-vm $parentVM
        Enable-InstantCloneVM -vm $parentVM -guestUser $guestUser -GuestPassword $guestPassword -confirm:$false
        $parent = Get-InstantCloneVM -name $parentVM.name
        $childvm = New-InstantCloneVM -ParentVM $parent -Name "$($parent.name)-child-$($args[4])" 
        $vm = get-vm -Name "$($parent.name)-child-$($args[4])"
        $vmAdapters = $vm | get-networkadapter
        $networks = $vmAdapters.NetworkName | Select-Object -unique
        $portGroups = @{}
        foreach ($network in $networks) 
        {
            if (!$portGroups.ContainsKey($network)) {
                $newportGroup = $vswitch | New-VirtualPortGroup -Name "$($network)-$($args[4])"
                $portGroups.add($network, $newportGroup)
            }
        }
        Disconnect-VIServer -Server $args[0] -confirm:$false
    } -ArgumentList $argList
}
Get-Job | Wait-Job |out-null
$vms = get-vm -name "*$($randomNumber)"
foreach ($vm in $vms) {
    $vmAdapters = $vm |get-networkadapter
    foreach ($vmAdapter in $vmAdapters)
    {
        $vmAdapter |Set-networkadapter -NetworkName "$($vmAdapter.NetworkName)-$($randomNumber)" -confirm:$false |Out-Null
    }
    $vm | start-vm
}
Disconnect-VIServer -Server $vcenter -confirm:$false