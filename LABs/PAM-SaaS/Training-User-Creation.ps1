<#
.SYNOPSIS
Training support account creation v26-09-01

.DESCRIPTION
This script creates training accounts, verifies identity URLs, authenticates,
assigns roles, and exports tenant configuration.
It features structured logging, interactive MFA selection, secure token revocation,
and full rerun/idempotency support.
#>

# ==============================================================================
# Script Configuration & Toggles
# ==============================================================================

$EnableFileLogging = $true
$EnableDebugMode   = $false

# Log File Setup
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logFileName = "TenantAdmin_Provisioning_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:LogFilePath = Join-Path -Path $desktopPath -ChildPath $logFileName
$ExportPath  = Join-Path -Path $desktopPath -ChildPath "tenantadmin.csv"

# ==============================================================================
# 1. HELPER FUNCTIONS
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

            Write-Log "MFA challenge sent. Waiting for approval (Check your phone or email)..." -Level WARN
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
# 2. EXECUTION FLOW & PRE-FLIGHT CHECKS
# ==============================================================================
try {
    if ($EnableFileLogging) { Write-Log "Logging initialized. File: $script:LogFilePath" -Level INFO }
    Write-Log "--- Tenant Initialization & Verification ---" -Level INFO

    $UseExisting = $false
    $UsersToCreate = @()
    $ExportObj = [ordered]@{}

    if (Test-Path $ExportPath) {
        Write-Log "Found existing configuration file (tenantadmin.csv)." -Level INFO
        $csvData = Import-Csv -Path $ExportPath
        $csvDict = @{}
        foreach ($row in $csvData) { $csvDict[$row.Field] = $row.Value }

        if ($csvDict.Contains("Login") -and $csvDict.Contains("Identity_Url")) {
            Write-Host "`nFound existing configuration for:" -ForegroundColor Cyan
            Write-Host "  Tenant Admin: $($csvDict['Login'])" -ForegroundColor White
            Write-Host "  Identity URL: $($csvDict['Identity_Url'])" -ForegroundColor White

            $choice = Read-Host "Do you want to verify and re-apply this configuration? (Y/N)"
            if ($choice -match "^[Yy]$") {
                $UseExisting = $true
                $Username    = $csvDict["Login"]
                $IdentityURL = $csvDict["Identity_Url"]
                $PAMUrl      = $csvDict["PAM_SaaS_Url"]

                $UsersToCreate += @{ 
                    Name = $csvDict["Training_User"]; 
                    Mail = "cybr-training-labs+PAMSAAS_Trainer@paloaltonetworks.com"; 
                    Password = $csvDict["Training_User_Pwd"] 
                }

                if ($csvDict.Contains("Trainer_User") -and -not [string]::IsNullOrWhiteSpace($csvDict["Trainer_User"])) {
                    $UsersToCreate += @{ 
                        Name = $csvDict["Trainer_User"]; 
                        Mail = "trainer@placeholder.com"; # Email isn't tracked in CSV, dummy is fine for verification
                        Password = $csvDict["Trainer_User_Pwd"] 
                    }
                }

                # Reconstruct base ExportObj to append to later
                foreach ($key in $csvDict.Keys) { $ExportObj[$key] = $csvDict[$key] }
            }
        }
    }

    if (-not $UseExisting) {
        # 2a. Username
        $validUser = $false
        do {
            $Username = Read-Host -Prompt "Enter Login Name (e.g., tenantadmin@cyberark.cloud.12345)"
            if ($Username -match 'X{3,}') { Write-Log "Please replace the 'X's with your actual 3 to 6 digit tenant suffix." -Level WARN }
            elseif ($Username -notmatch '^tenantadmin@cyberark\.cloud\.[\w-]*\d{3,6}$') { Write-Log "Invalid format!" -Level ERROR }
            else { $validUser = $true }
        } until ($validUser)

        # 2b. Subtenant
        $validSub = $false
        do {
            $Subtenant = Read-Host -Prompt "Enter Subtenant (e.g., acme-lab-12345)"
            if ($Subtenant -match 'X{3,}') { Write-Log "Please replace the 'X's with your actual 3 to 6 digit tenant suffix." -Level WARN }
            elseif ($Subtenant -notmatch '^[a-zA-Z0-9-]+?\d{3,6}$') { Write-Log "Invalid format!" -Level ERROR }
            else { $validSub = $true }
        } until ($validSub)

        # 2c. Resolve and Validate Identity URL 
        $PAMUrl = "https://${Subtenant}.cyberark.cloud/"
        Write-Log "Resolving Identity URL for $PAMUrl..." -Level INFO
        $IdentityURL = Get-IdentityURL -idURL $PAMUrl

        if ($IdentityURL -match "^Error:") {
            Write-Log "Failed to reach the PAM URL. $IdentityURL" -Level ERROR
            throw "Failed to resolve Identity URL."
        }

        $IdentityURL = "https://${IdentityURL}"
        Write-Log "Identity URL resolved: $IdentityURL" -Level SUCCESS
    }

    # 2d. Authenticate (Confirms Connection)
    Write-Log "Validating connection to tenant..." -Level INFO
    $ValidatedPassword = Get-IdentityToken -Identity_Url $IdentityURL -UserEmail $Username

    # ==============================================================================
    # 3. GENERATE USERS & EXPORT CSV (IF NEW)
    # ==============================================================================
    if (-not $UseExisting) {
        $TrainingUser = "training-support@" + $Username.Split('@')[1]
        $TrainingPwd  = Get-RandomPassword
        $TrainerUser  = "trainer@" + $Username.Split('@')[1]
        $TrainerPwd   = Get-RandomPassword

        Write-Host "`nIMPORTANT: If this is a Self-Paced course, please leave the default email address." -ForegroundColor Yellow
        Write-Host "Otherwise, you can input a custom email address for the trainer for direct support." -ForegroundColor Yellow

        $isValid = $false
        while (-not $isValid) {
            $InputEmail = Read-Host "Enter the Trainer's email (or press Enter to keep default)"
            if ([string]::IsNullOrWhiteSpace($InputEmail)) {
                $UsersToCreate += @{ Name = $TrainingUser; Mail = "cybr-training-labs+PAMSAAS_Trainer@paloaltonetworks.com"; Password = $TrainingPwd }
                $isValid = $true
            } else {
                try {
                    $mail = [mailaddress]$InputEmail
                    $UsersToCreate += @{ Name = $TrainerUser; Mail = $mail.Address; Password = $TrainerPwd }
                    $UsersToCreate += @{ Name = $TrainingUser; Mail = "cybr-training-labs+PAMSAAS_Trainer@paloaltonetworks.com"; Password = $TrainingPwd }
                    $isValid = $true
                } catch {
                    Write-Log "Invalid email format. Please enter a valid email address or press Enter for the default." -Level ERROR
                }
            }
        }

        $ExportObj = [ordered]@{
            Login             = $Username
            PAM_SaaS_Url      = $PAMUrl
            Identity_Url      = $IdentityURL
            Training_User     = $TrainingUser
            Training_User_Pwd = $TrainingPwd
        }
        if ($UsersToCreate.Count -gt 1) {
            $ExportObj.Add("Trainer_User", $TrainerUser)
            $ExportObj.Add("Trainer_User_Pwd", $TrainerPwd)
        }

        $ExportObj.GetEnumerator() | Select-Object @{Name="Field";Expression={$_.Name}}, Value | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Log "Tenant configuration saved to: $ExportPath" -Level SUCCESS
    }

    # ==============================================================================
    # 4. ENVIRONMENT SETUP: VERIFY USERS
    # ==============================================================================
    Write-Log "Provisioning / Verifying Training Account(s)..." -Level INFO
    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }

    $CreatedUserUuids = @()
    $UuidToNameMap = @{}

    foreach ($u in $UsersToCreate) {
        $checkUserBody = @{ Script = "SELECT ID, Username FROM User WHERE Username = '$($u.Name)'" } | ConvertTo-Json
        try {
            $checkUserRes = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $checkUserBody @RestArgs
            $existingUser = @($checkUserRes.Result.Results)

            if ($existingUser.Count -gt 0) {
                $userId = $existingUser[0].Row.ID
                $CreatedUserUuids += $userId
                $UuidToNameMap[$userId] = $u.Name
                Write-Log "Account verified: $($u.Name)." -Level SUCCESS
            } else {
                $body = @{
                    Name                    = $u.Name
                    Mail                    = $u.Mail
                    Password                = $u.Password
                    InEverybodyRole         = $true
                    InSysAdminRole          = $true
                    ForcePasswordChangeNext = $false
                    SendEmailInvite         = $true
                    SendSmsInvite           = $false
                    PasswordNeverExpire     = $true
                } | ConvertTo-Json -Depth 10

                $res = Invoke-RestMethod -Uri "$IdentityURL/CDirectoryService/CreateUser" -Headers $global:BaseHeaders -Body $body @RestArgs
                if ($res.success) {
                    $CreatedUserUuids += $res.Result
                    $UuidToNameMap[$res.Result] = $u.Name
                    Write-Log "User created: $($u.Name) ($($u.Mail))" -Level SUCCESS
                } else {
                    Write-Log "Failed to create user $($u.Name): $($res.Message)" -Level ERROR
                }
            }
        } catch {
            Write-Log "Failed to process user $($u.Name): $(Get-ApiErrorMessage -ExceptionRecord $_)" -Level ERROR
        }
    }

    # ==============================================================================
    # 5. ENVIRONMENT SETUP: ROLES & PERMISSIONS VERIFICATION
    # ==============================================================================
    $RolesToCheck = @("Safe Master", "Privilege Cloud Administrators")

    foreach ($RoleName in $RolesToCheck) {
        Write-Log "Verifying Role: $RoleName..." -Level INFO
        $queryBody = @{ Script = "SELECT Role.Description, Role.ID, Role.Name FROM Role WHERE Role.Name = '$RoleName'" } | ConvertTo-Json

        try {
            $queryResponse = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $queryBody @RestArgs
            $RoleID = $null
            $roleResults = @($queryResponse.Result.Results)

            if ($roleResults.Count -gt 0) {
                $RoleID = $roleResults[0].Row.ID
                Write-Log "Found existing role: $RoleName" -Level SUCCESS
            } else {
                if ($RoleName -eq "Safe Master") {
                    Write-Log "Role '$RoleName' missing. Creating..." -Level WARN
                    $body = @{ Name = "Safe Master"; Description = "Grant members permissions"; RoleType = "PrincipalList" } | ConvertTo-Json
                    $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/StoreRole" -Headers $global:BaseHeaders -Body $body @RestArgs
                    if ($res.success) {
                        $RoleID = $res.Result._RowKey
                        Write-Log "Role created: Safe Master" -Level SUCCESS
                        Start-Sleep -Seconds 3
                    } else {
                        Write-Log "Failed to create role: $($res.Message)" -Level ERROR
                        continue
                    }
                } else {
                    Write-Log "System Role '$RoleName' not found! Cannot verify members." -Level ERROR
                    continue
                }
            }

            # Check Role Members
            if (-not [string]::IsNullOrWhiteSpace($RoleID) -and $CreatedUserUuids.Count -gt 0) {
                $memberQuery = @{ Script = "SELECT User FROM RoleMember WHERE Role = '$RoleID'" } | ConvertTo-Json
                $memberRes = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $memberQuery @RestArgs
                $existingMembers = @($memberRes.Result.Results | Select-Object -ExpandProperty Row | Select-Object -ExpandProperty User)

                $missingUsers = @()
                foreach ($uid in $CreatedUserUuids) {
                    if ($uid -notin $existingMembers) {
                        Write-Log "WARN: User '$($UuidToNameMap[$uid])' is missing from '$RoleName'. Will assign now." -Level WARN
                        $missingUsers += $uid
                    } else {
                        Write-Log "User '$($UuidToNameMap[$uid])' is correctly assigned to '$RoleName'." -Level SUCCESS
                    }
                }

                if ($missingUsers.Count -gt 0) {
                    $body = @{ Users = @{ Add = $missingUsers }; Name = $RoleID } | ConvertTo-Json -Depth 10
                    $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/UpdateRole" -Headers $global:BaseHeaders -Body $body @RestArgs
                    if ($res.success) { 
                        Write-Log "Missing user(s) successfully added to '$RoleName'." -Level SUCCESS 
                    } else {
                        Write-Log "Failed to update role '$RoleName': $($res.Message)" -Level ERROR
                    }
                }
            }
        } catch {
            Write-Log "Error processing role '$RoleName': $(Get-ApiErrorMessage -ExceptionRecord $_)" -Level ERROR
        }
    }

    # ==============================================================================
    # 6. APPEND INSTALLER USER TO CSV
    # ==============================================================================
    $body = @{ Script = "SELECT ID, Username FROM User WHERE Username LIKE 'installeruser@%'" } | ConvertTo-Json
    try {
        $response = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $body @RestArgs
        $installerUserId = $null
        $installerUserName = $null
        $installerResults = @($response.Result.Results)

        if ($installerResults.Count -gt 0) {
            $installerUserId = $installerResults[0].Row.ID
            $installerUserName = $installerResults[0].Row.Username
        } else {
            Write-Log "Could not find the installeruser@... in the tenant." -Level WARN
        }

        # Check if already present in ExportObj before adding
        if (-not $ExportObj.Contains("Installer_User")) {
            $ExportObj.Add("Installer_User", $installerUserName)
            $ExportObj.Add("Installer_User_Pwd", "Paste Here")
            $ExportObj.Add("Installer_User_Id", $installerUserId)
            $ExportObj.GetEnumerator() | Select-Object @{Name="Field";Expression={$_.Name}}, Value | Export-Csv -Path $ExportPath -NoTypeInformation
        }

        Write-Log "--- Onboarding Complete ---" -Level SUCCESS
    } catch {
        Write-Log "Error querying installer user: $(Get-ApiErrorMessage -ExceptionRecord $_)" -Level ERROR
    }

} catch {
    Write-Log "Script execution halted due to a critical error: $($_.Exception.Message)" -Level ERROR
} finally {
    if ($global:BaseHeaders -and $global:BaseHeaders.ContainsKey("Authorization")) {
        Revoke-IdentityToken -Identity_Url $IdentityURL -BaseHeaders $global:BaseHeaders
    }
}
