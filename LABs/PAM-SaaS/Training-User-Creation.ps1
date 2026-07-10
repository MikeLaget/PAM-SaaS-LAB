# ==============================================================================
# 1. HELPER FUNCTIONS
# ==============================================================================
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
# 2. DATA COLLECTION & VALIDATION
# ==============================================================================
Write-Host "--- CyberArk Tenant Initialization ---" -ForegroundColor Cyan

# Username
$UserPattern = '^tenantadmin@cyberark\.cloud\.[\w]+$'
do {
    $Username = Read-Host -Prompt "Enter Login Name (tenantadmin@cyberark.cloud.XXXXX)"
    if ($Username -notmatch $UserPattern) { Write-Host "Invalid format! Must be tenantadmin@cyberark.cloud.XXXXX" -ForegroundColor Red }
} while ($Username -notmatch $UserPattern)

# Password (Secure Loop using .NET class)
$PasswordsMatch = $false
while (-not $PasswordsMatch) {
    $SecPass1 = Read-Host -Prompt "Enter password" -AsSecureString
    $SecPass2 = Read-Host -Prompt "Confirm password" -AsSecureString

    $Password  = [System.Net.NetworkCredential]::new("", $SecPass1).Password
    $Password2 = [System.Net.NetworkCredential]::new("", $SecPass2).Password

    if ($Password -eq $Password2 -and -not [string]::IsNullOrWhiteSpace($Password)) {
        $PasswordsMatch = $true
        Write-Host "[+] Passwords match." -ForegroundColor Green
    } else {
        Write-Host "[-] Passwords do not match or are blank. Try again." -ForegroundColor Red
    }
}

# Subtenant
$SubtenantPattern = '^[a-zA-Z0-9-]+$'
do {
    $Subtenant = Read-Host -Prompt "Enter Subtenant (e.g., acme-lab-XXXXX)"
    if ($Subtenant -notmatch $SubtenantPattern) { Write-Host "Invalid format!" -ForegroundColor Red }
} while ($Subtenant -notmatch $SubtenantPattern)

$PAMUrl = "https://${Subtenant}.cyberark.cloud/"

$IdentityURL = Get-IdentityURL -idURL $PAMUrl
$IdentityURL = "https://${IdentityURL}"

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
[PSCustomObject]$ExportObj | Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "`n[+] Tenant configuration saved to: $ExportPath" -ForegroundColor Green

# ==============================================================================
# 3. AUTHENTICATION (ITERATIVE MFA FLOW)
# ==============================================================================
Write-Host "`n--- Authenticating to CyberArk Identity ---" -ForegroundColor Cyan

$RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
$BaseHeaders = @{ "X-Idap-Native-Client" = "true" }
$IdentityID = ($IdentityURL -replace "https://", "").Split(".")[0]

Write-Host "[*] Starting authentication process..."
$bodyStart = @{ 
    TenantId = $IdentityID
    Version  = "1.0"
    User     = $Username 
} | ConvertTo-Json -Compress

$resStart = Invoke-RestMethod -Uri "$IdentityURL/Security/StartAuthentication" -Headers $BaseHeaders -Body $bodyStart @RestArgs

if (-not $resStart.Success -or -not $resStart.Result.Challenges) {
    Write-Error "Failed to start authentication or no challenges returned."
    exit
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
    Answer      = $Password
} | ConvertTo-Json -Compress

$resPwd = Invoke-RestMethod -Uri "$IdentityURL/Security/AdvanceAuthentication" -Headers $BaseHeaders -Body $bodyPwd @RestArgs

if (-not $resPwd.Success -or $resPwd.Result.Summary -eq "LoginFailed") {
    Write-Error "Authentication failed: Incorrect password."
    exit
}

# Auth Step 3: Trigger MFA (OOB)
Write-Host "[*] Triggering MFA Challenge..."
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
    exit
}

# ==============================================================================
# 4. ENVIRONMENT SETUP: USER & SAFE MASTER ROLE
# ==============================================================================
Write-Host "`n--- Provisioning the Training Account(s) ---" -ForegroundColor Cyan

$CreatedUserUuids = @()

foreach ($u in $UsersToCreate) {
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
    }
}

# Check if Safe Master Role already exists using Redrock
$queryBody = @{ Script = "SELECT Role.Description, Role.ID, Role.Name FROM Role WHERE Role.Name = 'Safe Master'" } | ConvertTo-Json
$queryResponse = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $queryBody @RestArgs

$RoleID = $null
if ($queryResponse.Result.Results.Count -gt 0 -and $queryResponse.Result.Results[0].Entities.Count -gt 0) {
    $RoleID = $queryResponse.Result.Results[0].Entities[0].Key
}

if (-not [string]::IsNullOrWhiteSpace($RoleID)) {
    Write-Host "[+] Found existing Safe Master Role ID: $RoleID" -ForegroundColor Green
} else {
    # Create Safe Master Role
    $body = @{ Name = "Safe Master"; Description = "Grant members permissions"; RoleType = "PrincipalList" } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/StoreRole" -Headers $BaseHeaders -Body $body @RestArgs
    if ($res.success) {
        $RoleID = $res.Result._RowKey
        Write-Host "[+] Role created: Safe Master" -ForegroundColor Green
    } else {
        Write-Host "[-] Failed to create role: $($res.Message)" -ForegroundColor Red
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
    }
} else {
    Write-Host "[-] Role creation failed or no users to add." -ForegroundColor Red
}

# ==============================================================================
# 5. ASSIGN PRIVILEGE CLOUD ADMINISTRATORS ROLE
# ==============================================================================
Write-Host "`n--- Assigning Privilege Cloud Administrators Role ---" -ForegroundColor Cyan

# Query Redrock for the Role ID
$body = @{ Script = "SELECT Role.Description, Role.ID, Role.Name FROM Role WHERE Role.Name = 'Privilege Cloud Administrators'" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $body @RestArgs

# Extract the Role ID
$PrivCloudAdmins = $null
if ($response.Result.Results.Count -gt 0 -and $response.Result.Results[0].Entities.Count -gt 0) {
    $PrivCloudAdmins = $response.Result.Results[0].Entities[0].Key
}

if (-not [string]::IsNullOrWhiteSpace($PrivCloudAdmins) -and $CreatedUserUuids.Count -gt 0) {
    Write-Host "[+] Found Privilege Cloud Admins Role ID: $PrivCloudAdmins" -ForegroundColor Green

    # Grant membership to all created users
    $authBody = @{ Users = @{ Add = $CreatedUserUuids }; Name = $PrivCloudAdmins } | ConvertTo-Json -Depth 10
    $response = Invoke-RestMethod -Uri "$IdentityURL/Roles/UpdateRole" -Headers $BaseHeaders -Body $authBody @RestArgs

    if ($response.success) {
        Write-Host "[+] User(s) successfully added to Privilege Cloud Administrators!" -ForegroundColor Green
    } else {
        Write-Host "[-] API Error while adding to role: $($response.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "[-] Failed: Could not find 'Privilege Cloud Administrators'." -ForegroundColor Yellow
}

$body = @{ Script = "SELECT ID, Username FROM User WHERE Username LIKE 'installeruser@%'" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $BaseHeaders -Body $body @RestArgs
$installerUserId = $response.Result.Results.Row.ID
$installerUserName = $response.Result.Results.Row.Username

# Overwrite CSV on Desktop to include the Installer info
$ExportObj.Add("Installer_User", $installerUserName)
$ExportObj.Add("Installer_User_Pwd", "Paste Here")
$ExportObj.Add("Installer_User_Id", $installerUserId)

[PSCustomObject]$ExportObj | Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "`n--- Onboarding Complete ---" -ForegroundColor Cyan
