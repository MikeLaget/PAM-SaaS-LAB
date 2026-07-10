<#
.SYNOPSIS
Safes and Members Provisioning Script

.DESCRIPTION
This script provisions a matrix of Safes and their respective members in a PAM SaaS environment.
It performs the following steps:
1. Starts a transcript logging session to the current user's Desktop.
2. Retrieves tenant info from the CSV file (tenantadmin.csv) on the Desktop.
3. Securely prompts for credentials (verifying the password matches locally) and authenticates to CyberArk Identity.
4. Creates the defined Safes in the $SafesMatrix array.
5. Adds members to those Safes based on the $SafeMemberships array.
6. Cleans up by removing the authenticated user ($AuthUser) from the newly created Safes.
7. Stops the transcript logging.
#>

# ==============================================================================
# Script Configuration
# ==============================================================================
# Set to $true to enable detailed verbose logging output, $false for standard output.
$VerboseOutput = $false

if ($VerboseOutput) {
 $VerbosePreference = 'Continue'
}

# ==============================================================================
# Start Transcript Logging
# ==============================================================================
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logFileName = "CyberArk_Provisioning_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$logPath = Join-Path -Path $desktopPath -ChildPath $logFileName

Write-Host "Starting transcript log. Output will be saved to: $logPath" -ForegroundColor Cyan
Start-Transcript -Path $logPath -Append

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

 if (Test-Path -Path $filePath) {
 Write-Verbose "File 'tenantadmin.csv' found on the Desktop."
 $csvData = Import-Csv -Path $filePath -Delimiter ','

 foreach ($row in $csvData) {
 if ($row.PSObject.Properties.Match('PAM_SaaS_Url').Count -gt 0 -and
 $row.PSObject.Properties.Match('Identity_Url').Count -gt 0 -and
 $row.PSObject.Properties.Match('Login').Count -gt 0) {

 $global:PAM_SaaS_Url = $row.PAM_SaaS_Url
 $global:Identity_Url = $row.Identity_Url
 $global:AuthUser = $row.Login

 Write-Host "Extracted Data:"
 Write-Host "PAM SaaS URL : $global:PAM_SaaS_Url"
 Write-Host "Identity URL : $global:Identity_Url"
 Write-Host "Auth User : $global:AuthUser"
 Write-Host "----------------------------------"
 } else {
 Write-Warning "The file does not match the expected format or is missing required columns."
 }
 }
 } else {
 Write-Warning "File 'tenantadmin.csv' was NOT found on the Desktop."
 Stop-Transcript
 throw "Missing required configuration file 'tenantadmin.csv'. Exiting."
 }
}

# Helper function to securely prompt for credentials, and iteratively authenticate via API challenges
function Get-CyberArkToken {
 param (
 [Parameter(Mandatory=$true)][string]$Identity_Url,
 [Parameter(Mandatory=$true)][string]$UserEmail
 )

 $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
 $global:BaseHeaders = @{ "X-Idap-Native-Client" = "true" }
 $IdentityID = ($Identity_Url -replace "https://", "").Split(".")[0]

 Write-Host "`n--- Authenticating to CyberArk Identity ($UserEmail) ---" -ForegroundColor Cyan

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
 Write-Host "[-] Passwords do not match. Please try again.`n" -ForegroundColor Red
 }
 }

 Write-Host "[*] Starting authentication process..."
 $bodyStart = @{ 
 TenantId = $IdentityID
 Version = "1.0"
 User = $UserEmail 
 } | ConvertTo-Json -Compress

 Write-Verbose "Sending StartAuthentication request to: $Identity_Url/Security/StartAuthentication"
 $resStart = Invoke-RestMethod -Uri "$Identity_Url/Security/StartAuthentication" -Headers $BaseHeaders -Body $bodyStart @RestArgs

 if (-not $resStart.Success -or -not $resStart.Result.Challenges) {
     throw "Failed to start authentication or no challenges returned."
 }

 $SessionId = $resStart.Result.SessionId

 # Capture the mechanism IDs for the challenges up front
 $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms[0].MechanismId
 $MechanismId_Mfa = $resStart.Result.Challenges[1].Mechanisms[0].MechanismId

 Write-Host "[*] Submitting password to Identity..."
 $bodyPwd = @{
     TenantId    = $IdentityID
     SessionId   = $SessionId
     MechanismId = $MechanismId_Pwd
     Action      = "Answer"
     Answer      = $PlainPassword1
 } | ConvertTo-Json -Compress

 Write-Verbose "Sending AdvanceAuthentication (Password) request."
 $resPwd = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyPwd @RestArgs

 if (-not $resPwd.Success -or $resPwd.Result.Summary -eq "LoginFailed") {
     throw "Authentication failed: Incorrect password."
 }

 # Auth Step 3: Trigger MFA (OOB)
 Write-Host "[*] Triggering MFA Challenge..."
 $bodyMfa = @{
     TenantID    = $IdentityID
     SessionId   = $SessionId
     MechanismId = $MechanismId_Mfa
     Action      = "StartOOB"
 } | ConvertTo-Json -Compress

 Write-Verbose "Sending AdvanceAuthentication (MFA StartOOB) request."
 $resMfa = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyMfa @RestArgs

 Write-Host "`n[!] MFA challenge sent to your device." -ForegroundColor Yellow
 Write-Host "[!] Waiting for approval... Check your email or authenticator app." -ForegroundColor Cyan

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

     Write-Verbose "Polling for MFA completion token..."
     $pollResponse = Invoke-RestMethod -Uri "$Identity_Url/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $pollBody @RestArgs
 }

 if ($pollResponse.Success -and -not [string]::IsNullOrEmpty($pollResponse.Result.Token)) {
     $global:UToken = $pollResponse.Result.Token
     $BaseHeaders.Add("Authorization", "Bearer $UToken")
     Write-Host "[+] Authentication Successful!" -ForegroundColor Green
 } else {
     throw "Authentication failed: MFA approval failed or timed out."
 }
}

# Create new Safes in the Vault
function New-CyberArkSafes {
 [CmdletBinding()]
 param (
 [Parameter(Mandatory = $true)][string]$PAM_SaaS_Url,
 [Parameter(Mandatory = $true)][hashtable]$BaseHeaders,
 [Parameter(Mandatory = $true)][array]$SafesMatrix
 )

 $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
 Write-Host "`n--- Starting Batch Safe Creation ($($SafesMatrix.Count) Safes) ---" -ForegroundColor Cyan

 $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
 $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

 foreach ($safe in $SafesMatrix) {
 Write-Host "[*] Creating Safe '$($safe.safeName)'..." -ForegroundColor Cyan

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
 Write-Verbose "Target URI: $BaseUrl/PasswordVault/API/Safes"
 Write-Verbose "Payload Body: $jsonBody"

 $safeResponse = Invoke-RestMethod -Uri "$BaseUrl/PasswordVault/API/Safes" -Headers $BaseHeaders -Body $jsonBody @RestArgs
 Write-Host "[+] Safe '$($safe.safeName)' created successfully." -ForegroundColor Green
 } catch {
 Write-Host "[-] Failed to create safe '$($safe.safeName)': $($_.Exception.Message)" -ForegroundColor Red
 if ($_.ErrorDetails) {
 Write-Host " Server Error Details: $($_.ErrorDetails.Message)" -ForegroundColor DarkRed
 } elseif ($_.Exception.Response) {
 try {
 $stream = $_.Exception.Response.GetResponseStream()
 $reader = New-Object System.IO.StreamReader($stream)
 $responseBody = $reader.ReadToEnd()
 Write-Host " Server Response Body: $responseBody" -ForegroundColor DarkRed
 } catch {}
 }
 }
 }
}

# Add Members to Safes based on the matrix
function Add-CyberArkSafeMembers {
 [CmdletBinding()]
 param (
 [Parameter(Mandatory = $true)][string]$PAM_SaaS_Url,
 [Parameter(Mandatory = $true)][hashtable]$BaseHeaders,
 [Parameter(Mandatory = $true)][string]$DirectoryUuid,
 [Parameter(Mandatory = $true)][hashtable]$PermissionProfiles,
 [Parameter(Mandatory = $true)][array]$SafeMemberships
 )

 $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
 Write-Host "`n--- Starting Batch Safe Member Addition ($($SafeMemberships.Count) Memberships) ---" -ForegroundColor Cyan

 $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
 $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

 foreach ($mapping in $SafeMemberships) {
 $safeName = $mapping.safeName
 $memberName = $mapping.memberName
 $memberType = $mapping.memberType
 $profileName = $mapping.profile

 Write-Host "[*] Processing member '$memberName' for Safe '$safeName'..." -ForegroundColor Cyan

 $searchIn = if ($memberName -in @("Safe Master", "Secure Infrastructure Privilege Cloud Ephemeral Access", "Privilege Cloud Administrators")) { 
 "Vault" 
 } else { 
 $DirectoryUuid 
 }

 $permissions = $PermissionProfiles[$profileName]

 if ($null -eq $permissions) {
 Write-Warning "Permissions profile '$profileName' could not be found. Skipping."
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
 Write-Verbose "Target URI: $uri"
 Write-Verbose "Payload Body: $memberBody"

 $response = Invoke-RestMethod -Uri $uri -Headers $BaseHeaders -Body $memberBody @RestArgs

 if ($response -is [string] -and $response -match "idaptive|<!DOCTYPE html>") {
 Write-Host "[-] Failed to add member '$memberName' to '$safeName'. Token unauthorized or invalid URL." -ForegroundColor Red
 } else {
 Write-Host "[+] Member '$memberName' added successfully to '$safeName'." -ForegroundColor Green
 }
 } catch {
 Write-Host "[-] Failed to add member '$memberName' to '$safeName'." -ForegroundColor Red
 Write-Host " Exception Message: $($_.Exception.Message)" -ForegroundColor Red
 }
 Write-Host "--------------------------------------------------------"
 }
}

# Remove a specific member from the created Safes
function Remove-CyberArkSafeMember {
 [CmdletBinding()]
 param (
 [Parameter(Mandatory = $true)][string]$PAM_SaaS_Url,
 [Parameter(Mandatory = $true)][hashtable]$BaseHeaders,
 [Parameter(Mandatory = $true)][array]$SafesMatrix,
 [Parameter(Mandatory = $true)][string]$MemberToRemove
 )

 $RestArgs = @{ Method = 'DELETE'; ContentType = 'application/json' }
 Write-Host "`n--- Cleaning Up: Removing '$MemberToRemove' from Safes ---" -ForegroundColor Cyan

 $Sub_Domain = ($PAM_SaaS_Url -replace "https?://", "").Split(".")[0]
 $BaseUrl = "https://$Sub_Domain.privilegecloud.cyberark.cloud"

 foreach ($safe in $SafesMatrix) {
 $safeName = $safe.safeName
 Write-Host "[*] Removing '$MemberToRemove' from Safe '$safeName'..." -ForegroundColor Cyan

 $uri = "$BaseUrl/PasswordVault/API/Safes/$safeName/Members/$MemberToRemove/"

 try {
 Write-Verbose "Target URI: $uri"
 $response = Invoke-RestMethod -Uri $uri -Headers $BaseHeaders @RestArgs
 Write-Host "[+] Successfully removed '$MemberToRemove' from '$safeName'." -ForegroundColor Green
 } catch {
 Write-Host "[-] Failed to remove '$MemberToRemove' from '$safeName': $($_.Exception.Message)" -ForegroundColor Red
 }
 }
}

# ==============================================================================
# Execution Flow
# ==============================================================================
try {
 Get-TenantAdminInfo

 Get-CyberArkToken -Identity_Url $Identity_Url -UserEmail $AuthUser

 # Define the DirectoryName before using it to filter
 $DirectoryName = "Active Directory: acme.corp"

 Write-Verbose "Fetching Directory Services from Identity..."
 $response = Invoke-RestMethod -Uri "$Identity_Url/Core/GetDirectoryServices" -Method POST -Headers $BaseHeaders -ContentType 'application/json'
 $targetDirectory = $response.Result.Results | Where-Object { $_.Row.DisplayName -eq $DirectoryName }

 if (-not $targetDirectory) {
 throw "Could not locate directory '$DirectoryName' in Identity."
 }

 $DirectoryUuid = $targetDirectory.Row.directoryServiceUuid
 Write-Host "Directory UUID: $DirectoryUuid" -ForegroundColor Gray

 # Trigger Safe creation
 New-CyberArkSafes -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -SafesMatrix $SafesMatrix

 # Trigger Safe member addition
 Add-CyberArkSafeMembers -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -DirectoryUuid $DirectoryUuid -PermissionProfiles $PermissionProfiles -SafeMemberships $SafeMemberships

 # Clean up by removing the authenticated user from the created safes
 Remove-CyberArkSafeMember -PAM_SaaS_Url $PAM_SaaS_Url -BaseHeaders $BaseHeaders -SafesMatrix $SafesMatrix -MemberToRemove $AuthUser

} catch {
 Write-Error "Script execution halted: $_"
} finally {
 # Check if we have an active transcript before trying to stop it
 try {
    $transcriptInfo = Get-Command Stop-Transcript -ErrorAction Stop
    if ($host.UI.RawUI.IsTranscribing) {
        Write-Host "`n--- Execution Complete ---" -ForegroundColor Cyan
        Stop-Transcript | Out-Null
    }
 } catch {
    # Silently catch and suppress errors if transcript is not active or command is unavailable
 }
}
