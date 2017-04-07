<#
*******Disclaimer:******************************************************
This scripts are offered "as is" with no warranty.  While this 
scripts is tested and working in my environment, it is recommended that you test 
this script in a test lab before using in a production environment. Everyone can 
use the scripts/commands provided here without any written permission but I
will not be liable for any damage or loss to the system.
************************************************************************
see more info at:

http://wp.me/p6acjZ-Ci

#>


write-host '             __________________________'
write-host '            /++++++++++++++++++++++++++\'           
write-host '           /++++++++++++++++++++++++++++\'           
write-host '          /++++++++++++++++++++++++++++++\'         
write-host '         /++++++++++++++++++++++++++++++++\'        
write-host '        /++++++++++++++++++++++++++++++++++\'       
write-host '       /++++++++++++/----------\++++++++++++\'     
write-host '      /++++++++++++/            \++++++++++++\'    
write-host '     /++++++++++++/              \++++++++++++\'   
write-host '    /++++++++++++/                \++++++++++++\'  
write-host '   /++++++++++++/                  \++++++++++++\' 
write-host '   \++++++++++++\                  /++++++++++++/' 
write-host '    \++++++++++++\                /++++++++++++/' 
write-host '     \++++++++++++\              /++++++++++++/'  
write-host '      \++++++++++++\            /++++++++++++/'    
write-host '       \++++++++++++\          /++++++++++++/'     
write-host '        \++++++++++++\'                   
write-host '         \++++++++++++\'                           
write-host '          \++++++++++++\'                          
write-host '           \++++++++++++\'                         
write-host '            \------------\'
write-host 'Log Insight Ingestion REST API Example'
write-host '----------------------------------------------------------------------------------------------------'

$loginsightserver = "10.21.10.27"
$loginsightagentID = "624a9370"

    $restvmfs = [ordered]@{
                    name = "Datastore"
                    content = "vmfs"
                    }
    $restarray = [ordered]@{
                    name = "FlashArray"
                    content = "array"
                    }
    $restvol = [ordered]@{
                    name = "FlashArrayvol"
                    content = "vol"
                    }
    $restunmap = [ordered]@{
                    name = "ReclaimedSpace"
                    content = "454"
                    }
    $esxhost = [ordered]@{
                    name = "ESXihost"
                    content = "host"
                    }
    $devicenaa = [ordered]@{
                    name = "SCSINaa"
                    content = "naa.624a9370a847c250adbb1c7b00011aca"
                    }
    $fields = @($restvmfs,$restarray,$restvol,$restunmap,$esxhost,$devicenaa)
    $restcall = @{
                 messages =    ([Object[]]($messages = [ordered]@{
                        text = "Completed a VMFS UNMAP on a FlashArray volume."
                        fields = ([Object[]]$fields)
                        }))
                } |convertto-json -Depth 4

    $resturl = ("http://" + $loginsightserver + ":9000/api/v1/messages/ingest/" + $loginsightagentID)
    write-host ("Posting results to Log Insight server: " + $loginsightserver)
    try
    {
        $response = Invoke-RestMethod $resturl -Method Post -Body $restcall -ContentType 'application/json' -ErrorAction stop
        write-host "REST Call to Log Insight server successful"
        write-host $response
    }
    catch
    {
        write-host "REST Call failed to Log Insight server"
        write-host $error[0]
        write-host $resturl
    }