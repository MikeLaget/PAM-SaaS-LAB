Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$tzRegionLogonScriptFolder = "\\dc01\Distribution\TZRegion\"
$tzRegionLogonScript = "\\dc01\Distribution\TZRegion\config.ini"

Copy-Item .\Theme\TZRegionLogon.ps1 $tzRegionLogonScriptFolder
# --- Region definitions ---
$regions = @{
    "Australia (en-AU)" = @{
        SystemLocale = "en-AU"
        LanguageList = "en-AU"
        Culture = "en-AU"
        GeoId = 12
        TimeZone = "AUS Eastern Standard Time"
    }
    "United States (en-US)" = @{
        SystemLocale = "en-US"
        LanguageList = "en-US"
        Culture = "en-US"
        GeoId = 244
        TimeZone = "Pacific Standard Time"
    }
    "United Kingdom (en-GB)" = @{
        SystemLocale = "en-GB"
        LanguageList = "en-GB"
        Culture = "en-GB"
        GeoId = 242
        TimeZone = "GMT Standard Time"
    }
    "Default UTC (en-US)" = @{
        SystemLocale = "en-US"
        LanguageList = "en-US"
        Culture = "en-US"
        GeoId = 244
        TimeZone = "UTC"
    }
    "Singapore (en-SG)" = @{
        SystemLocale = "en-SG"
        LanguageList = "en-SG"
        Culture = "en-SG"
        GeoId = 224
        TimeZone = "Singapore Standard Time"
    }
    "Canada (en-CA)" = @{
        SystemLocale = "en-CA"
        LanguageList = "en-CA"
        Culture = "en-CA"
        GeoId = 39
        TimeZone = "Eastern Standard Time"
    }
    "New Zealand (en-NZ)" = @{
        SystemLocale = "en-NZ"
        LanguageList = "en-NZ"
        Culture = "en-NZ"
        GeoId = 20
        TimeZone = "New Zealand Standard Time"
    }
    "India (en-IN)" = @{
        SystemLocale = "en-IN"
        LanguageList = "en-IN"
        Culture = "en-IN"
        GeoId = 91
        TimeZone = "India Standard Time"
    }
    "Ireland (en-IE)" = @{
        SystemLocale = "en-IE"
        LanguageList = "en-IE"
        Culture = "en-IE"
        GeoId = 108
        TimeZone = "GMT Standard Time"
    }
    "South Africa (en-ZA)" = @{
        SystemLocale = "en-ZA"
        LanguageList = "en-ZA"
        Culture = "en-ZA"
        GeoId = 186
        TimeZone = "South Africa Standard Time"
    }
    "Philippines (en-PH)" = @{
        SystemLocale = "en-PH"
        LanguageList = "en-PH"
        Culture = "en-PH"
        GeoId = 183
        TimeZone = "Singapore Standard Time"
    }
    "Hong Kong (en-HK)" = @{
        SystemLocale = "en-HK"
        LanguageList = "en-HK"
        Culture = "en-HK"
        GeoId = 226
        TimeZone = "China Standard Time"
    }
    "Malaysia (en-MY)" = @{
        SystemLocale = "en-MY"
        LanguageList = "en-MY"
        Culture = "en-MY"
        GeoId = 173
        TimeZone = "Singapore Standard Time"
    }
}

# --- Timezone list with friendly display ---
$tzMap = @{}
[System.TimeZoneInfo]::GetSystemTimeZones() | ForEach-Object {
    $tzMap[$_.DisplayName] = $_.Id
}
$tzDisplayNames = $tzMap.Keys | Sort-Object

# --- Build GUI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Select Region and Timezone"
$form.Size = New-Object System.Drawing.Size(480,310)
$form.StartPosition = "CenterScreen"

# Region label & dropdown
$regionLabel = New-Object System.Windows.Forms.Label
$regionLabel.Text = "Select Region:"
$regionLabel.Location = New-Object System.Drawing.Point(20,20)
$regionLabel.AutoSize = $true

$regionDropdown = New-Object System.Windows.Forms.ComboBox
$regionDropdown.Location = New-Object System.Drawing.Point(20,45)
$regionDropdown.Size = New-Object System.Drawing.Size(390,30)
$regionDropdown.DropDownStyle = 'DropDownList'
#$regionDropdown.Items.AddRange($regions.Keys)
foreach ($regionName in $regions.Keys) {
    $regionDropdown.Items.Add($regionName)
}
$regionDropdown.SelectedItem = "United States (en-US)"  # Optional default

# Timezone label & dropdown
$timezoneLabel = New-Object System.Windows.Forms.Label
$timezoneLabel.Text = "Select Timezone:"
$timezoneLabel.Location = New-Object System.Drawing.Point(20,90)
$timezoneLabel.AutoSize = $true

$timezoneDropdown = New-Object System.Windows.Forms.ComboBox
$timezoneDropdown.Location = New-Object System.Drawing.Point(20,115)
$timezoneDropdown.Size = New-Object System.Drawing.Size(420,30)
$timezoneDropdown.DropDownStyle = 'DropDownList'
$timezoneDropdown.Items.AddRange($tzDisplayNames)
$timezoneDropdown.SelectedItem = "(UTC) Coordinated Universal Time"

# Apply to others label & dropdown
$remoteLabel = New-Object System.Windows.Forms.Label
$remoteLabel.Text = "Update logon script at $tzRegionLogonScript ?"
$remoteLabel.Location = New-Object System.Drawing.Point(20,160)
$remoteLabel.AutoSize = $true

$remoteDropdown = New-Object System.Windows.Forms.ComboBox
$remoteDropdown.Location = New-Object System.Drawing.Point(20,185)
$remoteDropdown.Size = New-Object System.Drawing.Size(420,30)
$remoteDropdown.DropDownStyle = 'DropDownList'
$remoteDropdown.Items.AddRange(@("No", "Yes"))
$remoteDropdown.SelectedItem = "Yes"

# Apply button
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Apply"
$applyButton.Location = New-Object System.Drawing.Point(180,230)
$applyButton.Size = New-Object System.Drawing.Size(100,30)

$applyButton.Add_Click({
    $selectedRegion = $regions[$regionDropdown.SelectedItem]
    $selectedTimezoneDisplay = $timezoneDropdown.SelectedItem
    $applyToOthers = $remoteDropdown.SelectedItem -eq "Yes"

    if (-not $selectedRegion -or -not $selectedTimezoneDisplay) {
        [System.Windows.Forms.MessageBox]::Show("Please select both region and timezone.","Missing Selection",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $selectedTimezoneId = $tzMap[$selectedTimezoneDisplay]

    try {
        Set-WinSystemLocale -SystemLocale $selectedRegion.SystemLocale
        Set-WinUserLanguageList -LanguageList @($selectedRegion.LanguageList) -Force
        Set-Culture -CultureInfo $selectedRegion.Culture
        Set-WinHomeLocation -GeoId $selectedRegion.GeoId
        Set-TimeZone -Id $selectedTimezoneId

        [System.Windows.Forms.MessageBox]::Show("Region and Timezone applied to local machine successfully.","Success",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)

        if ($applyToOthers) {
            [System.Windows.Forms.MessageBox]::Show("Updated logon script at $tzRegionLogonScript .","Success",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)

            
            $ScriptRunTime = Get-Date
$tzRegionlogonScriptContent = @"
# This logon ini was updated by the Update-TimeZone-Region script at $ScriptRunTime
[Settings]
WinSystemLocale = $($selectedRegion.SystemLocale)
WinUserLanguageList = $($selectedRegion.LanguageList)
Culture = $($selectedRegion.Culture)
WinHomeLocation = $($selectedRegion.GeoId)
TimeZone = $selectedTimezoneId
"@


Set-Content -Path $tzRegionLogonScript -Value $tzRegionlogonScriptContent -Force

        } else {
            [System.Windows.Forms.MessageBox]::Show("Apply to others Not Selected.","Success",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
        }

        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error applying settings:`n$_","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    }
})


# Add controls
$form.Controls.Add($regionLabel)
$form.Controls.Add($regionDropdown)
$form.Controls.Add($timezoneLabel)
$form.Controls.Add($timezoneDropdown)
$form.Controls.Add($remoteLabel)
$form.Controls.Add($remoteDropdown)
$form.Controls.Add($applyButton)

# Show GUI
$form.Topmost = $true
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
# SIG # Begin signature block
# MIIesgYJKoZIhvcNAQcCoIIeozCCHp8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBDth6Wck1SnYjj
# W/MJuDCh/44hrHpnFHdLoPYN4NQa16CCGNIwggWNMIIEdaADAgECAhAOmxiO+dAt
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFyHO3vmYhfAiY8nXmvDS/6VLW672QDi
# /IbZxdHuBjbLMA0GCSqGSIb3DQEBAQUABIIBABCRgQ5w5wYv+aBMbLGbpxb9R2y0
# aMmDCmiOSqVhzsZEnlJrNLNGOdLQOBgaY8Uave3wxg3yPNeF5cGhaITuRtm0YYJT
# 2dsQY8RRa+L9GZ2MTR9KPpug0euYAEC15Ir6IF2eZv/JopUwRZUnbJhx8SlIl5xn
# NTGP2ykinnDzIzgNwTBXQj1pGxfuE+6uxF5TCaTQib93Fs34as1AwiN8kEMjZR+g
# d06S3CT00q6tPONO3vaUkOzSm3NDsuUgAcQY+/8qTwX9vuc2gFYGt+l6ddbByONt
# vEhMP4jfQARr+6MUdoexPzz+yMZTTliO4NLPvkbK3YZJtFd1RDy0ZxYFusahggMm
# MIIDIgYJKoZIhvcNAQkGMYIDEzCCAw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43x
# BYLRxHanlXRoMA0GCWCGSAFlAwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3
# DQEHATAcBgkqhkiG9w0BCQUxDxcNMjUxMjEwMDI0OTU2WjAvBgkqhkiG9w0BCQQx
# IgQgjNwUVUGbGYsdnPwuauXTXGPQ2SsdX2Kp5DnYSLrAy90wDQYJKoZIhvcNAQEB
# BQAEggIAjyDRqvHVpjr0NNjCW3/GQzISz1hmqKLSNHifKWfofej4Ay1Qu+9HHopy
# JhqexRpS5LQlnHqDqKRfDwXj/HLl6Q95w7anGeGcPoKf/kzZmVlDLXDr3vaUUBU2
# 5xIfhSh0flIkEfsylcH+AaNuojFUeJLoGIg3KHlrzORuBXTLNV5yMBUSbxfvtc98
# G0voy7g8qQRdZHdRGsCUbbY1OKYAFT0fVDMbtMkJWQHui5eEg6RLrdmlpXOGDk6W
# XQg0d9LV/cz50WGLxQLi3hzTRtrQPoQAFq0kLV424A+Bj7aQyZYd0qTzQKBFvduz
# yU0p76tqSfIoFcNwMBDizQMbE4ikv86BP1WigoZmwjCzaI2ULYrxsWDywnc68772
# IhMK3RxbU1uA5sauxikD4SVyNDYAne4OQkR7NRYCsGlHAmAHrFuTLvrb7+12qUZM
# NxcuHIrTSQz83UPlgS9oXiWqSxJgZinfoyjUSy3NWFW0ez+dnT1Gen/gjMk4igQQ
# MuJWBa/YIEy6lbjsEHAyWKNlIHpt9xoHZQXraNp8iqjmDwLgVhx/uLBOyrBm+lxx
# cIbH6mT0Xbw+FHHWmIlv4U+1DBmEU01ltahQ0zrfRgFzSJtYh1yd2Yt2FKPjQKj0
# be+lhGTQss5Hc2STBfPectT+PTi/htPjGI+5omEdRZVAb+gR030=
# SIG # End signature block
