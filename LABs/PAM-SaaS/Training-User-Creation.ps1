<#
.SYNOPSIS
Safes and Members Provisioning Script v26-07-22

.DESCRIPTION
This script provisions a matrix of Safes and their respective members in a PAM SaaS environment.
It performs the following steps:
1. Initializes a custom logging session to append to Tenant.log on the Desktop with timestamps.
2. Retrieves tenant info from the CSV file (tenantadmin.csv) on the Desktop using Field/Value format.
3. Securely prompts for credentials (verifying the password matches locally) and authenticates to Idira Identity.
4. Creates the defined Safes in the $SafesMatrix array.
5. Adds members to those Safes based on the $SafeMemberships array.
6. Cleans up by removing the authenticated user ($AuthUser) from the newly created Safes.
#>

# ==============================================================================
# Script Configuration
# ==============================================================================
# Set to $true to enable detailed verbose logging output, $false for standard output.
$global:VerboseOutput = $false

if ($global:VerboseOutput) {
    $VerbosePreference = 'Continue'
}

# ==============================================================================
# Setup Custom Logging
# ==============================================================================
$desktopPath = [Environment]::GetFolderPath("Desktop")
$global:LogPath = Join-Path -Path $desktopPath -ChildPath "Tenant.log"

# Add a session header to the log file to separate runs
$sessionStart = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content -Path $global:LogPath -Value "`n====================================================================="
Add-Content -Path $global:LogPath -Value "[$sessionStart] [INFO] Starting New Idira Provisioning Session"
Add-Content -Path $global:LogPath -Value "====================================================================="

function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ConsoleColor]$ForegroundColor = 'Gray',
        [string]$Level = 'INFO'
    )
    $timeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $fileLogEntry = "[$timeStamp] [$Level] $Message"
    $consoleEntry = "[$timeStamp] $Message"

    # Write to console with color
    Write-Host $consoleEntry -ForegroundColor $ForegroundColor

    # Append to log file
    Add-Content -Path $global:LogPath -Value $fileLogEntry
}

function Write-VerboseLog {
    param([string]$Message)
    if ($global:VerboseOutput) {
        Write-Log -Message $Message -ForegroundColor DarkGray -Level 'VERBOSE'
    }
}

Write-Log "Logging initialized. Output is being appended to: $global:LogPath" -ForegroundColor Cyan

# ==============================================================================
# 1. Safes Matrix - List of all safes required for the lab = $SafesMatrix
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
# 2. Safe Memberships Matrix - List of all members for the safes with their permissions = $SafeMemberships
# ==============================================================================
$SafeMemberships = @(
    # --- P-BOS-LIN-S-FIN ---
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "LinuxAdmins@acme.corp"; memberType = "group"; profile = "ConnectAndViewMembers" }
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-LIN-S-FIN"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }

    # --- P-BOS-LIN-S-LOGON ---
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "LinuxAdmins@acme.corp"; memberType = "group"; profile = "ConnectAndViewMembers" }
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-LIN-S-LOGON"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }

    # --- P-BOS-DB-POS ---
    @{ safeName = "P-BOS-DB-POS"; memberName = "DBAdmins@acme.corp"; memberType = "group"; profile = "ConnectOnly" }
    @{ safeName = "P-BOS-DB-POS"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-DB-POS"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-DB-POS"; memberName = "Secure Infrastructure Privilege Cloud Ephemeral Access"; memberType = "Role"; profile = "ConnectOnly" }
    @{ safeName = "P-BOS-DB-POS"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }

    # --- P-BOS-Web-pgAdmin ---
    @{ safeName = "P-BOS-Web-pgAdmin"; memberName = "WebAppAdmins@acme.corp"; memberType = "group"; profile = "ConnectOnly" }
    @{ safeName = "P-BOS-Web-pgAdmin"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-Web-pgAdmin"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-Web-pgAdmin"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }

    # --- P-BOS-WIN-S-LA-FIN ---
    @{ safeName = "P-BOS-WIN-S-LA-FIN"; memberName = "WindowsAdmins@acme.corp"; memberType = "group"; profile = "ConnectAndViewMembers" }
    @{ safeName = "P-BOS-WIN-S-LA-FIN"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-WIN-S-LA-FIN"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-WIN-S-LA-FIN"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }

    # --- P-BOS-WIN-DOM ---
    @{ safeName = "P-BOS-WIN-DOM"; memberName = "WindowsAdmins@acme.corp"; memberType = "group"; profile = "ConnectAndViewMembers" }
    @{ safeName = "P-BOS-WIN-DOM"; memberName = "Privilege Cloud Administrators"; memberType = "Role"; profile = "VaultAdmin" }
    @{ safeName = "P-BOS-WIN-DOM"; memberName = "Safe Master"; memberType = "Role"; profile = "Full" }
    @{ safeName = "P-BOS-WIN-DOM"; memberName = "Privilege Cloud Safe Managers"; memberType = "Role"; profile = "Full" }
)

# ==============================================================================
# 3. Permission Profiles definitions = $PermissionProfiles
# ==============================================================================

# Helper function to generate the 22-item permission block dynamically
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

# Initialize the Hash Table for permission profiles
$PermissionProfiles = @{
    "ConnectOnly" = New-PermSet -TruePerms @("listAccounts", "useAccounts")
    "ConnectAndViewMembers" = New-PermSet -TruePerms @("listAccounts", "useAccounts", "viewSafeMembers")
    "VaultAdmin" = New-PermSet -TruePerms @("listAccounts", "addAccounts", "updateAccountContent", "updateAccountProperties", "initiateCPMAccountManagementOperations", "specifyNextAccountContent", "renameAccounts", "deleteAccounts", "unlockAccounts", "viewSafeMembers", "viewAuditLog")
    "Full" = New-PermSet -TruePerms @("useAccounts", "retrieveAccounts", "listAccounts", "addAccounts", "updateAccountContent", "updateAccountProperties", "initiateCPMAccountManagementOperations", "specifyNextAccountContent", "renameAccounts", "deleteAccounts", "unlockAccounts", "manageSafe", "manageSafeMembers", "backupSafe", "viewAuditLog", "viewSafeMembers", "requestsAuthorizationLevel1", "accessWithoutConfirmation", "createFolders", "deleteFolders", "moveAccountsAndFolders")
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# Helper to collect the tenant admin information from the CSV file on the desktop
function Get-TenantAdminInfo {
    $filePath = Join-Path -Path $desktopPath -ChildPath "tenantadmin.csv"

    # CSV File Check Loop
    while (-not (Test-Path -Path $filePath)) {
        Write-Log "File 'tenantadmin.csv' was NOT found on the Desktop." -ForegroundColor Yellow -Level 'WARNING'
        Write-Log "Please run the 'Training-User-Creation.ps1' script first to generate this configuration file." -ForegroundColor Yellow

        $retry = Read-Host "Press 'Y' to check again, or any other key to exit"
        if ($retry -notmatch '^[Yy]$') {
            Write-Log "Exiting script." -ForegroundColor Yellow
            exit
        }
    }

    Write-VerboseLog "File 'tenantadmin.csv' found on the Desktop."
    $csvData = Import-Csv -Path $filePath -Delimiter ','

    $parsed_PAM_SaaS_Url = $null
    $parsed_Identity_Url = $null
    $parsed_Login = $null

    foreach ($row in $csvData) {
        if ($row.Field -eq "PAM_SaaS_Url") { $parsed_PAM_SaaS_Url = $row.Value }
        if ($row.Field -eq "Identity_Url") { $parsed_Identity_Url = $row.Value }
        if ($row.Field -eq "Login") { $parsed_Login = $row.Value }
    }

    if ($parsed_PAM_SaaS_Url -and $parsed_Identity_Url -and $parsed_Login) {
        $global:PAM_SaaS_Url = $parsed_PAM_SaaS_Url
        $global:Identity_Url = $parsed_Identity_Url
        $global:AuthUser = $parsed_Login

        Write-Log "Extracted Data:"
        Write-Log "PAM SaaS URL : $global:PAM_SaaS_Url"
        Write-Log "Identity URL : $global:Identity_Url"
        Write-Log "Auth User    : $global:AuthUser"
        Write-Log "----------------------------------"
    } else {
        Write-Log "The file 'tenantadmin.csv' does not match the expected format or is missing required fields (PAM_SaaS_Url, Identity_Url, or Login)." -ForegroundColor Yellow -Level 'WARNING'
        exit
    }
}

# Helper function to securely prompt for credentials, and iteratively authenticate via API challenges
function Get-IdiraToken {
    param (
        [Parameter(Mandatory=$true)][string]$Identity_Url,
        [Parameter(Mandatory=$true)][string]$UserEmail
    )

    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    $global:BaseHeaders = @{ "X-Idap-Native-Client" = "true" }
    $IdentityID = ($Identity_Url -replace "https://", "").Split(".")[0]

    Write-Log "--- Authenticating to Idira Identity ($UserEmail) ---" -ForegroundColor Cyan

    $passwordMatch = $false

    # Local Password validation loop
    while (-not $passwordMatch) {
        $pwd1 = Read-Host "Enter the password for $UserEmail" -AsSecureString
        $pwd2 = Read-Host "Confirm the password for $UserEmail" -AsSecureString

        $PlainPassword1 = [System.Net.NetworkCredential]::new("", $pwd1).Password
        $PlainPassword2 = [System.Net.NetworkCredential]::new("", $pwd2).Password

        if ($PlainPassword1 -ceq $PlainPassword2) {
            $passwordMatch = $true
        } else {
            Write-Log "[-] Passwords do not match. Please try again." -ForegroundColor Red -Level 'ERROR'
        }
    }

    Write-Log "[*] Starting authentication process..."
    $bodyStart = @{ 
        TenantId = $IdentityID
        Version = "1.0"
        User = $UserEmail 
    } | ConvertTo-Json -Compress

    Write-VerboseLog "Sending StartAuthentication request to: $Identity_Url/Security/StartAuthentication"
    $resStart = Invoke-RestMethod -Uri "$Identity_Url/Security/StartAuthentication" -Headers $BaseHeaders -Body $bodyStart @RestArgs

    if (-not $resStart.Success -or -not $resStart.Result.Challenges) {
        throw "Failed to start authentication or no challenges returned."
    }

    $SessionId = $resStart.Result.SessionId

    # Capture the mechanism IDs for the challenges up front
    $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms[0].MechanismId
    $MechanismId_Mfa = $resStart.Result.Challenges[1].Mechanisms[0].MechanismId

    Write-Log "[*] Submitting password to Identity..."
    $bodyPwd = @{
        TenantId    = $IdentityID
        SessionId   = $SessionId
        MechanismId = $MechanismId_Pwd
        Action      = "Answer"
        Answer      = $PlainPassword1
    } | ConvertTo-Json -Compress

    Write-VerboseLog "Sending AdvanceAuthentication (Password) request."
    $resPwd = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyPwd @RestArgs

    if (-not $resPwd.Success -or $resPwd.Result.Summary -eq "LoginFailed") {
        throw "Authentication failed: Incorrect password."
    }

    # Auth Step 3: Trigger MFA (OOB)
    Write-Log "[*] Triggering MFA Challenge..."
    $bodyMfa = @{
        TenantID    = $IdentityID
        SessionId   = $SessionId
        MechanismId = $MechanismId_Mfa
        Action      = "StartOOB"
    } | ConvertTo-Json -Compress

    Write-VerboseLog "Sending AdvanceAuthentication (MFA StartOOB) request."
    $resMfa = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyMfa @RestArgs

    Write-Log "[!] MFA challenge sent to your device." -ForegroundColor Yellow
    Write-Log "[!] Waiting for approval... Check your email or authenticator app." -ForegroundColor Cyan

    $pollResponse = $resMfa

    # Poll Identity API until the user clicks the link/approves MFA
    while ($pollResponse.Result.Summary -in @("OobPending", "PendingOOB", "Pending")) {
        Start-Sleep -Seconds 3
        $pollBody = @{
            TenantID    = $IdentityID
            SessionId   = $SessionId
            MechanismId = $MechanismId_Mfa
            Action      = "Poll"
        } | ConvertTo-Json -Compress

        Write-VerboseLog "Polling for MFA completion token..."
        $pollResponse = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $pollBody @RestArgs
    }

    if ($pollResponse.Success -and -not [string]::IsNullOrEmpty($pollResponse.Result.Token)) {
        $global:UToken = $pollResponse.Result.Token
        $BaseHeaders.Add("Authorization", "Bearer $UToken")
        Write-Log "[+] Authentication Successful!" -ForegroundColor Green
    } else {
        throw "Authentication failed: MFA approval failed or timed out."
    }
}

# Create new Safes in the Vault
function New-IdiraSafes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$PAM_SaaS_Url,
        [Parameter(Mandatory = $true)][hashtable]$BaseHeaders,
        [Parameter(Mandatory = $true)][array]$SafesMatrix
    )

    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    Write-Log "--- Starting Batch Safe Creation ($($SafesMatrix.Count) Safes) ---" -ForegroundColor Cyan

    $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
    $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

    foreach ($safe in $SafesMatrix) {
        Write-Log "[*] Creating Safe '$($safe.safeName)'..." -ForegroundColor Cyan

        $safeBody = @{
            safeName = $safe.safeName
            description = $safe.description
            numberOfDaysRetention = $safe.numberOfDaysRetention
        }

        if ($null -ne $safe.autoPurgeEnabled) {
            $safeBody.Add("autoPurgeEnabled", $safe.autoPurgeEnabled)
        }

        $jsonBody = $safeBody | ConvertTo-Json -Depth 5

        try {
            Write-VerboseLog "Target URI: $BaseUrl/PasswordVault/API/Safes"
            Write-VerboseLog "Payload Body: $jsonBody"

            $safeResponse = Invoke-RestMethod -Uri "$BaseUrl/PasswordVault/API/Safes" -Headers $BaseHeaders -Body $jsonBody @RestArgs
            Write-Log "[+] Safe '$($safe.safeName)' created successfully." -ForegroundColor Green
        } catch {
            $responseBody = ""
            if ($_.Exception.Response) {
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                } catch {}
            }

            # Check if the error indicates that the safe is already created
            if ($responseBody -match "already exists" -or $_.Exception.Message -match "already exists" -or $responseBody -match "PASWS040E" -or $responseBody -match "PASWS138E") {
                Write-Log "[i] Information: Safe '$($safe.safeName)' already exists." -ForegroundColor Cyan
            } else {
                Write-Log "[-] Failed to create safe '$($safe.safeName)': $($_.Exception.Message)" -ForegroundColor Red -Level 'ERROR'
                if ($_.ErrorDetails) {
                    Write-Log "    Server Error Details: $($_.ErrorDetails.Message)" -ForegroundColor DarkRed -Level 'ERROR'
                } elseif ($responseBody) {
                    Write-Log "    Server Response Body: $responseBody" -ForegroundColor DarkRed -Level 'ERROR'
                }
            }
        }
    }
}

# Add Members to Safes based on the matrix
function Add-IdiraSafeMembers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$PAM_SaaS_Url,
        [Parameter(Mandatory = $true)][hashtable]$BaseHeaders,
        [Parameter(Mandatory = $true)][string]$DirectoryUuid,
        [Parameter(Mandatory = $true)][hashtable]$PermissionProfiles,
        [Parameter(Mandatory = $true)][array]$SafeMemberships
    )

    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    Write-Log "--- Starting Batch Safe Member Addition ($($SafeMemberships.Count) Memberships) ---" -ForegroundColor Cyan

    $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
    $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

    foreach ($mapping in $SafeMemberships) {
        $safeName = $mapping.safeName
        $memberName = $mapping.memberName
        $memberType = $mapping.memberType
        $profileName = $mapping.profile

        Write-Log "[*] Processing member '$memberName' for Safe '$safeName'..." -ForegroundColor Cyan

        $searchIn = if ($memberName -in @("Safe Master", "Secure Infrastructure Privilege Cloud Ephemeral Access", "Privilege Cloud Administrators")) { 
            "Vault" 
        } else { 
            $DirectoryUuid 
        }

        $permissions = $PermissionProfiles[$profileName]

        if ($null -eq $permissions) {
            Write-Log "Permissions profile '$profileName' could not be found. Skipping." -ForegroundColor Yellow -Level 'WARNING'
            continue
        }

        $memberBody = @{
            memberName = $memberName
            memberType = $memberType
            searchIn = $searchIn
            permissions = $permissions
        } | ConvertTo-Json -Depth 10

        $uri = "$BaseUrl/PasswordVault/API/Safes/$safeName/Members/"

        try {
            Write-VerboseLog "Target URI: $uri"
            Write-VerboseLog "Payload Body: $memberBody"

            $response = Invoke-RestMethod -Uri $uri -Headers $BaseHeaders -Body $memberBody @RestArgs

            if ($response -is [string] -and $response -match "idaptive|<!DOCTYPE html>") {
                Write-Log "[-] Failed to add member '$memberName' to '$safeName'. Token unauthorized or invalid URL." -ForegroundColor Red -Level 'ERROR'
            } else {
                Write-Log "[+] Member '$memberName' added successfully to '$safeName'." -ForegroundColor Green
            }
        } catch {
            Write-Log "[-] Failed to add member '$memberName' to '$safeName'." -ForegroundColor Red -Level 'ERROR'
            Write-Log "    Exception Message: $($_.Exception.Message)" -ForegroundColor Red -Level 'ERROR'
        }
        Write-Log "--------------------------------------------------------"
    }
}

# Remove a specific member from the created Safes
function Remove-IdiraSafeMember {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$PAM_SaaS_Url,
        [Parameter(Mandatory = $true)][hashtable]$BaseHeaders,
        [Parameter(Mandatory = $true)][array]$SafesMatrix,
        [Parameter(Mandatory = $true)][string]$MemberToRemove
    )

    $RestArgs = @{ Method = 'DELETE'; ContentType = 'application/json' }
    Write-Log "--- Cleaning Up: Removing '$MemberToRemove' from Safes ---" -ForegroundColor Cyan

    $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
    $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

    foreach ($safe in $SafesMatrix) {
        $safeName = $safe.safeName
        Write-Log "[*] Removing '$MemberToRemove' from Safe '$safeName'..." -ForegroundColor Cyan

        $uri = "$BaseUrl/PasswordVault/API/Safes/$safeName/Members/$MemberToRemove/"

        try {
            Write-VerboseLog "Target URI: $uri"
            $response = Invoke-RestMethod -Uri $uri -Headers $BaseHeaders @RestArgs
            Write-Log "[+] Successfully removed '$MemberToRemove' from '$safeName'." -ForegroundColor Green
        } catch {
            Write-Log "[-] Failed to remove '$MemberToRemove' from '$safeName': $($_.Exception.Message)" -ForegroundColor Red -Level 'ERROR'
        }
    }
}

# ==============================================================================
# Execution Flow
# ==============================================================================
try {
    Get-TenantAdminInfo

    Get-IdiraToken -Identity_Url $Identity_Url -UserEmail $AuthUser

    # Define the DirectoryName before using it to filter
    $DirectoryName = "Active Directory: acme.corp"

    Write-VerboseLog "Fetching Directory Services from Identity..."
    $response = Invoke-RestMethod -Uri "$Identity_Url/Core/GetDirectoryServices" -Method POST -Headers $BaseHeaders -ContentType 'application/json'
    $targetDirectory = $response.Result.Results | Where-Object { $_.Row.DisplayName -eq $DirectoryName }

    if (-not $targetDirectory) {
        throw "Could not locate directory '$DirectoryName' in Identity."
    }

    $DirectoryUuid = $targetDirectory.Row.directoryServiceUuid
    Write-Log "Directory UUID: $DirectoryUuid" -ForegroundColor Gray

    # Trigger Safe creation
    New-IdiraSafes -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -SafesMatrix $SafesMatrix

    # Trigger Safe member addition
    Add-IdiraSafeMembers -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -DirectoryUuid $DirectoryUuid -PermissionProfiles $PermissionProfiles -SafeMemberships $SafeMemberships

    # Clean up by removing the authenticated user from the created safes
    Remove-IdiraSafeMember -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -SafesMatrix $SafesMatrix -MemberToRemove $AuthUser

} catch {
    Write-Log "Script execution halted: $_" -ForegroundColor Red -Level 'ERROR'
} finally {
    Write-Log "--- Execution Complete ---" -ForegroundColor Cyan
}
