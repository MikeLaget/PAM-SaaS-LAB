# Ensure the Active Directory module is imported
Import-Module ActiveDirectory

# This function verifies the admin credentials.
function Get-VerifiedAdminCredential {
    [CmdletBinding()]
    param(
        [string] $PromptMessage = "Domain Admin Credentials"
    )
    # Prompt for credentials
    Write-Host "Please enter credentials to continue."
    $cred = Get-Credential -Message $PromptMessage

    # Validate credentials
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $env:USERDNSDOMAIN)
    $username = $cred.UserName
    # Remove domain part if present (Domain\User)
    if($username -like "*\*") {
        $username = $username.Split("\")[1]
    }
    $password = $cred.GetNetworkCredential().Password
    $isValid = $context.ValidateCredentials($username, $password)
    $context.Dispose()  # free the PrincipalContext resource
    if(-not $isValid) {
        Stop-Transcript
        throw "Invalid admin credentials! Exiting."
    }
    Write-Host "Credentials validated. Continuing..."
    return $cred
}

# 3 & 4. Prompt and validate Domain Admin credentials
$AdminCred = Get-VerifiedAdminCredential -PromptMessage "Enter Domain Admin level credentials. For example,  acme\mike_da"
 #existingUser = Get-ADUser -Filter "SamAccountName -eq '$user'" -Credential $AdminCred -ErrorAction SilentlyContinue

# Prompt user for a mobile/cell number
$StudentMobile = Read-Host "Enter your Mobile/Cell number (e.g., +614xxxxxxxx)"

# Prompt user for an email address
$StudentEmail = Read-Host "Enter your email address (e.g., student@example.com)"

# Define users and assign the mobile number.
$users = @(
    @{ Name = "mike"},
    @{ Name = "carlos"},
    @{ Name = "cindy"},
    @{ Name = "tom"},
    @{ Name = "john"},
    @{ Name = "pamela"},
    @{ Name = "robert"},
    @{ Name = "paul"}
)

# Update mobile number for each user
foreach ($user in $users) {
    try {
        Set-ADUser -Identity $user.Name -MobilePhone $StudentMobile -Credential $AdminCred -ErrorAction SilentlyContinue
        Write-Host "Updated mobile number for $($user.Name) to $StudentMobile"
        Set-ADUser -Identity $user.Name -EmailAddress $StudentEmail -Credential $AdminCred -ErrorAction SilentlyContinue
        Write-Host "Updated email address for $($user.Name) to $StudentEmail"
    } catch {
        Write-Warning "Failed to update mobile number or email for $($user.Name): $_"
    }
}
# SIG # Begin signature block
# MIIesgYJKoZIhvcNAQcCoIIeozCCHp8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBZM/aYqhtz5RV2
# WZaqJoaSabYhOaCN0DWvljQYaHUlcaCCGNIwggWNMIIEdaADAgECAhAOmxiO+dAt
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOLnXSk4gxiVCpJ09fwa2RRVDRPc9b1y
# k26vR2m7/xRxMA0GCSqGSIb3DQEBAQUABIIBAI4pmJ1yDIg4Gfh9TnWnsUTKIY65
# MeeiG6jOYWCDh+snzPLdCIyrqWlVA/PJWZAZqT5lgl3zOKJik5mAWTAX3Atqh3wX
# Q8Amz3M7xlIKyuxVSS7OzArT2f1Z/Ca/iayJofQgwqzBOQfD628rQMqG3dao2+QS
# nmNGoXtzS1pyklB9efUOObViLbyKZhX5Bo8YTg9f92C35GfZ+tKnhLy0ULIOFnwQ
# QogZzKno9sCEoj4/6YpqCyLrLN7whipy4ciWpLE7Mlf625zY8Ibu4ckgL4vSQOui
# o/FmqfszomcEvEpwIvuphwsSdSX4ZuoLWDaxWO4nt58pBl8RXrVUxywwKKGhggMm
# MIIDIgYJKoZIhvcNAQkGMYIDEzCCAw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43x
# BYLRxHanlXRoMA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3
# DQEHATAcBgkqhkiG9w0BCQUxDxcNMjUxMjEwMDI0OTU2WjAvBgkqhkiG9w0BCQQx
# IgQgzvrZNva1twZAzhTVBf0HQMG3/e+Dp472AzAo4V+KH3YwDQYJKoZIhvcNAQEB
# BQAEggIAtULSZBVywr8mTSM+wD03umU7/seLIr+1rE3ZhYXmJUXpOGlObgu7gDG0
# NmnSLViNjzb3s0qXhpD9jnVDT32H/qbvsTDYdqzjhpgByemYNy4YgfTy2tr7Zg+t
# EZqa9YMhFD+94cGQk6XEiK1ErVI36U84CXpYZXXw0jfRL7ibl2qKn6/56tn5BJN4
# NQtfGL+QQtedLXDketAufGZokGYXEZX0vBZ6COx9qwzGh2pbmti7wKq+kVrZn18J
# tPKSqa8Jc2qSD26Fu87k5VV8tT6rhRvrDfeZCyo4EK69kDRXUQ4305IYcqVYObgB
# +VAevsbQEdj035NNCInR94mIHzO34zNiX8yTCJnE4w8nskzVEz1+MV6BEafqdxKz
# QFnrufq2UX+3gTu6hONQtQhXJRmNhtiHXU9mlXxybf1X0Pvo4L4fAZlW2qu7MnOB
# /ICenY1DMGr295O3DNmOUy3UGB5CC8Rr/IfkUppj7TRrgn9+m1sGU7eZkw+drW14
# ZHq4ngP6PGG0KzfGm+ePUCdnPY/YgXESSL3Ddfqh05kzYaSJWskILPACCwLILmhf
# VUIi5/85Nnvodw+GJIV+FBvDLvrDDSXa/ZOxHgYKnmmsRYs7aIF5ezFSCOZt2QSy
# Lj/tBph+9cXp9c14ZEkApiSfh/z34g8uG6W5pamG2BjPFS19BFg=
# SIG # End signature block
