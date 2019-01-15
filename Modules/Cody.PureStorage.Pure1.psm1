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
            [string]$pureOneToken,

            [Parameter(Position=1)]
            [string]$arrayName,

            [Parameter(Position=2)]
            [string]$arrayProduct,
            
            [Parameter(Position=3)]
            [string]$arrayId
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
        [Parameter(Position=0)]
        [string]$pureOneToken,

        [Parameter(Position=1,mandatory=$True)]
        [string]$resourceType,

        [Parameter(Position=2)]
        [string]$queryFilter,

        [Parameter(Position=3)]
        [string]$jsonBody,

        [Parameter(Position=4,mandatory=$True)]
        [string]$restOperationType

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
            [string]$pureOneToken,

            [Parameter(Position=1)]
            [string[]]$arrayNames,
         
            [Parameter(Position=2)]
            [string[]]$arrayIds,

            [Parameter(Position=3)]
            [string]$tagKey
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
            [string]$pureOneToken,

            [Parameter(Position=1)]
            [string[]]$arrayNames,
         
            [Parameter(Position=2)]
            [string[]]$arrayIds,

            [Parameter(Position=3,mandatory=$True)]
            [string]$tagKey,

            [Parameter(Position=4,mandatory=$True)]
            [string]$tagValue

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
