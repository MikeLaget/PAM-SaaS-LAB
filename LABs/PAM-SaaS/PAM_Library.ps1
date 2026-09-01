<#
.SYNOPSIS
Overview for Students:
In software development, writing the same code multiple times is considered bad practice. This file is a Function Library (a module). It contains all the complex, reusable logic that our actual automation scripts will need. By separating this logic from the main scripts, we make our main scripts much easier to read and maintain.

Key Learning Concepts in this Script:

Modular Code (DRY Principle): "Don't Repeat Yourself." Functions like Write-Log or Get-IdentityToken are written once here, but can be called by any other script.
Advanced API Authentication: Look at Get-IdentityToken. It demonstrates how to handle a multi-step API login: submitting a password, dynamically finding out if Multi-Factor Authentication (MFA) is required, prompting the user to pick an MFA method (Email/SMS), and polling the server until the user approves the prompt on their phone.
Idempotency & Error Handling: The PAM Safe functions (New-PAMSafes, Add-PAMSafeMembers) use try/catch blocks. If they detect a 409 Conflict (meaning the Safe or Member already exists), they don't crash. Instead, they gracefully check if the existing permissions are correct and move on.
Security Best Practices: The Revoke-IdentityToken function shows how to properly destroy a session token so it cannot be hijacked after the script finishes.
v26-09-01
#>

# ==============================================================================
# LOGGING & ERROR HANDLING
# ==============================================================================
function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "SUCCESS")][string]$Level = "INFO"
    )

    if ($Level -eq "DEBUG" -and -not $global:EnableDebugMode) { return }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"    { Write-Host $LogLine -ForegroundColor Cyan }
        "SUCCESS" { Write-Host $LogLine -ForegroundColor Green }
        "WARN"    { Write-Host $LogLine -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogLine -ForegroundColor Red }
        "DEBUG"   { Write-Host $LogLine -ForegroundColor Gray }
    }

    if ($global:EnableFileLogging -and $global:LogFilePath) {
        try { Add-Content -Path $global:LogFilePath -Value $LogLine -ErrorAction Stop } catch {}
    }
}

function Get-ApiErrorMessage {
    param ($ExceptionRecord)
    if ($null -ne $ExceptionRecord.ErrorDetails) {
        return $ExceptionRecord.ErrorDetails.Message
    } elseif ($null -ne $ExceptionRecord.Exception.Response) {
        if ($ExceptionRecord.Exception.Response.GetType().Name -eq "HttpWebResponse") {
            $reader = New-Object System.IO.StreamReader($ExceptionRecord.Exception.Response.GetResponseStream())
            return $reader.ReadToEnd()
        }
    }
    return $ExceptionRecord.Exception.Message
}

# ==============================================================================
# UTILITIES
# ==============================================================================
function Get-RandomPassword {
    [CmdletBinding()]
    Param([int]$Length = 20)

    $Upper   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    $Lower   = "abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $Numbers = "0123456789".ToCharArray()
    $Special = "!#$%&*?".ToCharArray()

    $Base = @($Upper | Get-Random), @($Lower | Get-Random), @($Numbers | Get-Random), @($Special | Get-Random)
    $Pool = $Upper + $Lower + $Numbers + $Special
    $Base += 1..($Length - 4) | ForEach-Object { $Pool | Get-Random }

    return ($Base | Get-Random -Count $Length) -join ""
}

function Get-IdentityURL($idURL) {
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object System.Net.Http.HttpClient($handler)

    try {
        $task = $client.GetAsync($idURL)
        $task.Wait()

        if ($task.IsCompleted) {
            $response = $task.Result
            if (($response.StatusCode -ge 300 -and $response.StatusCode -lt 400) -or ($response.StatusCode -eq "OK")) {
                return $response.RequestMessage.RequestUri.Host
            } else {
                return "Unexpected status code: $($response.StatusCode)"
            }
        } else {
            return "Task did not complete successfully."
        }
    } catch {
        $exception = $_.Exception
        while ($exception.InnerException) { $exception = $exception.InnerException }
        return "Error: $($exception.Message)"
    } finally {
        if ($null -ne $client) { $client.Dispose() }
    }
}

function Get-TenantAdminInfo {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $filePath = Join-Path -Path $desktopPath -ChildPath "tenantadmin.csv"

    while (-not (Test-Path -Path $filePath)) {
        Write-Log "File 'tenantadmin.csv' was NOT found on the Desktop." -Level WARN
        $retry = Read-Host "Press 'Y' to check again, or any other key to exit"
        if ($retry -notmatch '^[Yy]$') { exit }
    }

    $csvData = Import-Csv -Path $filePath -Delimiter ','
    foreach ($row in $csvData) {
        switch ($row.Field) {
            'PAM_SaaS_Url' { $global:PAM_SaaS_Url = $row.Value }
            'Identity_Url' { $global:Identity_Url = $row.Value }
            'Login'        { $global:AuthUser = $row.Value }
        }
    }

    if ($global:PAM_SaaS_Url -and $global:Identity_Url -and $global:AuthUser) {
        Write-Log "Loaded config: PAM_Url=$global:PAM_SaaS_Url | Identity=$global:Identity_Url | User=$global:AuthUser" -Level INFO
    } else {
        Write-Log "CSV is missing required values." -Level ERROR
        exit
    }
}

# ==============================================================================
# AUTHENTICATION
# ==============================================================================
function Get-IdentityToken {
    param ([string]$Identity_Url, [string]$UserEmail)
    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    $global:BaseHeaders = @{ "X-Idap-Native-Client" = "true" }
    $IdentityID = ($Identity_Url -replace "https://", "").Split(".")[0]

    Write-Log "Authenticating to Idira Platform ($UserEmail)" -Level INFO
    $passwordMatch = $false

    while (-not $passwordMatch) {
        $pwd1 = Read-Host "Enter the password for $UserEmail" -AsSecureString
        $pwd2 = Read-Host "Confirm the password for $UserEmail" -AsSecureString
        $PlainPassword1 = [System.Net.NetworkCredential]::new("", $pwd1).Password
        $PlainPassword2 = [System.Net.NetworkCredential]::new("", $pwd2).Password

        if ($PlainPassword1 -ceq $PlainPassword2 -and -not [string]::IsNullOrWhiteSpace($PlainPassword1)) { 
            $passwordMatch = $true 
        } else { 
            Write-Log "Passwords do not match or are blank. Please try again." -Level ERROR 
        }
    }

    try {
        $bodyStart = @{ TenantId = $IdentityID; Version = "1.0"; User = $UserEmail } | ConvertTo-Json -Compress
        $resStart = Invoke-RestMethod -Uri "$Identity_Url/Security/StartAuthentication" -Headers $global:BaseHeaders -Body $bodyStart @RestArgs

        if (-not $resStart.Success -or $null -eq $resStart.Result.Challenges) { throw "API returned Success=$false or no challenges." }

        $SessionId = $resStart.Result.SessionId
        $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms | Where-Object { $_.Name -match "Password" } | Select-Object -ExpandProperty MechanismId
        if (-not $MechanismId_Pwd) { $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms[0].MechanismId }

        Write-Log "Submitting password..." -Level INFO
        $bodyPwd = @{ TenantId = $IdentityID; SessionId = $SessionId; MechanismId = $MechanismId_Pwd; Action = "Answer"; Answer = $PlainPassword1 } | ConvertTo-Json -Compress
        $resPwd = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $global:BaseHeaders -Body $bodyPwd @RestArgs

        if (-not $resPwd.Success -or $resPwd.Result.Summary -eq "LoginFailed") { throw "Incorrect password or login failed." }
        if ($resPwd.Result.Summary -eq "NewPasswordRequired") { throw "User must change their password before API authentication." }

        if ($resPwd.Result.Summary -eq "LoginSuccess") {
            $global:UToken = $resPwd.Result.Token
        } else {
            $mfaChallenge = if ($resPwd.Result.Challenges) { $resPwd.Result.Challenges[0] } else { $resStart.Result.Challenges[1] }
            $mfaOptions = $mfaChallenge.Mechanisms | Where-Object { $_.Name -match "Email" -or $_.Name -match "SMS" }
            $MechanismId_Mfa = $null

            if ($mfaOptions.Count -gt 1) {
                Write-Host "`nMultiple MFA methods detected. Please select one:" -ForegroundColor Cyan
                for ($i = 0; $i -lt $mfaOptions.Count; $i++) {
                    Write-Host "[$($i + 1)] $($mfaOptions[$i].Name)" -ForegroundColor White
                }

                [int]$selection = 0
                while ($selection -lt 1 -or $selection -gt $mfaOptions.Count) {
                    $inputStr = Read-Host "Select your preferred MFA method (1-$($mfaOptions.Count))"
                    if ([int]::TryParse($inputStr, [ref]$selection) -and $selection -ge 1 -and $selection -le $mfaOptions.Count) { break }
                    Write-Host "Invalid selection. Try again." -ForegroundColor Red
                }
                $MechanismId_Mfa = $mfaOptions[$selection - 1].MechanismId
                Write-Log "Selected MFA method: $($mfaOptions[$selection - 1].Name)" -Level INFO
            } elseif ($mfaOptions.Count -eq 1) {
                $MechanismId_Mfa = $mfaOptions[0].MechanismId
                Write-Log "Auto-selected only available Email/SMS MFA method: $($mfaOptions[0].Name)" -Level INFO
            } else {
                $MechanismId_Mfa = $mfaChallenge.Mechanisms[0].MechanismId
                Write-Log "No Email or SMS mechanisms found. Falling back to default: $($mfaChallenge.Mechanisms[0].Name)" -Level WARN
            }

            $bodyMfa = @{ TenantID = $IdentityID; SessionId = $SessionId; MechanismId = $MechanismId_Mfa; Action = "StartOOB" } | ConvertTo-Json -Compress
            $resMfa = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $global:BaseHeaders -Body $bodyMfa @RestArgs

            Write-Log "MFA challenge sent. Waiting for approval..." -Level WARN
            $pollResponse = $resMfa

            while ($pollResponse.Result.Summary -in @("OobPending", "PendingOOB", "Pending")) {
                Start-Sleep -Seconds 3
                $pollBody = @{ TenantID = $IdentityID; SessionId = $SessionId; MechanismId = $MechanismId_Mfa; Action = "Poll" } | ConvertTo-Json -Compress
                $pollResponse = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $global:BaseHeaders -Body $pollBody @RestArgs
            }

            if ($pollResponse.Result.Summary -eq "LoginSuccess") { $global:UToken = $pollResponse.Result.Token } 
            else { throw "MFA failed. State: $($pollResponse.Result.Summary)" }
        }

        if (-not $global:UToken) { throw "No Token was returned." }
        $global:BaseHeaders.Add("Authorization", "Bearer $global:UToken")
        Write-Log "Authentication Successful!" -Level SUCCESS

        return $PlainPassword1

    } catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

function Revoke-IdentityToken {
    param ([string]$Identity_Url, [hashtable]$BaseHeaders)
    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    Write-Log "Revoking Identity token and destroying session..." -Level INFO
    try {
        Invoke-RestMethod -Uri "$Identity_Url/Security/Logout" -Headers $BaseHeaders @RestArgs -ErrorAction Stop | Out-Null
        Write-Log "Session token successfully revoked." -Level SUCCESS
    } catch {
        Write-Log "Failed to gracefully revoke token: $(Get-ApiErrorMessage -ExceptionRecord $_)" -Level WARN
    }
}

# ==============================================================================
# PAM SAFES & MEMBERS
# ==============================================================================
function New-PAMSafes {
    param ([string]$PAM_SaaS_Url, [hashtable]$BaseHeaders, [array]$SafesMatrix)
    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
    $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

    Write-Log "Starting Batch Safe Creation ($($SafesMatrix.Count) Safes)" -Level INFO

    foreach ($safe in $SafesMatrix) {
        $jsonBody = $safe | ConvertTo-Json -Depth 5
        Write-Log "Creating Safe '$($safe.safeName)'..." -Level INFO

        try {
            Invoke-RestMethod -Uri "$BaseUrl/PasswordVault/API/Safes" -Headers $BaseHeaders -Body $jsonBody @RestArgs | Out-Null
            Write-Log "Safe '$($safe.safeName)' created successfully." -Level SUCCESS
        } catch {
            $apiError = Get-ApiErrorMessage -ExceptionRecord $_
            if ($apiError -match "already exists" -or $_.Exception.Message -match "409") {
                Write-Log "Safe '$($safe.safeName)' already exists. Proceeding to membership checks." -Level WARN
            } else {
                Write-Log "Failed to create safe '$($safe.safeName)': $apiError" -Level ERROR
            }
        }
    }
}

function Add-PAMSafeMembers {
    param ([string]$PAM_SaaS_Url, [hashtable]$BaseHeaders, [string]$DirectoryUuid, [hashtable]$PermissionProfiles, [array]$SafeMemberships)
    $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
    $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

    Write-Log "Starting Batch Safe Member Addition ($($SafeMemberships.Count) Memberships)" -Level INFO

    foreach ($mapping in $SafeMemberships) {
        $searchIn = if ($mapping.memberName -in @("Safe Master", "Secure Infrastructure Privilege Cloud Ephemeral Access", "Privilege Cloud Administrators")) { "Vault" } else { $DirectoryUuid }
        $permissions = $PermissionProfiles[$mapping.profile]

        $memberBody = @{ memberName = $mapping.memberName; memberType = $mapping.memberType; searchIn = $searchIn; permissions = $permissions } | ConvertTo-Json -Depth 10
        $encodedSafeNamePOST = [uri]::EscapeDataString($mapping.safeName)
        $uri = "$BaseUrl/PasswordVault/API/Safes/$encodedSafeNamePOST/Members/"

        Write-Log "Adding member '$($mapping.memberName)' to '$($mapping.safeName)'..." -Level INFO

        try {
            Invoke-RestMethod -Uri $uri -Headers $BaseHeaders -Body $memberBody -Method POST -ContentType 'application/json' | Out-Null
            Write-Log "Member '$($mapping.memberName)' added to '$($mapping.safeName)'." -Level SUCCESS
        } catch {
            $apiError = Get-ApiErrorMessage -ExceptionRecord $_

            if ($apiError -match "already exists" -or $_.Exception.Message -match "409") {
                Write-Log "Member '$($mapping.memberName)' already exists in '$($mapping.safeName)'. Verifying permissions..." -Level WARN
                try {
                    $encodedSafeName = [uri]::EscapeDataString($mapping.safeName)
                    $encodedMemberName = [uri]::EscapeDataString($mapping.memberName)
                    $getUri = "$BaseUrl/PasswordVault/API/Safes/$encodedSafeName/Members/$encodedMemberName"

                    $existingMember = Invoke-RestMethod -Uri $getUri -Headers $BaseHeaders -Method GET

                    $mismatchFound = $false
                    foreach ($key in $permissions.Keys) {
                        if ($existingMember.permissions.$key -ne $permissions[$key]) {
                            $mismatchFound = $true
                            break
                        }
                    }

                    if ($mismatchFound) {
                        Write-Log "Permissions for '$($mapping.memberName)' are INCORRECT. Expected profile: $($mapping.profile)." -Level ERROR
                    } else {
                        Write-Log "Permissions for '$($mapping.memberName)' are correctly configured to profile: $($mapping.profile)." -Level SUCCESS
                    }
                } catch {
                    $getApiError = Get-ApiErrorMessage -ExceptionRecord $_
                    if ($getApiError -match "404") {
                        Write-Log "Could not locate member details. Server returned 404 Not Found." -Level ERROR
                    } else {
                        Write-Log "Failed to retrieve existing permissions: $getApiError" -Level ERROR
                    }
                }
            } else {
                Write-Log "Failed to add member '$($mapping.memberName)' to '$($mapping.safeName)': $apiError" -Level ERROR
            }
        }
    }
}

function Remove-PAMSafeMember {
    param ([string]$PAM_SaaS_Url, [hashtable]$BaseHeaders, [array]$SafesMatrix, [string]$MemberToRemove)
    $RestArgs = @{ Method = 'DELETE'; ContentType = 'application/json' }
    $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
    $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

    Write-Log "Cleaning Up: Removing '$MemberToRemove' from Safes" -Level INFO
    $encodedMemberToRemove = [uri]::EscapeDataString($MemberToRemove)

    foreach ($safe in $SafesMatrix) {
        $encodedSafeName = [uri]::EscapeDataString($safe.safeName)
        $uri = "$BaseUrl/PasswordVault/API/Safes/$encodedSafeName/Members/$encodedMemberToRemove/"
        Write-Log "Removing '$MemberToRemove' from Safe '$($safe.safeName)'..." -Level INFO

        try {
            Invoke-RestMethod -Uri $uri -Headers $BaseHeaders @RestArgs | Out-Null
            Write-Log "Successfully removed '$MemberToRemove' from '$($safe.safeName)'." -Level SUCCESS
        } catch {
            $apiError = Get-ApiErrorMessage -ExceptionRecord $_
            if ($apiError -match "not found" -or $_.Exception.Message -match "404") {
                Write-Log "'$MemberToRemove' is not a member of '$($safe.safeName)'. Skipping." -Level DEBUG
            } else {
                Write-Log "Failed to remove '$MemberToRemove' from '$($safe.safeName)': $apiError" -Level ERROR
            }
        }
    }
}
