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
Write-host "Pure Storage VMware Best Practice Check Script"
write-host "----------------------------------------------"
write-host

#Enter the following parameters. Put all entries inside the quotes:
#**********************************
$vcenter = "vcenter IP"
$vcuser = "username"
$vcpass = "password"
$logfolder = "C:\Users\cody.PURESTORAGE\Documents\Results\"
#############################


$logfile = $logfolder + (Get-Date -Format o |ForEach-Object {$_ -Replace ":", "."}) + "bestpracticeresults.txt"
connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
$hosts= get-vmhost
$iops = 1 
$iopsnumber=$iops
$iops = "iops=" + $iops  
add-content $logfile "Iterating through all ESXi hosts..."
foreach ($esx in $hosts) 
 {
      $esxcli=get-esxcli -VMHost $esx
      add-content $logfile "==================================================================================="
      add-content $logfile "******************************Next ESXi host***************************************"
      add-content $logfile "==================================================================================="
      add-content $logfile "Working on the following ESXi host:"
      add-content $logfile $esx.NetworkInfo
      add-content $logfile "----------------------------------------------------------------------------------" 
      add-content $logfile "Checking the VMware VAAI XCOPY Transfer size setting (recommended size is 16 MB)"
 
      $xfersize = $esx | Get-AdvancedSetting -Name DataMover.MaxHWTransferSize
      if ($xfersize.value -ne 16384)
           {
                add-content $logfile "The transfer size is set to an amount that differs from best practices of 16 MB."

           }
      else 
           {
               add-content $logfile "The XCOPY transfer size is set correctly."
           }
      add-content $logfile "----------------------------------------------------------------------------------" 
      add-content $logfile "Looking for Storage Array Type Plugin (SATP) rules for Pure Storage FlashArray devices..."
      $rule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
      if ($rule.Count -eq 1) 
          {
              if ($rule.DefaultPSP -eq "VMW_PSP_RR") 
                   {
                       add-content $logfile "The existing Pure/FlashArray rule is configured with the correct Path Selection Policy (Round Robin)"
                   }
              else 
                   {
                       add-content $logfile "The existing Pure/FlashArray rule is NOT configured with the correct Path Selection Policy"
                       add-content $logfile "The existing rule should be configured to Round Robin"
                    }
              if ($rule.PSPOptions -like "*$iops*") 
                   {
                       add-content $logfile "The existing Pure/FlashArray rule is configured with the correct IO Operations Limit"
                   }
              else 
                   {
                       add-content $logfile "The existing Pure/FlashArray rule is NOT configured with the as-entered IO Operations Limit"
                       add-content $logfile "The as-entered IO Operations Limit is " 
                       add-content $logfile $iopsnumber 
                       add-content $logfile "The current rule has the following PSP options:"
                       add-content $logfile $rule.PSPOptions
                   } 

           }
       elseif ($rule.Count -ge 2)
           {
                add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------"
                add-content $logfile "***NOTICE***: Multiple Pure Storage Rules have been found and this will require manual cleanup."
                add-content $logfile "Please examine your rules and delete unnecessary ones. No rule will be created. Doing per-volume check only."
                add-content $logfile "-------------------------------------------------------------------------------------------------------------------------------------------" 
           }
       else
           {  
                add-content $logfile "No default SATP rule for the Pure Storage FlashArray found. Create a new rule to set Round Robin and IO Operations Limit default" 
                
           }
       add-content $logfile "----------------------------------------------------------------------------------" 
       $devices = $esx |Get-ScsiLun -CanonicalName "naa.624a9370*"
       if ($devices.count -ge 1) 
           {
                 add-content $logfile "Looking for existing Pure Storage volumes on this host"
                 $devpsp = [array] "These devices have the wrong PSP:"
                 $deviops = [array] "These devices have the wrong IO Operations Limit, but the correct PSP:"
                 foreach ($device in $devices)
                       {
                                if ($device.MultipathPolicy -ne "RoundRobin")
                                    {
                                         $devpsp += $device.CanonicalName
                                    }
                                if ($device.MultipathPolicy -eq "RoundRobin")
                                    {
                                        $deviceconfig = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get($device)
                                    
                                         if ($deviceconfig.IOOperationLimit -ne $iopsnumber)
                                            {
                                              $deviops += $device.CanonicalName
                                            }
                                    }
                       }
            }
            else
                  {
                      add-content $logfile "No existing Pure Storage volumes found on this host."
                  }
            
            if ($devpsp.Count -eq 1)
                {
                    add-content $logfile "All devices on this host have the correct PSP of Round Robin"
                }
            else
                {
                    add-content $logfile $devpsp
                }
            if ($deviops.Count -eq 1)
                {
                    add-content $logfile "All of the devices using the Round Robin PSP on this host have the correct IO Operations Limit"
                }
            else
                {
                    add-content $logfile $deviops
                }
     }
 disconnect-viserver -Server $vcenter -confirm:$false