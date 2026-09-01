<#
.SYNOPSIS
Safes and Members Provisioning Script v26-09-01

.DESCRIPTION
This script provisions a matrix of Safes and their respective members in a PAM SaaS environment.
It features structured logging, interactive MFA selection, and secure token revocation.
#>

# ==============================================================================
# Script Configuration & Toggles
# ==============================================================================

$EnableFileLogging = $true      # Set to $false to disable logging to a file
$EnableDebugMode   = $false     # Set to $true to log detailed API payloads and HTTP responses

# Log File Setup
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logFileName = "PAM_Provisioning_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:LogFilePath = Join-Path -Path $desktopPath -ChildPath $logFileName

# ==============================================================================
# Core Logging Function
# ==============================================================================
function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "SUCCESS")][string]$Level = "INFO"
    )

    if ($Level -eq "DEBUG" -and -not $script:EnableDebugMode) { return }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"    { Write-Host $LogLine -ForegroundColor Cyan }
        "SUCCESS" { Write-Host $LogLine -ForegroundColor Green }
        "WARN"    { Write-Host $LogLine -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogLine -ForegroundColor Red }
        "DEBUG"   { Write-Host $LogLine -ForegroundColor Gray }
    }

    if ($script:EnableFileLogging) {
        try { Add-Content -Path $script:LogFilePath -Value $LogLine -ErrorAction Stop } catch {}
    }
}

if ($EnableFileLogging) { Write-Log "Logging initialized. File: $script:LogFilePath" -Level INFO }
if ($EnableDebugMode)   { Write-Log "DEBUG MODE IS ENABLED. Detailed payloads will be logged." -Level WARN }

# ==============================================================================
# 1. Safes Matrix
# ==============================================================================
$SafesMatrix = @(
    @{ safeName = "P-BOS-LIN-S-FIN"; description = "Linux Financial Servers"; numberOfDaysRetention = 5 }
    @{ safeName = "P-BOS-LIN-S-LOGON"; description = "Linux Logon Servers"; numberOfDaysRetention = 5 }
    @{ safeName = "P-BOS-DB-POS"; description = "POS Database Servers"; numberOfDaysRetention = 5 }
    @{ safeName = "P-BOS-Web-pgAdmin"; description = "pgAdmin Web Servers"; numberOfDaysRetention = 5 }
    @{ safeName = "P-BOS-WIN-S-LA-FIN"; description = "Windows LA Financial"; numberOfDaysRetention = 5 }
    @{ safeName = "P-BOS-WIN-DOM"; description = "Windows Domain Servers"; numberOfDaysRetention = 5 }
)

# ==============================================================================
# 2. Safe Memberships Matrix
# ==============================================================================
$SafeMemberships = @(
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "LinuxAdmins@acme.corp"; memberType = "group"; profile = "ConnectAndViewMembers" }
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }

    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "LinuxAdmins@acme.corp"; memberType = "group"; profile = "ConnectAndViewMembers" }
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }
)

# ==============================================================================
# 3. Permission Profiles
# ==============================================================================
function New-PermSet ([string[]]$TruePerms) {
    $perms = @{
        useAccounts=$false; retrieveAccounts=$false; listAccounts=$false; addAccounts=$false; updateAccountContent=$false; 
        updateAccountProperties=$false; initiateCPMAccountManagementOperations=$false; specifyNextAccountContent=$false; 
        renameAccounts=$false; deleteAccounts=$false; unlockAccounts=$false; manageSafe=$false; manageSafeMembers=$false; 
        backupSafe=$false; viewAuditLog=$false; viewSafeMembers=$false; accessWithoutConfirmation=$false; createFolders=$false; 
        deleteFolders=$false; moveAccountsAndFolders=$false; requestsAuthorizationLevel1=$false; requestsAuthorizationLevel2=$false
    }
    foreach ($p in $TruePerms) { $perms[$p] = $true }
    return $perms
}

$PermissionProfiles = @{
    "ConnectOnly" = New-PermSet -TruePerms @("listAccounts", "useAccounts")
    "ConnectAndViewMembers" = New-PermSet -TruePerms @("listAccounts", "useAccounts", "viewSafeMembers")
    "VaultAdmin" = New-PermSet -TruePerms @("listAccounts", "addAccounts", "updateAccountContent", "updateAccountProperties", "initiateCPMAccountManagementOperations", "specifyNextAccountContent", "renameAccounts", "deleteAccounts", "unlockAccounts", "viewSafeMembers", "viewAuditLog")
    "Full" = New-PermSet -TruePerms @("useAccounts", "retrieveAccounts", "listAccounts", "addAccounts", "updateAccountContent", "updateAccountProperties", "initiateCPMAccountManagementOperations", "specifyNextAccountContent", "renameAccounts", "deleteAccounts", "unlockAccounts", "manageSafe", "manageSafeMembers", "backupSafe", "viewAuditLog", "viewSafeMembers", "requestsAuthorizationLevel1", "accessWithoutConfirmation", "createFolders", "deleteFolders", "moveAccountsAndFolders")
}

# ==============================================================================
# Helper Functions
# ==============================================================================

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

function Get-TenantAdminInfo {
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

function Get-IdentityToken {
    param ([string]$Identity_Url, [string]$UserEmail)
    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    $global:BaseHeaders = @{ "X-Idap-Native-Client" = "true" }
    $IdentityID = ($Identity_Url -replace "https://", "").Split(".")[0]

    Write-Log "Authenticating to Identity Platform ($UserEmail)" -Level INFO
    $passwordMatch = $false

    while (-not $passwordMatch) {
        $pwd1 = Read-Host "Enter the password for $UserEmail" -AsSecureString
        $pwd2 = Read-Host "Confirm the password for $UserEmail" -AsSecureString
        $PlainPassword1 = [System.Net.NetworkCredential]::new("", $pwd1).Password
        $PlainPassword2 = [System.Net.NetworkCredential]::new("", $pwd2).Password

        if ($PlainPassword1 -ceq $PlainPassword2) { $passwordMatch = $true } 
        else { Write-Log "Passwords do not match. Please try again." -Level ERROR }
    }

    try {
        $bodyStart = @{ TenantId = $IdentityID; Version = "1.0"; User = $UserEmail } | ConvertTo-Json -Compress
        $resStart = Invoke-RestMethod -Uri "$Identity_Url/Security/StartAuthentication" -Headers $BaseHeaders -Body $bodyStart @RestArgs

        if (-not $resStart.Success -or $null -eq $resStart.Result.Challenges) { throw "API returned Success=$false or no challenges." }

        $SessionId = $resStart.Result.SessionId
        $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms | Where-Object { $_.Name -match "Password" } | Select-Object -ExpandProperty MechanismId
        if (-not $MechanismId_Pwd) { $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms[0].MechanismId }

        Write-Log "Submitting password..." -Level INFO
        $bodyPwd = @{ TenantId = $IdentityID; SessionId = $SessionId; MechanismId = $MechanismId_Pwd; Action = "Answer"; Answer = $PlainPassword1 } | ConvertTo-Json -Compress
        $resPwd = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyPwd @RestArgs

        if (-not $resPwd.Success -or $resPwd.Result.Summary -eq "LoginFailed") { throw "Incorrect password or login failed." }
        if ($resPwd.Result.Summary -eq "NewPasswordRequired") { throw "User must change their password before API authentication." }

        if ($resPwd.Result.Summary -eq "LoginSuccess") {
            $global:UToken = $resPwd.Result.Token
        } else {
            # Find the MFA challenge array
            $mfaChallenge = if ($resPwd.Result.Challenges) { $resPwd.Result.Challenges[0] } else { $resStart.Result.Challenges[1] }

            # Filter for Email or SMS options
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
                    if ([int]::TryParse($inputStr, [ref]$selection) -and $selection -ge 1 -and $selection -le $mfaOptions.Count) {
                        break
                    }
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

            # Trigger MFA
            $bodyMfa = @{ TenantID = $IdentityID; SessionId = $SessionId; MechanismId = $MechanismId_Mfa; Action = "StartOOB" } | ConvertTo-Json -Compress
            $resMfa = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyMfa @RestArgs

            Write-Log "MFA challenge sent. Waiting for approval (Check your phone or email)..." -Level WARN
            $pollResponse = $resMfa

            while ($pollResponse.Result.Summary -in @("OobPending", "PendingOOB", "Pending")) {
                Start-Sleep -Seconds 3
                $pollBody = @{ TenantID = $IdentityID; SessionId = $SessionId; MechanismId = $MechanismId_Mfa; Action = "Poll" } | ConvertTo-Json -Compress
                $pollResponse = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $pollBody @RestArgs
            }

            if ($pollResponse.Result.Summary -eq "LoginSuccess") { $global:UToken = $pollResponse.Result.Token } 
            else { throw "MFA failed. State: $($pollResponse.Result.Summary)" }
        }

        if (-not $global:UToken) { throw "No Token was returned." }
        $BaseHeaders.Add("Authorization", "Bearer $UToken")
        Write-Log "Authentication Successful!" -Level SUCCESS

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
                        Write-Log "Could not locate member details for '$($mapping.memberName)'. The server returned 404 Not Found." -Level ERROR
                    } else {
                        Write-Log "Failed to retrieve existing permissions for '$($mapping.memberName)': $getApiError" -Level ERROR
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

# ==============================================================================
# Execution Flow
# ==============================================================================
try {
    Write-Log "--- Script Execution Started ---" -Level INFO
    Get-TenantAdminInfo

    Get-IdentityToken -Identity_Url $Identity_Url -UserEmail $AuthUser

    $DirectoryName = "Active Directory: acme.corp"
    Write-Log "Fetching Directory UUID for '$DirectoryName'..." -Level INFO
    $response = Invoke-RestMethod -Uri "$Identity_Url/Core/GetDirectoryServices" -Method POST -Headers $BaseHeaders -ContentType 'application/json'
    $DirectoryUuid = ($response.Result.Results | Where-Object { $_.Row.DisplayName -eq $DirectoryName }).Row.directoryServiceUuid

    if (-not $DirectoryUuid) { throw "Could not locate directory '$DirectoryName' in Identity platform." }
    Write-Log "Directory UUID: $DirectoryUuid" -Level SUCCESS

    New-PAMSafes -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -SafesMatrix $SafesMatrix

    Add-PAMSafeMembers -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -DirectoryUuid $DirectoryUuid -PermissionProfiles $PermissionProfiles -SafeMemberships $SafeMemberships

    Remove-PAMSafeMember -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -SafesMatrix $SafesMatrix -MemberToRemove $AuthUser

    Write-Log "--- Script Execution Completed Successfully ---" -Level SUCCESS
} catch {
    Write-Log "Script execution halted due to a critical error: $($_.Exception.Message)" -Level ERROR
} finally {
    # Always attempt to revoke the token and destroy the session to ensure security, even if script fails
    if ($global:BaseHeaders -and $global:BaseHeaders.ContainsKey("Authorization")) {
        Revoke-IdentityToken -Identity_Url $Identity_Url -BaseHeaders $global:BaseHeaders
    }
}
