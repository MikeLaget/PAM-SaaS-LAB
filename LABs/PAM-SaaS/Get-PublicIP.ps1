# 1) SkyTap IP ranges (as provided)
$SkyTapRanges = @(
    @{ Region = 'APAC-2';            CIDR = '45.120.106.48/29' }
    @{ Region = 'AU-Sydney-M-1';     CIDR = '20.53.232.34/31' }
    @{ Region = 'AU-Sydney-M-2';     CIDR = '13.70.104.148/31' }
    @{ Region = 'CAN-Toronto';       CIDR = '184.170.236.48/29' }
    @{ Region = 'CN-HongKong-M-1';   CIDR = '168.63.206.24/31' }
    @{ Region = 'EMEA';              CIDR = '185.64.245.48/29' }
    @{ Region = 'IE-Dublin-M-1';     CIDR = '13.69.157.38/31' }
    @{ Region = 'IN-Pune-M-1';       CIDR = '104.211.92.36/31' }
    @{ Region = 'JP-Tokyo-M-1';      CIDR = '13.78.15.0/31' }
    @{ Region = 'NL-Amsterdam-M-1';  CIDR = '20.54.198.188/31' }
    @{ Region = 'SG-Singapore-M-1';  CIDR = '20.197.80.234/31' }
    @{ Region = 'UK-London-M-1';     CIDR = '51.132.32.200/31' }
    @{ Region = 'UK-London-M-2';     CIDR = '20.108.161.156/31' }
    @{ Region = 'US-Central';        CIDR = '184.170.232.48/29' }
    @{ Region = 'US-East-2';         CIDR = '206.198.150.48/29' }
    @{ Region = 'US-Texas-M-1';      CIDR = '20.189.26.100/31' }
    @{ Region = 'US-Virginia-M-1';   CIDR = '206.198.148.48/29' }
    @{ Region = 'US-Virginia-M-2';   CIDR = '104.211.56.166/31' }
    @{ Region = 'US-West';           CIDR = '199.204.216.104/29' }
)

# 2) IPv4 -> UInt32
function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory)][string]$IPv4)
    try {
        $bytes = [System.Net.IPAddress]::Parse($IPv4).GetAddressBytes()
    } catch {
        throw "Invalid IPv4 address: $IPv4"
    }
    if ($bytes.Length -ne 4) { throw "Invalid IPv4 address: $IPv4" }
    return ([uint32]$bytes[0] -shl 24) -bor
           ([uint32]$bytes[1] -shl 16) -bor
           ([uint32]$bytes[2] -shl 8)  -bor
           ([uint32]$bytes[3])
}

# 3) Compute network start/end using block size and modulo
function Get-CIDRRange {
    param([Parameter(Mandatory)][string]$CIDR)
    $parts = $CIDR.Split('/')
    if ($parts.Count -ne 2) { throw "Invalid CIDR: $CIDR" }

    $baseIP  = $parts[0]
    $prefix  = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) { throw "Invalid prefix in CIDR: $CIDR" }

    $baseUInt  = Convert-IPv4ToUInt32 $baseIP
    $hostBits  = 32 - $prefix
    # Block size (# of addresses in the CIDR)
    $blockSize = [uint64](1) -shl $hostBits  # works well for /29 and /31

    # Use UInt64 math to avoid signed issues, then cast back
    $base64       = [uint64]$baseUInt
    $networkBase  = [uint32]($base64 - ($base64 % $blockSize))
    $broadcast    = [uint32]([uint64]$networkBase + ($blockSize - 1))

    [pscustomobject]@{
        CIDR              = $CIDR
        BaseIP            = $baseIP
        Prefix            = $prefix
        NetworkAddressUInt = $networkBase
        BroadcastAddressUInt = $broadcast
    }
}

# 4) Membership test
function Test-IPv4InCIDR {
    param(
        [Parameter(Mandatory)][string]$IPv4,
        [Parameter(Mandatory)][string]$CIDR
    )
    $ipUInt   = Convert-IPv4ToUInt32 $IPv4
    $range    = Get-CIDRRange $CIDR
    return ($ipUInt -ge $range.NetworkAddressUInt -and $ipUInt -le $range.BroadcastAddressUInt)
}

# 5) Discover public IP with multiple fallbacks
function Get-PublicIPv4 {
    $endpoints = @(
        'https://api.ipify.org',
        'https://ifconfig.me/ip',
        'https://ipinfo.io/ip'
    )
    foreach ($url in $endpoints) {
        try {
            $ip = (Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10).Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { return $ip }
        } catch { continue }
    }
    throw "Unable to determine public IPv4 address. Check internet connectivity or proxy settings."
}

# 6) Main
try {
    $publicIP = Get-PublicIPv4
    Write-Host "Detected public IPv4: $publicIP" -ForegroundColor Cyan

    $matches = foreach ($r in $SkyTapRanges) {
        if (Test-IPv4InCIDR -IPv4 $publicIP -CIDR $r.CIDR) {
            [pscustomobject]@{ Region = $r.Region; CIDR = $r.CIDR }
        }
    }

    if ($matches) {
        Write-Host "`nAdd the following IP range(s) in your PAM SaaS IP allow list :" -ForegroundColor Green
        $matches | Format-Table -AutoSize
    } else {
        Write-Warning "`nNo direct match found in the provided SkyTap ranges."
        Write-Host "Reference ranges:" -ForegroundColor Yellow
        $SkyTapRanges | Format-Table Region, CIDR -AutoSize
    }
}
catch {
    Write-Error $_.Exception.Message
    Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
    Write-Host " - Ensure outbound internet access is available from this VM."
    Write-Host " - If behind a proxy, configure PowerShell to use it (e.g., `$env:HTTPS_PROXY`)."
    Write-Host " - Try again, or manually compare your IP with the ranges."
}
# SIG # Begin signature block
# MIIesgYJKoZIhvcNAQcCoIIeozCCHp8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDIids44ysSN9ZI
# JXoO6LArT5IJPCdVKcgpfpnE+Vq+AqCCGNIwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwggWUMIIEfKADAgECAhN+AAAAXDZdcRsjYYagAAAAAABcMA0G
# CSqGSIb3DQEBCwUAMEMxFDASBgoJkiaJk/IsZAEZFgRjb3JwMRQwEgYKCZImiZPy
# LGQBGRYEYWNtZTEVMBMGA1UEAxMMYWNtZS1EQzAxLUNBMB4XDTI1MTIwMjAwMjMx
# M1oXDTI3MTIwMjAwMzMxM1owHDEaMBgGA1UEAxMRQUNNRSBDb2RlIFNpZ25pbmcw
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCnLugVsShtFlWxMIG5oXDE
# MqxHubR0iEHbNO8PjltukjK4hoOJZv2IzY3D9o7KcNo6nV1Tovj9GertL2FDFSoz
# 7iMoQKDr0uKzkCxqQ5jBSAhV/dtht78zfcP/rlJbYO9POvP5LUkpJ8T1miflziJc
# LmaaJ+j3BIimVxKeMnkPw853BM6HflQDdMggDJaqJD+dahkV8ORiTz5LpuKuXkqr
# /ULHaQwLB5QtJpxW+ExVOhLfaTjji4DwlLs8zJCg8dbM0KK/p1EU/bXJDg/kIBsi
# gYwFYOIc3WRQNRTJpvR/r0WqtQ99yxyHimPVwXOSkwm4xem9WWZl0Lf3WlKEKOoN
# AgMBAAGjggKmMIICojA9BgkrBgEEAYI3FQcEMDAuBiYrBgEEAYI3FQiDwJNuhsfy
# Q4XhkxmEnNw4g7q/UyeFzf4PhKaTOQIBZAIBCjATBgNVHSUEDDAKBggrBgEFBQcD
# AzAOBgNVHQ8BAf8EBAMCBsAwGwYJKwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzAd
# BgNVHQ4EFgQUpXEcaXx/IwMLhrAgV4y9z02JWp4wHwYDVR0jBBgwFoAUZ3ws+ydv
# UBVN4Sd3zC+8tvMpl3EwgfcGA1UdHwSB7zCB7DCB6aCB5qCB44aBrmxkYXA6Ly8v
# Q049YWNtZS1EQzAxLUNBLENOPWRjMDEsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUy
# MFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9YWNtZSxE
# Qz1jb3JwP2NlcnRpZmljYXRlUmV2b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFz
# cz1jUkxEaXN0cmlidXRpb25Qb2ludIYwaHR0cDovL2NybC5hY21lLmNvcnAvQ2Vy
# dEVucm9sbC9hY21lLURDMDEtQ0EuY3JsMIHkBggrBgEFBQcBAQSB1zCB1DCBqQYI
# KwYBBQUHMAKGgZxsZGFwOi8vL0NOPWFjbWUtREMwMS1DQSxDTj1BSUEsQ049UHVi
# bGljJTIwS2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlv
# bixEQz1hY21lLERDPWNvcnA/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNz
# PWNlcnRpZmljYXRpb25BdXRob3JpdHkwJgYIKwYBBQUHMAGGGmh0dHA6Ly9vY3Nw
# LmFjbWUuY29ycC9vY3NwMA0GCSqGSIb3DQEBCwUAA4IBAQCF2946OzdjjVLqxh6T
# XobgpbkPafR2GaL84BWhvSjS3FpfIlCpVUjRRxIDraG2N3GsMAIuz8AbBsl77aIX
# rnSKibQ6Gudgt2JumHOml+hHkvv/wBZSxlDjKBK3uD2G8LHpwvsVFJDXYwMdrJiF
# teJzsWKWcPYsNw3ruR3F9pzleK6dzWXYZd9RwIb1BHo3pvgq8tJvbZhVST+hQRiE
# fdrD4GX/T5gZMXyBgBlTb+jS3F+KrV8rgybCCLjb88xDPMEn1rP+9NUoCZRI6DcN
# LEK1UuKbScTAgZN4qCaUKKSW/axnvRpamaCktj550pXpicNse97f5rpgzzuAJ04B
# TEVrMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjANBgkqhkiG9w0BAQsF
# ADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQL
# ExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJv
# b3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5WjBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0Ex
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx0wqYQXK+PEbAHKx1
# 26NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz4aH+qbxeLho8I6jY
# 3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJgMQB3h2DZ0Mal5kY
# p77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQbzIBHYJBYgzWIjk8
# eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6bNMI1I7Gb5IBZK4i
# vbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJRfN20VRS3hpLgIR4
# hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU14lDnki7CcoKCz6eu
# m5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDDjAmSFTUms+wV/FbW
# Bqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cnT6Toy+rN+nM8M7Ln
# LqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq1BtmXUqEG1NqzJKS
# 4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqgPrHRVHhGNKlYzyjl
# roPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8GA1UdIwQYMBaAFOzX
# 44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggr
# BgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDag
# NIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RH
# NC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3
# DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfFiBowf0/Dm1wGc/Do
# 7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4/iEIUBO41P5F448r
# SYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/DMm/axFSgoR8n6c3
# nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HRtrYfctSLANEBfHU1
# 6r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2o1f4MXRJDMdTSlOL
# h0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K9i697cvaiIo2p61E
# d2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc3hsXMrS+U0yy+GWq
# AXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLiRu7hAWE6bTEm4XYR
# kA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAvjSabnf7+Pu0VrFgo
# iovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3JE3rYkrhLULy7Dc90
# G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM1pD2T7m3XDCCBu0w
# ggTVoAMCAQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJKoZIhvcNAQELBQAwaTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdp
# Q2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1
# IENBMTAeFw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMyMzU5NTlaMGMxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQg
# U0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAyMDI1IDEwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDQRqwtEsae0OquYFazK1e6b1H/hnAK
# Ad/KN8wZQjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjni6bz52fGTfr6PHRNv6T7zsf1
# Y/E3IU8kgNkeECqVQ+3bzWYesFtkepErvUSbf+EIYLkrLKd6qJnuzK8Vcn0DvbDM
# emQFoxQ2Dsw4vEjoT1FpS54dNApZfKY61HAldytxNM89PZXUP/5wWWURK+IfxiOg
# 8W9lKMqzdIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ0/fKJLKLkzGBTpx6EYevvOi7
# XOc4zyh1uSqgr6UnbksIcFJqLbkIXIPbcNmA98Oskkkrvt6lPAw/p4oDSRZreiwB
# 7x9ykrjS6GS3NR39iTTFS+ENTqW8m6THuOmHHjQNC3zbJ6nJ6SXiLSvw4Smz8U07
# hqF+8CTXaETkVWz0dVVZw7knh1WZXOLHgDvundrAtuvz0D3T+dYaNcwafsVCGZKU
# hQPL1naFKBy1p6llN3QgshRta6Eq4B40h5avMcpi54wm0i2ePZD5pPIssoszQyF4
# //3DoK2O65Uck5Wggn8O2klETsJ7u8xEehGifgJYi+6I03UuT1j7FnrqVrOzaQoV
# JOeeStPeldYRNMmSF3voIgMFtNGh86w3ISHNm0IaadCKCkUe2LnwJKa8TIlwCUNV
# wppwn4D3/Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQU
# 5Dv88jHt/f3X85FxYxlQQ89hjOgwHwYDVR0jBBgwFoAU729TSunkBnx6yuKQVvYv
# 1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGV
# BggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNB
# MS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVD
# QTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG
# 9w0BAQsFAAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNAciH45PYiT9s1i6UKtW+FERp8
# FgXRGQ/YAavXzWjZhY+hIfP2JkQ38U+wtJPBVBajYfrbIYG+Dui4I4PCvHpQuPqF
# gqp1PzC/ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5qjzvZs7JIIgt0GCFD9ktx0Lx
# xtRQ7vllKluHWiKk6FxRPyUPxAAYH2Vy1lNM4kzekd8oEARzFAWgeW3az2xejEWL
# NN4eKGxDJ8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr15zW/mJAxZMVBrTE2oi0fcI8
# VMbtoRAmaaslNXdCG1+lqvP4FbrQ6IwSBXkZagHLhFU9HCrG/syTRLLhAezu/3Lr
# 00GrJzPQFnCEH1Y58678IgmfORBPC1JKkYaEt2OdDh4GmO0/5cHelAK2/gTlQJIN
# qDr6JfwyYHXSd+V08X1JUPvB4ILfJdmL+66Gp3CSBXG6IwXMZUXBhtCyIaehr0Xk
# BoDIGMUG1dUtwq1qmcwbdUfcSYCn+OwncVUXf53VJUNOaMWMts0VlRYxe5nK+At+
# DI96HAlXHAL5SlfYxJ7La54i71McVWRP66bW+yERNpbJCjyCYG2j+bdpxo/1Cy4u
# PcU3AWVPGrbn5PhDBf3Froguzzhk++ami+r3Qrx5bIbY3TVzgiFI7Gq3zWcxggU2
# MIIFMgIBATBaMEMxFDASBgoJkiaJk/IsZAEZFgRjb3JwMRQwEgYKCZImiZPyLGQB
# GRYEYWNtZTEVMBMGA1UEAxMMYWNtZS1EQzAxLUNBAhN+AAAAXDZdcRsjYYagAAAA
# AABcMA0GCWCGSAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIEJkchx97m9O9pAb8prP2LrS7ecfOIIB
# lCtDNgnG5VhbMA0GCSqGSIb3DQEBAQUABIIBAFy7ISOf90EetB/Nbkkq1U137sfA
# OKUr6SbGLglKVf6zhPSahsNF6kA+DxBgR3qsLCokW8PYvE4GaASyorJmJTTD5nEV
# Lu1pBkCqTTmsPqc3Ire9RN7cMdXDyZVuSQ4PDjji4JiO77aId5QeZtVuvjJCbuk5
# T3GFY7G9AL19mJ6L6pATX+gdfy+EZSWagOTadGtoNDQ60ItZ+sIDzERrJ1AL06jk
# IkKkBTK8UdLprV1qONfUouRqFEh7ZorC9wVvbaifAjTpuACmfmgJPQuU7KOOcM8W
# HrfZwWVcXJqO4/qfhbhMF+nLtGtydgWd4b4breIAIWqh3I6LYLhMUUeA0lahggMm
# MIIDIgYJKoZIhvcNAQkGMYIDEzCCAw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43x
# BYLRxHanlXRoMA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3
# DQEHATAcBgkqhkiG9w0BCQUxDxcNMjYwMzE4MDExMjAwWjAvBgkqhkiG9w0BCQQx
# IgQgj/96HFz0KVGIOJplrXvVmwY2xcmBlj9rGug0DVXPABgwDQYJKoZIhvcNAQEB
# BQAEggIAKbP/JCBzTDeLIQhN7j8h+8a+aJNIj9w/q4Bj0iGAoNYBE3WzQPzF2JH2
# Ifzvq9m2wuD4jLmrkyNyAUawIpYJnQdr0hX4cSpHLiwrtLBVqfmxVZ1NhsBeS++1
# cUSOFVOphWjsSOEuLNhrkAILLErL53XqAH6cF29M30JukgFm4TLUDxsfVxe6B28Y
# oTSVEdWip0fMxIYRZ3MpPKW7ZYE/HwZRsX7RdPnD2gVBEXahrkjinxpfILTp3g4/
# xS7/nmIdRXcoAYxhD1esXfipsQLsM3ve+HI3DyR1jnpyySG8w3cmTbE7kP+PVJor
# OksKy0OGcAEEwxhiWYTjH94V20SJP05mkcpGPLpKC9k+B0Ofupq+6tezG5cYF1AR
# vP2V+sm9FCv/aowtTQdLZ/bBVphTGWIbo6XMbQ7EHi3KQ0hpN497uVZ/Sv4KUCiC
# r6/sgcZcJH8It+V3vrmKc0THrvlLxmrkcQnget6SlKzE2HONd8ivswMzyRRfwooF
# 4Lo/g3l3cPSvqLVwJLIY1OsgfTGso3bK+7QmeCTPXaEioyd1mO/LRGE5DKWI5Ydr
# cXtASic+d646EK+7EqmP5/JOr7zovpXJTp6QEVsi492ihx/FU6fOrcIFZa+M9QP4
# ZNrrHZXEzyoqr8jcveNvdzWPqRTuugLSdvtGAENFc7hXng5vce8=
# SIG # End signature block
