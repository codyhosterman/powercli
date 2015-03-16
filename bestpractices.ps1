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
Write-host "Pure Storage VMware Set Best Practices Script"
write-host "----------------------------------------------"
write-host

#Enter the following parameters. Put all entries inside the quotes:
#**********************************
$vcenter = ""
$vcuser = ""
$vcpass = ""
#**********************************

connect-viserver -Server $vcenter -username $vcuser -password $vcpass|out-null
$hosts= get-cluster |get-vmhost
$iopslimits = 1..1000
do 
   {
      $iops = read-host "Please enter an IO Operation Limit (1 to 1000): " 
      $iopsnumber=$iops
     $iops = "iops=" + $iops  
   }
until ($iopsnumber -in $iopslimits)
write-host
write-host "Iterating through all ESXi hosts..."
write-host 
foreach ($esx in $hosts) 
 {
      $esxcli=get-esxcli -VMHost $esx
      write-host
      write-host
      write-host "==================================================================================="
      write-host "******************************Next ESXi host***************************************"
      write-host "==================================================================================="
      write-host "Working on the following ESXi host:"
      write-host $esx.NetworkInfo
      write-host 
      write-host "----------------------------------------------------------------------------------" 
      write-host "Checking the VMware VAAI XCOPY Transfer size setting (recommended size is 16 MB)"
      write-host 
 
      $xfersize = $esx | Get-AdvancedSetting -Name DataMover.MaxHWTransferSize
      write-host "The transfer size is currently set to " ($xfersize.value/1024) "MB."
      if ($xfersize.value -ne 16384)
           {
                write-host "The transfer size is set to an amount that differs from best practices. Changing setting to 16 MB..."
                $xfersize |Set-AdvancedSetting -Value 16384 -Confirm:$false |out-null
                write-host "XCOPY transfer size is now 16 MB."
                write-host 
           }
      else 
           {
               write-host "The XCOPY transfer size is set correctly and will not be altered."
               write-host 
           }
      write-host "----------------------------------------------------------------------------------" 
      write-host 
      write-host "Looking for Storage Array Type Plugin (SATP) rules for Pure Storage FlashArray devices..."
      $rule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
      if ($rule.Count -eq 1) 
          {
              write-host "An existing SATP rule for the Pure Storage FlashArray has been found."
              write-host 
              $issuecount = 0
              if ($rule.DefaultPSP -eq "VMW_PSP_RR") 
                   {
                       write-host "The existing Pure/FlashArray rule is configured with the correct Path Selection Policy (Round Robin)"
                   }
              else 
                   {
                       write-host "The existing Pure/FlashArray rule is NOT configured with the correct Path Selection Policy"
                       write-host "The existing rule should be configured to Round Robin"
                       $issuecount = 1
                   }
              if ($rule.PSPOptions -like "*$iops*") 
                   {
                       write-host "The existing Pure/FlashArray rule is configured with the correct IO Operations Limit"
                   }
              else 
                   {
                       write-host "The existing Pure/FlashArray rule is NOT configured with the as-entered IO Operations Limit"
                       write-host "The as-entered IO Operations Limit is " $iopsnumber 
                       write-host "The current rule has the following PSP options:"
                       $rule.PSPOptions
                       $issuecount = $issuecount + 1
                       write-host 
                   } 
              if ($issuecount -ge 1)
                   {
                       $answers = "Y","N" 
                       do 
                          {
                              $answer = read-host "Would you like this rule to be deleted and re-created with the correct parameters? (Y/N): "
                          }
                       until ($answer -in $answers)
                       if ($answer -eq "Y")
                          {
                             $esxcli.storage.nmp.satp.rule.remove($null, $null, $rule.Description, $null, $null, $rule.Model, $null, $rule.DefaultPSP, $rule.PSPOptions, "VMW_SATP_ALUA", $null, $null, "PURE") |Out-Null
                             write-host "Rule deleted."
                             $esxcli.storage.nmp.satp.rule.add($null, $null, "PURE FlashArray IO Operation Limit Rule", $null, $null, $null, "FlashArray", $null, "VMW_PSP_RR", $iops, "VMW_SATP_ALUA", $null, $null, "PURE") |out-null
                             write-host "New rule created:"
                             $newrule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
                             $newrule
                          }
                    }
           }
                elseif ($rule.Count -ge 2)
                   {
                        write-host "-------------------------------------------------------------------------------------------------------------------------------------------"
                        write-host "***NOTICE***: Multiple Pure Storage Rules have been found and this will require manual cleanup."
                        write-host
                        write-host "Please examine your rules and delete unnecessary ones. No rule will be created. Doing per-volume check only."
                        write-host "-------------------------------------------------------------------------------------------------------------------------------------------" 
                   }
                else
                   {  
                        write-host "No default SATP rule for the Pure Storage FlashArray found. Creating a new rule to set Round Robin and a IO Operation Limit of" $iops 
                        $esxcli.storage.nmp.satp.rule.add($null, $null, "PURE FlashArray IO Operation Limit Rule", $null, $null, $null, "FlashArray", $null, "VMW_PSP_RR", $iops, "VMW_SATP_ALUA", $null, $null, "PURE") |out-null
                        write-host "New rule created:"
                        $newrule = $esxcli.storage.nmp.satp.rule.list() |where-object {$_.Vendor -eq "PURE"}
                        $newrule
 }
                write-host "----------------------------------------------------------------------------------" 
                $devices = $esx |Get-ScsiLun -CanonicalName "naa.624a9370*"
                if ($devices.count -ge 1) 
                   {
                        write-host
                        write-host "Looking for existing Pure Storage volumes on this host"
                        write-host "Found " $devices.count " existing Pure Storage volumes on this host. Checking and fixing their multipathing configuration now."
                        foreach ($device in $devices)
                           {
                               write-host
                               write-host "----------------------------------"
                               write-host "Checking device " $device "..."
                               write-host
                               if ($device.MultipathPolicy -ne "RoundRobin")
                                    {
                                       write-host "This device does not have the correct Path Selection Policy. Setting to Round Robin..."
                                       Get-VMhost $esx |Get-ScsiLun $device |Set-ScsiLun -MultipathPolicy RoundRobin 
                                    }
                               else
                                    {
                                       write-host "This device's Path Selection Policy is correctly set to Round Robin already. No need to change."
                                    }
                               $deviceconfig = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get($device)
                               if ($deviceconfig.IOOperationLimit -ne $iopsnumber)
                                    {
                                        write-host "This device's IO Operation Limit is not set to the entered value."
                                        write-host "The IO Operation Limit for this device is currently set to " $deviceconfig.IOOperationLimit " Setting it to " $iopsnumber " now..."
                                        $esxcli.storage.nmp.psp.roundrobin.deviceconfig.set($null,$null,$device.CanonicalName,$iopsnumber,”iops”,$null) |out-null
                                    }
                               else
                                    {
                                        write-host "This device's IO Operation Limit matches the value entered. No need to change."
                                    }
                            }
                 }
              else
                  {
                      write-host "No existing Pure Storage volumes found on this host."
                  }
     }
 disconnect-viserver -Server $vcenter -confirm:$false