#Enter the following parameters. Put all entries inside the quotes:
#**********************************
$vcenter = "vCenter Address"
$vcuser = "username"
$vcpass = "password"
$logfolder = "C:\Users\user\Documents\Results\"
#############################

set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
If (!(Test-Path -Path $logfolder)) { New-Item -ItemType Directory -Path $logfolder }
$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ":", "."}) + "SRMProtectedVMs.txt"

add-content $logfile "             __________________________"
add-content $logfile "            /++++++++++++++++++++++++++\"           
add-content $logfile "           /++++++++++++++++++++++++++++\"           
add-content $logfile "          /++++++++++++++++++++++++++++++\"         
add-content $logfile "         /++++++++++++++++++++++++++++++++\"        
add-content $logfile "        /++++++++++++++++++++++++++++++++++\"       
add-content $logfile "       /++++++++++++/----------\++++++++++++\"     
add-content $logfile "      /++++++++++++/            \++++++++++++\"    
add-content $logfile "     /++++++++++++/              \++++++++++++\"   
add-content $logfile "    /++++++++++++/                \++++++++++++\"  
add-content $logfile "   /++++++++++++/                  \++++++++++++\" 
add-content $logfile "   \++++++++++++\                  /++++++++++++/" 
add-content $logfile "    \++++++++++++\                /++++++++++++/" 
add-content $logfile "     \++++++++++++\              /++++++++++++/"  
add-content $logfile "      \++++++++++++\            /++++++++++++/"    
add-content $logfile "       \++++++++++++\          /++++++++++++/"     
add-content $logfile "        \++++++++++++\"                   
add-content $logfile "         \++++++++++++\"                           
add-content $logfile "          \++++++++++++\"                          
add-content $logfile "           \++++++++++++\"                         
add-content $logfile "            \------------\"
add-content $logfile ""
add-content $logfile "Pure Storage SRM Protected VM Inquiry Script"
add-content $logfile "----------------------------------------------"
add-content $logfile ""

connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
Connect-SrmServer |out-null
$srmapi = $defaultsrmservers.ExtensionData
$srmpgs = $srmapi.protection.listprotectiongroups()
for ($i=0; $i -lt $srmpgs.Count; $i++)
{
    $vms = $srmpgs[$i].ListProtectedVMs()
    $pgvms = [array] "Virtual Machine list:"
    for ($a=0; $a -lt $vms.Count; $a++)
    {
        
        $vm = get-vm -ID $vms[$a].VM.MoRef
        $pgvms += $vm.Name
    }
    $pgname = $srmapi.protection.listprotectiongroups()[$i].GetInfo().Name
    add-content $logfile "==================================================================================="
    add-content $logfile "******************************Next Protection Group********************************"
    add-content $logfile "==================================================================================="
    $text = "The following " + $vms.Count  + " virtual machines are in the Protection Group named "  + $pgname
    add-content $logfile $text
    add-content $logfile $pgvms 
}
disconnect-viserver -Server $vcenter -confirm:$false