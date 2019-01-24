function New-PureOneRestConnection {
    <#
    .SYNOPSIS
      Takes in a Pure1 Application ID and certificate to create a 10 hour access token.
    .DESCRIPTION
      Takes in a Pure1 Application ID and certificate to create a 10 hour access token. Can also take in a private key in lieu of the full cert. Will reject if the private key is not properly formatted.
    .INPUTS
      Pure1 Application ID, a certificate or a private key.
    .OUTPUTS
      Does not return anything--it stores the Pure1 REST access token in a global variable called $global:pureOneRestHeader. Valid for 10 hours.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/12/2019
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
            [Parameter(Position=0,ValueFromPipeline=$True)]
            [System.Security.Cryptography.X509Certificates.X509Certificate]$certificate,

            [Parameter(Position=1,mandatory=$True)]
            [string]$pureAppID,
            
            [Parameter(Position=2,ValueFromPipeline=$True)]
            [System.Security.Cryptography.RSA]$privateKey
    )
    Begin{
        if (($null -eq $privateKey) -and ($null -eq $certificate))
        {
            throw "You must pass in a x509 certificate or a RSA Private Key"
        }
        #checking for certificate accuracy
        if ($null -ne $certificate)
        {
            if ($certificate.HasPrivateKey -ne $true)
            {
                throw "There is no private key associated with this certificate. Please regenerate certificate with a private key."
            }
            if ($null -ne $certificate.PrivateKey)
            {
                $privateKey = $certificate.PrivateKey
            }
            else {
                try {
                    $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
                }
                catch {
                    throw "Could not obtain the private key from the certificate. Please re-run this cmdlet from a PowerShell session started with administrative rights."
                }
            }
        }
        #checking for correct private key type. Must be SHA-256, 2048 bit.
        if ($null -ne $privateKey)
        {
            if ($privateKey.KeySize -ne 2048)
            {
                throw "The key must be 2048 bit. It is currently $($privateKey.KeySize)"
            }
            if ($privateKey.SignatureAlgorithm -ne "RSA")
            {
                throw "This key is not an RSA-based key."
            }
        }
    }
    Process{
        $pureHeader = '{"alg":"RS256","typ":"JWT"}'
        $curTime = (Get-Date).ToUniversalTime()
        $curTime = [Math]::Floor([decimal](Get-Date($curTime) -UFormat "%s"))
        $expTime = $curTime  + 1000
        $payloadJson = '{"iss":"' + $pureAppID + '","iat":' + $curTime + ',"exp":' + $expTime + '}'
        $encodedHeader = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pureHeader)) -replace '\+','-' -replace '/','_' -replace '='
        $encodedPayload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payloadJson)) -replace '\+','-' -replace '/','_' -replace '='
        $toSign = $encodedHeader + '.' + $encodedPayload
        $toSignEncoded = [System.Text.Encoding]::UTF8.GetBytes($toSign)
        $signature = [Convert]::ToBase64String($privateKey.SignData($toSignEncoded,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)) -replace '\+','-' -replace '/','_' -replace '='
        $jwt = $toSign + '.' + $signature
    }
    End{
        $apiendpoint = "https://api.pure1.purestorage.com/oauth2/1.0/token"
        $AuthAction = @{
            grant_type = "urn:ietf:params:oauth:grant-type:token-exchange"
            subject_token = $jwt
            subject_token_type = "urn:ietf:params:oauth:token-type:jwt"
            }
        $pureOnetoken = Invoke-RestMethod -Method Post -Uri $apiendpoint -ContentType "application/x-www-form-urlencoded" -Body $AuthAction
        $Global:pureOneRestHeader = @{authorization="Bearer $($pureOnetoken.access_token)"} 
    }
}
function Get-PureOneArrays {
    <#
    .SYNOPSIS
      Returns all Pure Storage arrays listed in your Pure1 account.
    .DESCRIPTION
      Returns all Pure Storage arrays listed in your Pure1 account. Allows for some filters.
    .INPUTS
      None required. Optional inputs are array type, array name, and Pure1 access token.
    .OUTPUTS
      Returns the Pure Storage array information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/12/2019
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
            [string]$arrayName,

            [Parameter(Position=1)]
            [string]$arrayProduct,
            
            [Parameter(Position=2)]
            [string]$arrayId,

            [Parameter(Position=3)]
            [string]$pureOneToken
    )
    Begin{
        if ($arrayProduct -ne "")
        {
            switch ($arrayProduct) {
                "Purity//FA" {$arrayProduct = 'Purity//FA'; break}
                "Purity//FB" {$arrayProduct = 'Purity//FB'; break}
                "FlashArray" {$arrayProduct = 'Purity//FA'; break}
                "FlashBlade" {$arrayProduct = 'Purity//FB'; break}
                default {throw "The entered value, $($arrayProduct), is not a valid Pure Array product--accepted values are Purity//FB, Purity//FA, FlashArray, or FlashBlade"; break}
             }
        }
        $parameterCount = 0
        if ($arrayName -ne "")
        {
            $parameterCount++
            $restQuery = "?names=`'$($arrayName)`'"
        }
        if ($arrayProduct -ne "")
        {
            $parameterCount++
            $restQuery = "?filter=os=`'$($arrayProduct)`'"
        }
        if ($arrayId -ne "")
        {
            $parameterCount++
            $restQuery = "?ids=`'$($arrayId)`'"
        }
        if ($parameterCount -gt 1)
        {
            throw "Please only enter in one search parameter: ID, name, or product"
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/arrays" + $restQuery
        $pureArrays = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader     
    }
    End{
        return $pureArrays.items
    }
}
function New-PureOneRestOperation {
    <#
    .SYNOPSIS
      Allows you to run a Pure1 REST operation that has not yet been built into this module.
    .DESCRIPTION
      Runs a REST operation to Pure1
    .INPUTS
      A filter/query, an resource, a REST body, and optionally an access token.
    .OUTPUTS
      Returns Pure1 REST response.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/12/2019
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
        [Parameter(Position=0,mandatory=$True)]
        [string]$resourceType,

        [Parameter(Position=1)]
        [string]$queryFilter,

        [Parameter(Position=2)]
        [string]$jsonBody,

        [Parameter(Position=3,mandatory=$True)]
        [string]$restOperationType,

        [Parameter(Position=4)]
        [string]$pureOneToken
    )
    Begin{
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/" + $resourceType + $queryFilter
        if ($jsonBody -ne "")
        {
            $pureOneReponse = Invoke-RestMethod -Method $restOperationType -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader  -Body $jsonBody
        }
        else 
        {
            $pureOneReponse = Invoke-RestMethod -Method $restOperationType -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader 
        }   
    }
    End{
        return $pureOneReponse.items
    }
}
function Get-PureOneArrayTags {
    <#
    .SYNOPSIS
      Gets a tag for a given array or arrays in Pure1
    .DESCRIPTION
      Gets a tag for a given array or arrays in Pure1
    .INPUTS
      Array name(s) or ID(s) and optionally a tag key name and/or an access token.
    .OUTPUTS
      Returns the Pure Storage array(s) key/value tag information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/14/2019
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
            [string[]]$arrayNames,
         
            [Parameter(Position=1)]
            [string[]]$arrayIds,

            [Parameter(Position=2)]
            [string]$tagKey,

            [Parameter(Position=3)]
            [string]$pureOneToken
    )
    Begin{
        if (($arrayNames.count -gt 0) -and ($arrayIds.count -gt 0))
        {
            throw "Please only enter an array name or an ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        if ($arrayNames.count -gt 0)
        {
            $objectQuery = "resource_names="
            for ($i=0;$i -lt $arrayNames.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($arrayNames[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($arrayNames[$i])`'"
                }
            }
        }
        if ($arrayIds.Count -gt 0)
        {
            $objectQuery = "resource_ids="
            for ($i=0;$i -lt $arrayIds.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($arrayIds[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($arrayIds[$i])`'"
                }
            }
        }
        if ($tagKey -ne "")
        {
            $keyQuery = "?keys=`'$($tagKey)`'"
            if (($arrayNames.count -gt 0) -or ($arrayIds.count -gt 0))
            {
                $keyQuery = $keyQuery + "&"
            }
        }
        else
        {    
            $keyQuery = "?"
        }
        write-host $apiendpoint
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/arrays/tags" + $keyQuery + $objectQuery
        $pureArrayTags = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader     
    }
    End{
        return $pureArrayTags.items
    }
}
function Set-PureOneArrayTags {
    <#
    .SYNOPSIS
      Sets/updates a tag for a given array or arrays in Pure1
    .DESCRIPTION
      Sets/updates a tag for a given array or arrays in Pure1
    .INPUTS
      Array name(s) or ID(s) and a tag key name/value and/or optionally an access token.
    .OUTPUTS
      Returns the Pure Storage array(s) key/value tag information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/14/2019
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
            [string[]]$arrayNames,
         
            [Parameter(Position=1)]
            [string[]]$arrayIds,

            [Parameter(Position=2,mandatory=$True)]
            [string]$tagKey,

            [Parameter(Position=3,mandatory=$True)]
            [string]$tagValue,

            [Parameter(Position=4)]
            [string]$pureOneToken

    )
    Begin{
        if (($arrayNames.Count -gt 0) -and ($arrayIds.Count -gt 0))
        {
            throw "Please only enter an array name or an ID."
        }
        if (($arrayNames.Count -eq 0) -and ($arrayIds.Count -eq 0))
        {
            throw "Please enter an array name or an array ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        if ($arrayNames.count -gt 0)
        {
            $objectQuery = "?resource_names="
            for ($i=0;$i -lt $arrayNames.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($arrayNames[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($arrayNames[$i])`'"
                }
            }
        }
        if ($arrayIds.Count -gt 0)
        {
            $objectQuery = "?resource_ids="
            for ($i=0;$i -lt $arrayIds.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($arrayIds[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($arrayIds[$i])`'"
                }
            }
        }
        $newTag = @{
            key = ${tagKey}
            value = ${tagValue}
        }
        $newTagJson = $newTag |ConvertTo-Json
        $newTagJson = "[" + $newTagJson + "]"
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/arrays/tags/batch" + $objectQuery
        $pureArrayTags = Invoke-RestMethod -Method PUT -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader -Body $newTagJson    
    }
    End{
        return $pureArrayTags.items
    }
}
function Remove-PureOneArrayTags {
    <#
    .SYNOPSIS
      Removes one or more tags for a given array or arrays in Pure1
    .DESCRIPTION
      Removes one or more tags for a given array or arrays in Pure1
    .INPUTS
      Array name(s) or ID(s) and one or more tag key names and/or optionally an access token. If you do not enter a key name, all tags for the input arrays will be removed.
    .OUTPUTS
      Returns nothing.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/15/2019
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
            [string[]]$arrayNames,
         
            [Parameter(Position=1)]
            [string[]]$arrayIds,

            [Parameter(Position=2)]
            [string[]]$tagKeys,

            [Parameter(Position=3)]
            [string]$pureOneToken
    )
    Begin{
        if (($arrayNames.Count -gt 0) -and ($arrayIds.Count -gt 0))
        {
            throw "Please only enter one or more array names or one or more array IDs."
        }
        if (($arrayNames.Count -eq 0) -and ($arrayIds.Count -eq 0))
        {
            throw "Please enter one or more array names or an array IDs."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        if ($arrayNames.count -gt 0)
        {
            $objectQuery = "?resource_names="
            for ($i=0;$i -lt $arrayNames.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($arrayNames[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($arrayNames[$i])`'"
                }
            }
        }
        if ($arrayIds.Count -gt 0)
        {
            $objectQuery = "?resource_ids="
            for ($i=0;$i -lt $arrayIds.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($arrayIds[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($arrayIds[$i])`'"
                }
            }
        }
        if ($tagKeys.Count -gt 0)
        {
            $objectQuery = $objectQuery + "&keys="
            for ($i=0;$i -lt $tagKeys.count; $i++)
            {
                if ($i-eq 0)
                {
                    $objectQuery = $objectQuery + "`'$($tagKeys[$i])`'"
                }
                else {
                    $objectQuery = $objectQuery + ",`'$($tagKeys[$i])`'"
                }
            }
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/arrays/tags" + $objectQuery
        $pureArrayTags = Invoke-RestMethod -Method Delete -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader   
    }
    End{
        return $pureArrayTags
    }
}
function Get-PureOneArrayNetworking {
    <#
    .SYNOPSIS
      Returns the networking information for a given array in Pure1
    .DESCRIPTION
      Returns the the networking information for a given array in Pure1
    .INPUTS
      Array name or ID and optionally access token.
    .OUTPUTS
      Returns the Pure Storage array network information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/16/2019
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
            [string]$arrayName,
         
            [Parameter(Position=1)]
            [string]$arrayId,

            [Parameter(Position=2)]
            [Switch]$virtualIP,

            [Parameter(Position=3)]
            [string]$service,

            [Parameter(Position=4)]
            [string]$pureOneToken
    )
    Begin{
        if (($virtualIP -eq $true) -and (($service -ne "management") -and ($service -ne "") ))
        {
            throw "Virtual IPs are only management-based services, so you cannot request virtual IPs with $($service) as the service"
        }
        if (($arrayName -eq "") -and ($arrayId -eq ""))
        {
            throw "Please enter an array name or ID."
        }
        elseif (($arrayName -ne "") -and ($arrayId -ne ""))
        {
            throw "Please only enter an array name or an ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($virtualIP -eq $true)
        {
            $restQuery = $restQuery + "names=`'vir1`',`'vir0`'&"
        }
        if ($arrayName -ne "")
        {
            #URL encoding the square brackets as some network do not pass them properly
            $restQuery = $restQuery + "filter=" + ([System.Web.HttpUtility]::Urlencode("arrays[any].name")) + "=`'$($arrayName)`'"
        }
        if ($arrayId -ne "")
        {
            $restQuery = $restQuery + "filter=" + ([System.Web.HttpUtility]::Urlencode("arrays[any].name")) + "=`'$($arrayId)`'"
        }
        if ($service -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode(" and services[any]")) + "=`'$($service)`'"
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/network-interfaces" + $restQuery
        $pureArrayNetwork = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader 
    }
    End{
        return $pureArrayNetwork.items
    }
}
function Get-PureOneMetricDetails {
    <#
    .SYNOPSIS
      Returns the available metrics in Pure1 
    .DESCRIPTION
      Returns the available metrics in Pure1 and their specifics
    .INPUTS
      Resource type or metric name and/or access token.
    .OUTPUTS
      Returns the Pure Storage array information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/18/2019
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
            [string]$metricName,
         
            [Parameter(Position=1)]
            [string]$resourceType,

            [Parameter(Position=2)]
            [string]$pureOneToken
    )
    Begin{
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($resourceType -ne "")
        {
            $restQuery = $restQuery + "resource_types=`'$($resourceType)`'&"
        }
        if ($metricName -ne "")
        {
            $restQuery = $restQuery +"names=`'$($metricName)`'"
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/metrics" + $restQuery
        $pureOneMetrics = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader 
    }
    End{
        return $pureOneMetrics.items
    }
}
function Get-PureOneMetrics {
    <#
    .SYNOPSIS
      Returns the metrics for a given array in Pure1
    .DESCRIPTION
      Returns the metrics for a given array in Pure1, either an average or a maximum of a given time period. Default behavior is to return the average.
    .INPUTS
      Required: resource name or ID and metric name. Optional: timeframe, granularity, and aggregation type (if none entered defaults will be used based on metric entered). Also optionally an access token.
    .OUTPUTS
      Returns the Pure Storage array information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/18/2019
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
            [string]$objectName,
         
            [Parameter(Position=1)]
            [string]$objectId,

            [Parameter(Position=2)]
            [switch]$average,

            [Parameter(Position=3)]
            [switch]$maximum,

            [Parameter(Position=4,mandatory=$True)]
            [string]$metricName,

            [Parameter(Position=5)]
            [System.DateTime]$startTime,

            [Parameter(Position=6)]
            [System.DateTime]$endTime,

            [Parameter(Position=7)]
            [Int64]$granularity,

            [Parameter(Position=8)]
            [string]$pureOneToken
    )
    Begin{
        if (($average -eq $true) -and ($maximum -eq $true))
        {
            throw "Please only choose average or maximum, not both."
        }
        elseif (($average -eq $false) -and ($maximum -eq $false)) 
        {
            #defaulting to average if neither option is entered
            $average = $true
        }
        if (($objectName -eq "") -and ($objectId -eq ""))
        {
            throw "Please enter an object name or ID."
        }
        elseif (($objectName -ne "") -and ($objectId -ne ""))
        {
            throw "Please only enter an object name or an ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        #get metric rules
        $metricDetails = Get-PureOneMetricDetails -metricName $metricName
        #set granularity if not set
        if ($granularity -eq 0)
        {
            $granularity = $metricDetails.availabilities.resolution
        }

        #set end time to start time minus retention for that stat (if not entered) and convert to epoch time
        if ($endTime -eq $null)
        {
            $endTime = Get-Date
            $endTime = $endTime.ToUniversalTime()
        }
        else {
            $endTime = $endTime.ToUniversalTime()
        }
        [datetime]$epoch = '1970-01-01 00:00:00'
        $endEpoch = (New-TimeSpan -Start $epoch -End $endTime).TotalMilliSeconds
        $endEpoch = [math]::Round($endEpoch)

        #set start time to current time (if not entered) and convert to epoch time
        if ($startTime -eq $null)
        {
            $startTime = $epoch.AddMilliseconds($metricDetails._as_of - $metricDetails.availabilities.retention)
        }
        else {
            $startTime = $startTime.ToUniversalTime()
        }
        $startEpoch = (New-TimeSpan -Start $epoch -End $startTime).TotalMilliSeconds
        $startEpoch = [math]::Round($startEpoch)

        #building query
        if ($average -eq $true)
        {
            $restQuery = "?aggregation='avg'&end_time=$($endEpoch)&names=`'$($metricName)`'&resolution=$($granularity)&start_time=$($startEpoch)&"
        }
        else {
            $restQuery = "?aggregation='max'&end_time=$($endEpoch)&names=`'$($metricName)`'&resolution=$($granularity)&start_time=$($startEpoch)&"
        }
        if ($objectName -ne "")
        {
            $restQuery = $restQuery + "resource_names=`'$($objectName)`'"
        }
        else {
            $restQuery = $restQuery + "ids=`'$($objectId)`'"
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/metrics/history" + $restQuery
        $pureOneMetrics = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader 
    }
    End{
        return $pureOneMetrics.items
    }
}
function Get-PureOneVolumes {
    <#
    .SYNOPSIS
      Returns all Pure Storage volumes listed in your Pure1 account.
    .DESCRIPTION
      Returns all Pure Storage volumes listed in your Pure1 account. Allows for some filters.
    .INPUTS
      None required. Optional inputs are array type, array name, and Pure1 access token.
    .OUTPUTS
      Returns the Pure Storage array information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/18/2019
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
            [string]$arrayName,
            
            [Parameter(Position=1)]
            [string]$arrayId,

            [Parameter(Position=2)]
            [string]$volumeName,

            [Parameter(Position=3)]
            [string]$volumeSerial,

            [Parameter(Position=4)]
            [string]$pureOneToken
    )
    Begin{
        if (($volumeName -ne "") -and ($volumeSerial -ne ""))
        {
            throw "Please enter an volume name or a serial number."
        }
        if (($arrayName -ne "") -and ($arrayId -ne ""))
        {
            throw "Please enter an array name or an array ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($volumeName -ne "")
        {
            $restQuery = $restQuery + "names=`'$($volumeName)`'"
            if (($arrayName -ne "") -or ($arrayId -ne ""))
            {
                $restQuery = $restQuery + "&"
            }
        }
        elseif ($volumeSerial -ne "")
        {
            $volumeSerial = $volumeSerial.ToUpper()
            $restQuery = $restQuery +"filter=serial=`'$($volumeSerial)`'"
            if ($arrayName -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode(" and arrays[any].name")) + "=`'$($arrayName)`'"
            }
            if ($arrayId -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode(" and arrays[any].id")) + "=`'$($arrayId)`'"
            }
        }
        if ($volumeSerial -eq "")
        {
            if ($arrayName -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].name")) + "=`'$($arrayName)`'"
            }
            if ($arrayId -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].id")) + "=`'$($arrayId)`'"
            }
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/volumes" + $restQuery
        $pureVolumes = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader     
    }
    End{
        return $pureVolumes.items
    }
}
function Get-PureOnePods {
    <#
    .SYNOPSIS
      Returns all Pure Storage pods listed in your Pure1 account.
    .DESCRIPTION
      Returns all Pure Storage pods listed in your Pure1 account. Allows for some filters.
    .INPUTS
      None required. Optional inputs are pod name, array name or ID, and Pure1 access token.
    .OUTPUTS
      Returns the Pure Storage pod information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/18/2019
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
            [string]$arrayName,
            
            [Parameter(Position=1)]
            [string]$arrayId,

            [Parameter(Position=2)]
            [string]$podName,

            [Parameter(Position=3)]
            [string]$pureOneToken
    )
    Begin{
        if (($arrayName -ne "") -and ($arrayId -ne ""))
        {
            throw "Please enter an array name or an array ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($podName -ne "")
        {
            $restQuery = $restQuery + "names=`'$($podName)`'"
            if (($arrayName -ne "") -or ($arrayId -ne ""))
            {
                $restQuery = $restQuery + "&"
            }
        }
        if ($arrayName -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].name")) + "=`'$($arrayName)`'"
        }
        if ($arrayId -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].id")) + "=`'$($arrayId)`'"
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/pods" + $restQuery
        $purePods = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader     
    }
    End{
        return $purePods.items
    }
}
function Get-PureOneVolumeSnapshots {
    <#
    .SYNOPSIS
      Returns all Pure Storage volume snapshots listed in your Pure1 account.
    .DESCRIPTION
      Returns all Pure Storage volume snapshots listed in your Pure1 account. Allows for some filters.
    .INPUTS
      None required. Optional inputs are array type, array name, volume name, snapshot name or snapshot serial, or Pure1 access token.
    .OUTPUTS
      Returns the Pure Storage array information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/21/2019
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
            [string]$arrayName,
            
            [Parameter(Position=1)]
            [string]$arrayId,

            [Parameter(Position=2)]
            [string]$snapshotName,

            [Parameter(Position=3)]
            [string]$snapshotSerial,

            [Parameter(Position=4)]
            [string]$volumeName,

            [Parameter(Position=5)]
            [string]$pureOneToken
    )
    Begin{
        if (($snapshotName -ne "") -and ($snapshotSerial -ne ""))
        {
            throw "Please only enter a volume name or a serial number."
        }
        if (($arrayName -ne "") -and ($arrayId -ne ""))
        {
            throw "Please only enter an array name or an array ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($snapshotName -ne "")
        {
            $restQuery = $restQuery + "names=`'$($snapshotName)`'"
            if (($arrayName -ne "") -or ($arrayId -ne ""))
            {
                $restQuery = $restQuery + "&"
            }
        }
        elseif ($snapshotSerial -ne "")
        {
            $snapshotSerial = $snapshotSerial.ToUpper()
            $restQuery = $restQuery +"filter=serial=`'$($snapshotSerial)`'"
            if ($arrayName -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode(" and arrays[any].name")) + "=`'$($arrayName)`'"
            }
            if ($arrayId -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode(" and arrays[any].id")) + "=`'$($arrayId)`'"
            }
        }
        if ($snapshotSerial -eq "")
        {
            if ($arrayName -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].name")) + "=`'$($arrayName)`'"
            }
            if ($arrayId -ne "")
            {
                $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].id")) + "=`'$($arrayId)`'"
            }
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/volume-snapshots" + $restQuery
        $pureVolumes = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader   
        $pureVolumes = $pureVolumes.items  
        if ($volumeName -ne "")
        {
            $pureVolumes = $pureVolumes |Where-Object {$_.source.name -eq $volumeName}
        }
    }
    End{
        return $pureVolumes
    }
}
function Get-PureOneFileSystems {
    <#
    .SYNOPSIS
      Returns all Pure Storage file systems listed in your Pure1 account.
    .DESCRIPTION
      Returns all Pure Storage file systems  listed in your Pure1 account. Allows for some filters.
    .INPUTS
      None required. Optional inputs are array type, array name, file system name, or Pure1 access token.
    .OUTPUTS
      Returns the Pure Storage array information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/21/2019
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
            [string]$arrayName,
            
            [Parameter(Position=1)]
            [string]$arrayId,

            [Parameter(Position=2)]
            [string]$fsName,

            [Parameter(Position=3)]
            [string]$pureOneToken
    )
    Begin{
        if (($arrayName -ne "") -and ($arrayId -ne ""))
        {
            throw "Please enter an array name or an array ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($fsName -ne "")
        {
            $restQuery = $restQuery + "names=`'$($fsName)`'"
            if (($arrayName -ne "") -or ($arrayId -ne ""))
            {
                $restQuery = $restQuery + "&"
            }
        }
        if ($arrayName -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].name")) + "=`'$($arrayName)`'"
        }
        if ($arrayId -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].id")) + "=`'$($arrayId)`'"
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/file-systems" + $restQuery
        $pureFileSystems = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader     
    }
    End{
        return $pureFileSystems.items
    }
}
function Get-PureOneFileSystemSnapshots {
    <#
    .SYNOPSIS
      Returns all Pure Storage file system snapshots listed in your Pure1 account.
    .DESCRIPTION
      Returns all Pure Storage file system snapshots listed in your Pure1 account. Allows for some filters.
    .INPUTS
      None required. Optional inputs are array name, file system name, snapshot name, or Pure1 access token.
    .OUTPUTS
      Returns the Pure Storage file system(s) information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/21/2019
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
            [string]$arrayName,
            
            [Parameter(Position=1)]
            [string]$arrayId,

            [Parameter(Position=2)]
            [string]$snapshotName,

            [Parameter(Position=4)]
            [string]$fsName,

            [Parameter(Position=5)]
            [string]$pureOneToken
    )
    Begin{
        if (($arrayName -ne "") -and ($arrayId -ne ""))
        {
            throw "Please only enter an array name or an array ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        $restQuery = "?"
        if ($snapshotName -ne "")
        {
            $restQuery = $restQuery + "names=`'$($snapshotName)`'"
            if (($arrayName -ne "") -or ($arrayId -ne ""))
            {
                $restQuery = $restQuery + "&"
            }
        }
        if ($arrayName -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].name")) + "=`'$($arrayName)`'"
        }
        if ($arrayId -ne "")
        {
            $restQuery = $restQuery + ([System.Web.HttpUtility]::Urlencode("filter=arrays[any].id")) + "=`'$($arrayId)`'"
        }
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/file-system-snapshots" + $restQuery
        $pureSnapshots = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader   
        $pureSnapshots = $pureSnapshots.items  
        if ($fsName -ne "")
        {
            $pureSnapshots = $pureSnapshots |Where-Object {$_.source.name -eq $fsName}
        }
    }
    End{
        return $pureSnapshots
    }
}
function Get-PureOneArrayBusyMeter {
    <#
    .SYNOPSIS
      Returns the busy meter for a given array in Pure1
    .DESCRIPTION
      Returns the busy meter for a given array in Pure1, either an average or a maximum of a given time period. Default behavior is to return the average.
    .INPUTS
      Required: resource name or ID--must be an array. Optional: timeframe, granularity, and aggregation type (if none entered defaults will be used based on metric entered). Also optionally an access token.
    .OUTPUTS
      Returns the Pure Storage busy meter metric information in Pure1.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/18/2019
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
            [string]$objectName,
         
            [Parameter(Position=1)]
            [string]$objectId,

            [Parameter(Position=2)]
            [switch]$average,

            [Parameter(Position=3)]
            [switch]$maximum,

            [Parameter(Position=5)]
            [System.DateTime]$startTime,

            [Parameter(Position=6)]
            [System.DateTime]$endTime,

            [Parameter(Position=7)]
            [Int64]$granularity,

            [Parameter(Position=8)]
            [string]$pureOneToken
    )
    Begin{
        $metricName = "array_total_load"
        if (($average -eq $true) -and ($maximum -eq $true))
        {
            throw "Please only choose average or maximum, not both."
        }
        elseif (($average -eq $false) -and ($maximum -eq $false)) 
        {
            #defaulting to average if neither option is entered
            $average = $true
        }
        if (($objectName -eq "") -and ($objectId -eq ""))
        {
            throw "Please enter an object name or ID."
        }
        elseif (($objectName -ne "") -and ($objectId -ne ""))
        {
            throw "Please only enter an object name or an ID."
        }
        if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -ne ""))
        {
            throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
        }
        if ($null -eq $Global:pureOneRestHeader)
        {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        elseif (($null -ne $pureOneToken) -and ($pureOneToken -ne "")) {
            $pureOneHeader = @{authorization="Bearer $($pureOnetoken)"}
        }
        else {
            $pureOneHeader = $Global:pureOneRestHeader
        }
    }
    Process{
        #get metric rules
        $metricDetails = Get-PureOneMetricDetails -metricName $metricName
        #set granularity if not set
        if ($granularity -eq 0)
        {
            $granularity = $metricDetails.availabilities.resolution
        }

        #set end time to start time minus retention for that stat (if not entered) and convert to epoch time
        if ($endTime -eq $null)
        {
            $endTime = Get-Date
            $endTime = $endTime.ToUniversalTime()
        }
        else {
            $endTime = $endTime.ToUniversalTime()
        }
        [datetime]$epoch = '1970-01-01 00:00:00'
        $endEpoch = (New-TimeSpan -Start $epoch -End $endTime).TotalMilliSeconds
        $endEpoch = [math]::Round($endEpoch)

        #set start time to current time (if not entered) and convert to epoch time
        if ($startTime -eq $null)
        {
            $startTime = $epoch.AddMilliseconds($metricDetails._as_of - $metricDetails.availabilities.retention)
        }
        else {
            $startTime = $startTime.ToUniversalTime()
        }
        $startEpoch = (New-TimeSpan -Start $epoch -End $startTime).TotalMilliSeconds
        $startEpoch = [math]::Round($startEpoch)

        #building query
        if ($average -eq $true)
        {
            $restQuery = "?aggregation='avg'&end_time=$($endEpoch)&names=`'$($metricName)`'&resolution=$($granularity)&start_time=$($startEpoch)&"
        }
        else {
            $restQuery = "?aggregation='max'&end_time=$($endEpoch)&names=`'$($metricName)`'&resolution=$($granularity)&start_time=$($startEpoch)&"
        }
        if ($objectName -ne "")
        {
            $restQuery = $restQuery + "resource_names=`'$($objectName)`'"
        }
        else {
            $restQuery = $restQuery + "ids=`'$($objectId)`'"
        }
        
        $apiendpoint = "https://api.pure1.purestorage.com/api/1.0/metrics/history" + $restQuery
        $pureOneMetrics = Invoke-RestMethod -Method Get -Uri $apiendpoint -ContentType "application/json" -Headers $pureOneHeader 
    }
    End{
        return $pureOneMetrics.items
    }
}