$arrayID = Read-Host "Enter a FlashArray ID"
$md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
$utf8 = new-object -TypeName System.Text.UTF8Encoding
$hash = $md5.ComputeHash($utf8.GetBytes($arrayID))
$hash2 = $md5.ComputeHash(($hash))
$hash2[6] = $hash2[6] -band 0x0f
$hash2[6] = $hash2[6] -bor 0x30
$hash2[8] = $hash2[8] -band 0x3f
$hash2[8] = $hash2[8] -bor 0x80
$newGUID = (new-object -TypeName System.Guid -ArgumentList (,$hash2)).Guid
$fixedGUID = $newGUID.Substring(18)
$scId = $newGUID.Substring(6,2) + $newGUID.Substring(4,2) + $newGUID.Substring(2,2) + $newGUID.Substring(0,2) + "-" + $newGUID.Substring(11,2) + $newGUID.Substring(9,2) + "-" + $newGUID.Substring(16,2) + $newGUID.Substring(14,2) + $fixedGUID
$scId = $scId.Replace("-","")
$scId = "vvol:" + $scId.Insert(16,"-")
write-host $scId