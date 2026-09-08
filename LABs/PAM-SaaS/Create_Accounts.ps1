<#
.SYNOPSIS
Overview for Students:
This is the Bootstrapping Script. It is responsible for setting up the foundational Identity layer of your lab environment. It creates your specific training accounts, generates random passwords, and assigns the correct administrative roles so you have the necessary access to perform the rest of the labs.

Key Learning Concepts in this Script:

Dot-Sourcing: At the very top, you will see . .\PAM_Library.ps1. This is how PowerShell imports external libraries, giving this script access to all the tools we built in the library.
Idempotent Execution: The script is designed to be run multiple times safely. It first looks for a tenantadmin.csv file. If you already ran the script, it asks if you want to verify the existing setup rather than creating everything from scratch.
Identity & Access Management (IAM): The script interacts with the backend Identity service to:
1. Check if your training users exist, and create them if they don't.
2. Check if a specific role ("Safe Master") exists, and create it if missing.
3. Add your newly created training users into the "Privilege Cloud Administrators" and "Safe Master" roles.
State Tracking: It exports a .csv file to your desktop containing the generated passwords and user IDs. This acts as a database for the next script to use.
v26-09-07
#>

# Load the external library dynamically based on script location
$libraryPath = Join-Path -Path $PSScriptRoot -ChildPath "PAM_Library.ps1"
. $libraryPath

# Config
$global:EnableFileLogging = $true
$global:EnableDebugMode   = $false
$global:LogFilePath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath "TenantAdmin_Provisioning_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ExportPath = Join-Path -Path ([Environment]::GetFolderPath("Desktop")) -ChildPath "tenantadmin.csv"

try {
    if ($global:EnableFileLogging) { Write-Log "Logging initialized. File: $global:LogFilePath" -Level INFO }
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

                $UsersToCreate += @{ Name = $csvDict["Training_User"]; Mail = "cybr-training-labs+PAMSAAS_Trainer@paloaltonetworks.com"; Password = $csvDict["Training_User_Pwd"] }
                if ($csvDict.Contains("Trainer_User") -and -not [string]::IsNullOrWhiteSpace($csvDict["Trainer_User"])) {
                    $UsersToCreate += @{ Name = $csvDict["Trainer_User"]; Mail = "trainer@placeholder.com"; Password = $csvDict["Trainer_User_Pwd"] }
                }
                foreach ($key in $csvDict.Keys) { $ExportObj[$key] = $csvDict[$key] }
            }
        }
    }

    if (-not $UseExisting) {
        $validUser = $false
        do {
            $Username = Read-Host -Prompt "Enter Login Name (e.g., tenantadmin@cyberark.cloud.12345)"
            if ($Username -notmatch '^tenantadmin@cyberark\.cloud\.[\w-]*\d{3,6}$') { Write-Log "Invalid format!" -Level ERROR }
            else { $validUser = $true }
        } until ($validUser)

        $validSub = $false
        do {
            $Subtenant = Read-Host -Prompt "Enter Subtenant (e.g., acme-lab-12345)"
            if ($Subtenant -notmatch '^[a-zA-Z0-9-]+?\d{3,6}$') { Write-Log "Invalid format!" -Level ERROR }
            else { $validSub = $true }
        } until ($validSub)

        $PAMUrl = "https://${Subtenant}.cyberark.cloud/"
        Write-Log "Resolving Identity URL for $PAMUrl..." -Level INFO
        $IdentityURL = Get-IdentityURL -idURL $PAMUrl

        if ($IdentityURL -match "^Error:") { throw "Failed to resolve Identity URL: $IdentityURL" }
        $IdentityURL = "https://${IdentityURL}"
        Write-Log "Identity URL resolved: $IdentityURL" -Level SUCCESS
    }

    Write-Log "Validating connection to tenant..." -Level INFO
    $ValidatedPassword = Get-IdentityToken -Identity_Url $IdentityURL -UserEmail $Username

    if (-not $UseExisting) {
        $TrainingUser = "training-support@" + $Username.Split('@')[1]
        $TrainingPwd  = Get-RandomPassword
        $TrainerUser  = "trainer@" + $Username.Split('@')[1]
        $TrainerPwd   = Get-RandomPassword

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
                } catch { Write-Log "Invalid email format." -Level ERROR }
            }
        }

        $ExportObj = [ordered]@{ Login = $Username; PAM_SaaS_Url = $PAMUrl; Identity_Url = $IdentityURL; Training_User = $TrainingUser; Training_User_Pwd = $TrainingPwd }
        if ($UsersToCreate.Count -gt 1) { $ExportObj.Add("Trainer_User", $TrainerUser); $ExportObj.Add("Trainer_User_Pwd", $TrainerPwd) }

        $ExportObj.GetEnumerator() | Select-Object @{Name="Field";Expression={$_.Name}}, Value | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Log "Tenant configuration saved to: $ExportPath" -Level SUCCESS
    }

    Write-Log "Provisioning / Verifying Training Account(s)..." -Level INFO
    $RestArgs = @{ Method = 'POST'; ContentType = 'application/json' }
    $CreatedUserUuids = @()
    $UuidToNameMap = @{}

    foreach ($u in $UsersToCreate) {
        $checkUserBody = @{ Script = "SELECT ID, Username FROM User WHERE Username = '$($u.Name)'" } | ConvertTo-Json
        $checkUserRes = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $checkUserBody @RestArgs
        $existingUser = @($checkUserRes.Result.Results)

        if ($existingUser.Count -gt 0) {
            $userId = $existingUser[0].Row.ID
            $CreatedUserUuids += $userId
            $UuidToNameMap[$userId] = $u.Name
            Write-Log "Account verified: $($u.Name)." -Level SUCCESS
        } else {
            $body = @{ Name = $u.Name; Mail = $u.Mail; Password = $u.Password; InEverybodyRole = $true; InSysAdminRole = $true; ForcePasswordChangeNext = $false; SendEmailInvite = $true; SendSmsInvite = $false; PasswordNeverExpire = $true } | ConvertTo-Json -Depth 10
            $res = Invoke-RestMethod -Uri "$IdentityURL/CDirectoryService/CreateUser" -Headers $global:BaseHeaders -Body $body @RestArgs
            if ($res.success) {
                $CreatedUserUuids += $res.Result
                $UuidToNameMap[$res.Result] = $u.Name
                Write-Log "User created: $($u.Name)" -Level SUCCESS
            }
        }
    }

    $RolesToCheck = @("Safe Master", "Privilege Cloud Administrators")
    foreach ($RoleName in $RolesToCheck) {
        Write-Log "Verifying Role: $RoleName..." -Level INFO
        $queryBody = @{ Script = "SELECT Role.Description, Role.ID, Role.Name FROM Role WHERE Role.Name = '$RoleName'" } | ConvertTo-Json
        $queryResponse = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $queryBody @RestArgs
        $roleResults = @($queryResponse.Result.Results)
        $RoleID = $null

        if ($roleResults.Count -gt 0) {
            $RoleID = $roleResults[0].Row.ID
            Write-Log "Found existing role: $RoleName" -Level SUCCESS
        } else {
            if ($RoleName -eq "Safe Master") {
                $body = @{ Name = "Safe Master"; Description = "Grant members permissions"; RoleType = "PrincipalList" } | ConvertTo-Json
                $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/StoreRole" -Headers $global:BaseHeaders -Body $body @RestArgs
                if ($res.success) { $RoleID = $res.Result._RowKey; Start-Sleep -Seconds 3; Write-Log "Role created: Safe Master" -Level SUCCESS }
            } else { Write-Log "System Role '$RoleName' not found! Cannot verify members." -Level ERROR; continue }
        }

        if (-not [string]::IsNullOrWhiteSpace($RoleID) -and $CreatedUserUuids.Count -gt 0) {
            $memberQuery = @{ Script = "SELECT User FROM RoleMember WHERE Role = '$RoleID'" } | ConvertTo-Json
            $memberRes = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $memberQuery @RestArgs
            $existingMembers = @($memberRes.Result.Results | Select-Object -ExpandProperty Row | Select-Object -ExpandProperty User)

            $missingUsers = @()
            foreach ($uid in $CreatedUserUuids) {
                if ($uid -notin $existingMembers) { Write-Log "WARN: User '$($UuidToNameMap[$uid])' missing from '$RoleName'." -Level WARN; $missingUsers += $uid }
            }

            if ($missingUsers.Count -gt 0) {
                $body = @{ Users = @{ Add = $missingUsers }; Name = $RoleID } | ConvertTo-Json -Depth 10
                $res = Invoke-RestMethod -Uri "$IdentityURL/Roles/UpdateRole" -Headers $global:BaseHeaders -Body $body @RestArgs
                if ($res.success) { Write-Log "Missing user(s) added to '$RoleName'." -Level SUCCESS }
            }
        }
    }

    $body = @{ Script = "SELECT ID, Username FROM User WHERE Username LIKE 'installeruser@%'" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$IdentityURL/Redrock/query" -Headers $global:BaseHeaders -Body $body @RestArgs
    $installerResults = @($response.Result.Results)

    if ($installerResults.Count -gt 0 -and -not $ExportObj.Contains("Installer_User")) {
        $ExportObj.Add("Installer_User", $installerResults[0].Row.Username)
        $ExportObj.Add("Installer_User_Pwd", "Paste Here")
        $ExportObj.Add("Installer_User_Id", $installerResults[0].Row.ID)
        $ExportObj.GetEnumerator() | Select-Object @{Name="Field";Expression={$_.Name}}, Value | Export-Csv -Path $ExportPath -NoTypeInformation
    }

    Write-Log "--- Onboarding Complete ---" -Level SUCCESS
} catch {
    Write-Log "Script execution halted due to a critical error: $($_.Exception.Message)" -Level ERROR
} finally {
    if ($global:BaseHeaders -and $global:BaseHeaders.ContainsKey("Authorization")) {
        Revoke-IdentityToken -Identity_Url $IdentityURL -BaseHeaders $global:BaseHeaders
    }
}
