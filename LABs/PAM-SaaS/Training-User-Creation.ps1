# ==============================================================================
# Training support account creation v26-07-22
# ==============================================================================

# ==============================================================================
# 1. HELPER FUNCTIONS
# ==============================================================================
$ErrorLogPath = Join-Path -Path "$HOME\Desktop" -ChildPath "Tenant.log"

function Write-ErrorLog {
    param ([string]$Message)
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$Timestamp - ERROR: $Message" | Out-File -FilePath $ErrorLogPath -Append
}

function Get-RandomPassword {
    [CmdletBinding()]
    Param([int]$Length = 20)

    $Upper   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    $Lower   = "abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $Numbers = "0123456789".ToCharArray()
    $Special = "!#$%&*?".ToCharArray()

    # Guarantee at least one of each type
    $Base = @($Upper | Get-Random), @($Lower | Get-Random), @($Numbers | Get-Random), @($Special | Get-Random)

    # Fill the rest
    $Pool = $Upper + $Lower + $Numbers + $Special
    $Base += 1..($Length - 4) | ForEach-Object { $Pool | Get-Random }

    return ($Base | Get-Random -Count $Length) -join ""
}

Function Get-IdentityURL($idURL) {
    Add-Type -AssemblyName System.Net.Http

    Function CreateHttpClient($allowAutoRedirect) {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $allowAutoRedirect
        return New-Object System.Net.Http.HttpClient($handler)
    }

    $client = CreateHttpClient($true)

    try {
        $task = $client.GetAsync($idURL)
        $task.Wait()  # Ensures the task completes and exceptions are thrown if any.

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
    }
    catch {
        # Extracting detailed exception message from AggregateException
        $exception = $_.Exception
        while ($exception.InnerException) {
            $exception = $exception.InnerException
        }

        # Return the extracted exception message
        return "Error: $($exception.Message)"
    }
    finally {
        if ($client -ne $null) {
            $client.Dispose()
        }
    }
}

# ==============================================================================
# 2. DATA COLLECTION & PRE-FLIGHT CHECKS
# ==============================================================================
Write-Host "--- Idira Tenant Initialization ---" -ForegroundColor Cyan

# 2a. Username
$validUser = $false
do {
    $Username = Read-Host -Prompt "Enter Login Name (e.g., tenantadmin@cyberark.cloud.12345)"
    
    if ($Username -match 'X{3,}') { 
        Write-Host "Please replace the 'X's with your actual 3 to 6 digit tenant suffix." -ForegroundColor Yellow
        Write-ErrorLog "User entered literal 'X's in username: $Username" 
    } elseif ($Username -notmatch '^tenantadmin@cyberark\.cloud\.[\w-]*\d{3,6}$') { 
        Write-Host "Invalid format! Must be tenantadmin@cyberark.cloud.<suffix> (ending in 3 to 6 digits)" -ForegroundColor Red
        Write-ErrorLog "Invalid username format provided: $Username" 
    } else {
        $validUser = $true
    }
} until ($validUser)

# 2b. Subtenant
$validSub = $false
do {
    $Subtenant = Read-Host -Prompt "Enter Subtenant (e.g., acme-lab-12345)"
    
    if ($Subtenant -match 'X{3,}') { 
        Write-Host "Please replace the 'X's with your actual 3 to 6 digit tenant suffix." -ForegroundColor Yellow
        Write-ErrorLog "User entered literal 'X's in subtenant: $Subtenant" 
    } elseif ($Subtenant -notmatch '^[a-zA-Z0-9-]+?\d{3,6}$') { 
        Write-Host "Invalid format! Subtenant should contain alphanumeric characters/hyphens and end with 3 to 6 digits." -ForegroundColor Red 
        Write-ErrorLog "Invalid subtenant format provided: $Subtenant" 
    } else {
        $validSub = $true
    }
} until ($validSub)

# 2c. Resolve and Validate Identity URL 
$PAMUrl = "https://${Subtenant}.cyberark.cloud/"
Write-Host "[*] Resolving Identity URL for $PAMUrl..."
$IdentityURL = Get-IdentityURL -idURL $PAMUrl

if ($IdentityURL -match "^Error:") {
    Write-Host "[-] Failed to reach the PAM URL. $IdentityURL" -ForegroundColor Red
    Write-Host "[-] Please verify that the subtenant '$Subtenant' is correct and active." -ForegroundColor Yellow
    Write-ErrorLog "Failed to reach PAM URL: $IdentityURL for subtenant $Subtenant"
    exit
}

$IdentityURL = "https://${IdentityURL}"
Write-Host "[+] Identity URL resolved: $IdentityURL" -ForegroundColor Green

# Setup Authentication variables
$RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
$BaseHeaders = @{ "X-Idap-Native-Client" = "true" }
$IdentityID = ($IdentityURL -replace "https://", "").Split(".")[0]

$IsAuthenticated = $false
$SessionId = $null
$MechanismId_Mfa = $null
$Password = $null

# 2d. Password Validation Loop (Verifies directly against the Identity API)
while (-not $IsAuthenticated) {
    $SecPass1 = Read-Host -Prompt "Enter password" -AsSecureString
    $SecPass2 = Read-Host -Prompt "Confirm password" -AsSecureString

    $PasswordTest  = [System.Net.NetworkCredential]::new("", $SecPass1).Password
    $PasswordTest2 = [System.Net.NetworkCredential]::new("", $SecPass2).Password

    if ($PasswordTest -eq $PasswordTest2 -and -not [string]::IsNullOrWhiteSpace($PasswordTest)) {
        Write-Host "[*] Verifying credentials with Idira Identity..." -ForegroundColor Cyan

        $bodyStart = @{ TenantId = $IdentityID; Version = "1.0"; User = $Username } | ConvertTo-Json -Compress
        try {
            $resStart = Invoke-RestMethod -Uri "$IdentityURL/Security/StartAuthentication" -Headers $BaseHeaders -Body $bodyStart @RestArgs

            if ($resStart.Success -and $resStart.Result.Challenges) {
                $SessionId = $resStart.Result.SessionId
                $MechanismId_Pwd = $resStart.Result.Challenges[0].Mechanisms[0].MechanismId
                $MechanismId_Mfa = $resStart.Result.Challenges[1].Mechanisms[0].MechanismId

                $bodyPwd = @{
                    TenantId    = $IdentityID
                    SessionId   = $SessionId
                    MechanismId = $MechanismId_Pwd
                    Action      = "Answer"
                    Answer      = $PasswordTest
                } | ConvertTo-Json -Compress

                $resPwd = Invoke-RestMethod -Uri "$IdentityURL/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyPwd @RestArgs

                if ($resPwd.Success -and $resPwd.Result.Summary -ne "LoginFailed") {
                    Write-Host "[+] Password verified successfully!" -ForegroundColor Green
                    $Password = $PasswordTest # Lock in the valid password
                    $IsAuthenticated = $true
                } else {
                    Write-Host "[-] Incorrect password. Please try again." -ForegroundColor Red
                    Write-ErrorLog "Incorrect password attempt for user $Username"
                }
            } else {
                Write-Host "[-] Failed to start authentication. Check your username/tenant." -ForegroundColor Red
                Write-ErrorLog "Failed to start authentication for user $Username"
            }
        } catch {
            Write-Host "[-] API Connection error: $_" -ForegroundColor Red
            Write-Host "[-] Will prompt for password again..." -ForegroundColor Yellow
            Write-ErrorLog "API Connection error during auth: $_"
        }
    } else {
        Write-Host "[-] Passwords do not match or are blank. Try again." -ForegroundColor Red
    }
}

# ==============================================================================
# 3. GENERATE USERS & EXPORT CSV
# ==============================================================================
# Generate Training & Trainer Info
$TrainingUser = "training-support@" + $Username.Split('@')[1]
$TrainingPwd  = Get-RandomPassword
$TrainerUser  = "trainer@" + $Username.Split('@')[1]
$TrainerPwd   = Get-RandomPassword

Write-Host "`nIMPORTANT: If this is a Self-Paced course, please leave the default email address." -ForegroundColor Yellow
Write-Host "Otherwise, you can input a custom email address for the trainer for direct support." -ForegroundColor Yellow
Write-Host "If a custom email is provided, two accounts (training-support and trainer) will be created." -ForegroundColor Yellow

$isValid = $false
$UsersToCreate = @()

while (-not $isValid) {
    $InputEmail = Read-Host "Enter the Trainer's email (or press Enter to keep default)"

    # Check if the user just pressed Enter (empty input)
    if ([string]::IsNullOrWhiteSpace($InputEmail)) {
        $UsersToCreate += @{
            Name     = $TrainingUser
            Mail     = "cybr-training-labs+PAMSAAS_Trainer@paloaltonetworks.com"
            Password = $TrainingPwd
        }
        $isValid = $true
    } else {
        # Try to cast the input to a valid mail address
        try {
            $mail = [mailaddress]$InputEmail

            # 1. Create the custom Trainer user
            $UsersToCreate += @{
                Name     = $TrainerUser
                Mail     = $mail.Address
                Password = $TrainerPwd
            }

            # 2. Create the default Training user
            $UsersToCreate += @{
                Name     = $TrainingUser
                Mail     = "cybr-training-labs+PAMSAAS_Trainer@paloaltonetworks.com"
                Password = $TrainingPwd
            }
            $isValid = $true
        } catch {
            Write-Host "Invalid email format. Please enter a valid email address or press Enter for the default." -ForegroundColor Red
            Write-ErrorLog "Invalid trainer email format entered: $InputEmail"
        }
    }
}

# Base CSV object
$ExportObj = [ordered]@{
    Login             = $Username
    PAM_SaaS_Url      = $PAMUrl
    Identity_Url      = $IdentityURL
    Training_User     = $TrainingUser
    Training_User_Pwd = $TrainingPwd
}

# If two users are being created, add the Trainer info to the CSV
if ($UsersToCreate.Count -gt 1) {
    $ExportObj.Add("Trainer_User", $TrainerUser)
    $ExportObj.Add("Trainer_User_Pwd", $TrainerPwd)
}

# Export initial CSV to Desktop
$ExportPath = Join-Path -Path "$HOME\Desktop" -ChildPath "TenantAdmin.csv"
$ExportObj.GetEnumerator() | Select-Object @{Name="Field";Expression={$_.Name}}, Value | Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "`n[+] Tenant configuration saved to: $ExportPath" -ForegroundColor Green

# ==============================================================================
# 4. AUTHENTICATION (FINISH MFA FLOW)
# ==============================================================================
Write-Host "`n--- Triggering MFA for Identity ---" -ForegroundColor Cyan

# Auth Step 3: Trigger MFA (OOB)
$bodyMfa = @{
    TenantID    = $IdentityID
    SessionId   = $SessionId
    MechanismId = $MechanismId_Mfa
    Action      = "StartOOB"
} | ConvertTo-Json -Compress

$resMfa = Invoke-RestMethod -Uri "$IdentityURL/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyMfa @RestArgs

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

    $pollResponse = Invoke-RestMethod -Uri "$IdentityURL/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $pollBody @RestArgs
}

if ($pollResponse.Success -and -not [string]::IsNullOrEmpty($pollResponse.Result.Token)) {
    $UToken = $pollResponse.Result.Token
    $BaseHeaders.Add("Authorization", "Bearer $UToken")
    Write-Host "[+] Authentication Successful!" -ForegroundColor Green
} else {
    Write-Error "Authentication failed: MFA approval failed or timed out."
    Write-ErrorLog "Authentication failed: MFA approval failed or timed out."
    exit
}

# ==============================================================================
# 5. ENVIRONMENT SETUP: USER & SAFE MASTER ROLE
# ==============================================================================
Write-Host "`n--- Provisioning the Training Account(s) ---" -ForegroundColor Cyan

$CreatedUserUuids = @()

foreach ($u in $UsersToCreate) {
    # Verify if the user already exists before attempting creation
    $checkUserBody = @{ Script = "SELECT ID, Username FROM User WHERE Username = '$($u.Name)'" } | ConvertTo-Json
    $checkUserRes = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $checkUserBody @RestArgs
    
    $existingUser = @($checkUserRes.Result.Results)
    
    if ($existingUser.Count -gt 0) {
        $userId = $existingUser[0].Row.ID
        $CreatedUserUuids += $userId
        Write-Host "[i] Account already exists: $($u.Name). Skipping creation and using existing account." -ForegroundColor Cyan
    } else {
        # Create user
        $body = @{
            Name                    = $u.Name
            Mail                    = $u.Mail
            Password                = $u.Password
            InEverybodyRole         = $true
            InSysAdminRole          = $true  # Grants System Admin
            ForcePasswordChangeNext = $false
            SendEmailInvite         = $true
            SendSmsInvite           = $false
            PasswordNeverExpire     = $true
        } | ConvertTo-Json -Depth 10

        $res = Invoke-RestMethod -Uri "$IdentityURL/CDirectoryService/CreateUser" -Headers $BaseHeaders -Body $body @RestArgs
        if ($res.success) {
            $CreatedUserUuids += $res.Result
            Write-Host "[+] User created: $($u.Name) ($($u.Mail))" -ForegroundColor Green
        } else {
            Write-Host "[-] Failed to create user $($u.Name): $($res.Message)" -ForegroundColor Red
            Write-ErrorLog "Failed to create user $($u.Name): $($res.Message)"
        }
    }
}

# Check if Safe Master Role already exists using Redrock
$queryBody = @{ Script = "SELECT Role.Description, Role.ID, Role.Name FROM Role WHERE Role.Name = 'Safe Master'" } | ConvertTo-Json
$queryResponse = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $queryBody @RestArgs

$RoleID = $null
$safeMasterResults = @($queryResponse.Result.Results)

if ($safeMasterResults.Count -gt 0) {
    $RoleID = $safeMasterResults[0].Row.ID
}

if (-not [string]::IsNullOrWhiteSpace($RoleID)) {
    Write-Host "[i] Role already exists: Safe Master (No need to recreate)" -ForegroundColor Cyan
} else {
    # Create Safe Master Role
    $body = @{ Name = "Safe Master"; Description = "Grant members permissions"; RoleType = "PrincipalList" } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/StoreRole" -Headers $BaseHeaders -Body $body @RestArgs
    if ($res.success) {
        $RoleID = $res.Result._RowKey
        Write-Host "[+] Role created: Safe Master" -ForegroundColor Green
    } else {
        Write-Host "[-] Failed to create role: $($res.Message)" -ForegroundColor Red
        Write-ErrorLog "Failed to create Safe Master role: $($res.Message)"
    }

    Start-Sleep -Seconds 3 # Give Identity backend a moment to sync
}

# Assign User(s) to Safe Master Role
if (-not [string]::IsNullOrWhiteSpace($RoleID) -and $CreatedUserUuids.Count -gt 0) {
    $body = @{ Users = @{ Add = $CreatedUserUuids }; Name = $RoleID } | ConvertTo-Json -Depth 10
    $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/UpdateRole" -Headers $BaseHeaders -Body $body @RestArgs
    if ($res.success) { 
        Write-Host "[+] User(s) added to Safe Master role!" -ForegroundColor Green 
    } else {
        Write-Host "[-] Failed to add user(s) to the Safe Master role." -ForegroundColor Red
        Write-ErrorLog "Failed to add user(s) to the Safe Master role: $($res.Message)"
    }
} else {
    Write-Host "[-] Role creation failed or no users to add." -ForegroundColor Red
    Write-ErrorLog "Safe Master role creation failed or no users available to add."
}

# ==============================================================================
# 6. ASSIGN PRIVILEGE CLOUD ADMINISTRATORS ROLE
# ==============================================================================
Write-Host "`n--- Assigning Privilege Cloud Administrators Role ---" -ForegroundColor Cyan

# Query Redrock for the Role ID
$body = @{ Script = "SELECT Role.Description, Role.ID, Role.Name FROM Role WHERE Role.Name = 'Privilege Cloud Administrators'" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $body @RestArgs

# Extract the Role ID
$PrivCloudAdmins = $null
$privCloudResults = @($response.Result.Results)

if ($privCloudResults.Count -gt 0) {
    $PrivCloudAdmins = $privCloudResults[0].Row.ID
}

if (-not [string]::IsNullOrWhiteSpace($PrivCloudAdmins)) {
    Write-Host "[i] Found Role: Privilege Cloud Administrators" -ForegroundColor Cyan

    # Verify we actually have users to add before sending the update
    if ($null -ne $CreatedUserUuids -and $CreatedUserUuids.Count -gt 0) {
        # Grant membership to all created users
        $authBody = @{ Users = @{ Add = $CreatedUserUuids }; Name = $PrivCloudAdmins } | ConvertTo-Json -Depth 10
        $updateResponse = Invoke-RestMethod -Uri "$IdentityURL/Roles/UpdateRole" -Headers $BaseHeaders -Body $authBody @RestArgs

        if ($updateResponse.success) {
            Write-Host "[+] User(s) successfully added to Privilege Cloud Administrators!" -ForegroundColor Green
        } else {
            Write-Host "[-] API Error while adding to role: $($updateResponse.Message)" -ForegroundColor Red
            Write-ErrorLog "API Error while adding to Privilege Cloud Administrators role: $($updateResponse.Message)"
        }
    } else {
        Write-Host "[-] No users available to add to the role." -ForegroundColor Yellow
        Write-ErrorLog "No users available to add to the Privilege Cloud Administrators role."
    }
} else {
    Write-Host "[-] Failed: Could not find 'Privilege Cloud Administrators'." -ForegroundColor Red
    Write-ErrorLog "Failed: Could not find 'Privilege Cloud Administrators' role via Redrock."
}

$body = @{ Script = "SELECT ID, Username FROM User WHERE Username LIKE 'installeruser@%'" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $body @RestArgs

# Safely extract installer user details
$installerUserId = $null
$installerUserName = $null
$installerResults = @($response.Result.Results)

if ($installerResults.Count -gt 0) {
    $installerUserId = $installerResults[0].Row.ID
    $installerUserName = $installerResults[0].Row.Username
} else {
    Write-Host "[-] Could not find the installeruser." -ForegroundColor Yellow
    Write-ErrorLog "Could not find installeruser@... in the tenant."
}

# Overwrite CSV on Desktop to include the Installer info
$ExportObj.Add("Installer_User", $installerUserName)
$ExportObj.Add("Installer_User_Pwd", "Paste Here")
$ExportObj.Add("Installer_User_Id", $installerUserId)

$ExportObj.GetEnumerator() | Select-Object @{Name="Field";Expression={$_.Name}}, Value | Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "`n--- Onboarding Complete ---" -ForegroundColor Cyan

