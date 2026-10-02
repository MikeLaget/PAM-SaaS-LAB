# Intro / description
#v26-10-2

Write-Host "`nIdira Bulk Account Actions" -ForegroundColor Cyan
Write-Host "=============================`n" -ForegroundColor Cyan

Write-Host "This script performs bulk account actions." -ForegroundColor Yellow
Write-Host "You can set accounts in safes to reconcile, change, or verify." -ForegroundColor Yellow
Write-Host "Note: This script will only work for accounts in the domain *.acme.corp`n" -ForegroundColor Yellow

$subdomain = Read-Host "Enter your tenant subdomain eg acme-lab-xxxx"
$addressdomain = Read-Host "Enter your internal domain name eg acme.corp"

$PcloudURL = "https://$subdomain.cyberark.cloud"
$PVWAURL = "https://$subdomain.privilegecloud.cyberark.cloud/PasswordVault/"

function Get-IdentityURL {
    [OutputType([System.String])]
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Base URL of the Idira Identity platform',
            ValueFromPipelineByPropertyName = $true)]
        [string]$PCloudURL,
        [Parameter(ValueFromRemainingArguments = $true,
            DontShow = $true)]
        $CatchAll
    )
    Begin {
        $PSBoundParameters.Remove('CatchAll') | Out-Null
        $PCloudURL -match '^(?:https|http):\/\/(?<sub>.*).privilegecloud.cyberark.(?<top>cloud|com)\/PasswordVault.*$' | Out-Null
        $PCloudBaseURL = "https://$($matches['sub']).cyberark.$($matches['top'])"
    }
    Process {
        $invokeWebRequestParams = @{
            Uri = $PCloudBaseURL
            UseBasicParsing = $true
        }

        $response = Invoke-WebRequest @invokeWebRequestParams

        # Cross-compatibility for extracting the redirect URL in Windows PowerShell 5.1 vs PowerShell 7+
        if ($null -ne $response.BaseResponse -and $null -ne $response.BaseResponse.RequestMessage) {
            # PowerShell 7+
            $IdentityBaseURL = $response.BaseResponse.RequestMessage.RequestUri.Host
        } elseif ($null -ne $response.BaseResponse -and $null -ne $response.BaseResponse.ResponseUri) {
            # Windows PowerShell 5.1
            $IdentityBaseURL = $response.BaseResponse.ResponseUri.Host
        } else {
            # Fallback if both fail
            $IdentityBaseURL = "$($matches['sub']).id.cyberark.$($matches['top'])"
        }
    }
    end {
        # Return the Identity URL
        $IdentityURL = "https://$IdentityBaseURL"
        return $IdentityURL
    }
}

$IdentityTenantFullURL = Get-IdentityURL -PCloudURL $PVWAURL

Write-Host "`nIdira Tenant URLs" -ForegroundColor Cyan
Write-Host "====================`n" -ForegroundColor Cyan

Write-Host "PAM SaaS Portal URL : " -NoNewline
Write-Host $PcloudURL -ForegroundColor Green

Write-Host "PAM SaaS API URL    : " -NoNewline
Write-Host $PVWAURL -ForegroundColor Green

Write-Host "Identity Tenant URL: " -NoNewline
Write-Host $IdentityTenantFullURL -ForegroundColor Green

Write-Host "Internal Domain Name: " -NoNewline
Write-Host $addressdomain -ForegroundColor Green

$IdentityTenantURL = $IdentityTenantFullURL.Substring(8)

# Prompt for the username
$IdentityUser = Read-Host "Enter your Idira Identity username (e.g., mike@acme.corp)"
Write-Host "Using Identity user: $IdentityUser" -ForegroundColor Green

Import-Module 'C:\Scripts\epv-api-scripts\Identity Authentication\IdentityAuth.psm1'

$header = Get-IdentityHeader `
    -IdentityTenantURL $IdentityTenantURL `
    -IdentityUserName $IdentityUser

# Get list of safes
$SafeList = & 'C:\Scripts\epv-api-scripts\Safe Management\Safe-Management.ps1' `
    -PVWAURL $PVWAURL `
    -Report `
    -LogonToken $header

# Let user select safes
$SelectedSafes = $SafeList |
    Select safeName, description, managingCPM |
    Out-GridView `
        -Title "Select safes for bulk actions (Ctrl/Shift for multi-select)" `
        -PassThru

# Exit if nothing selected
if (-not $SelectedSafes) {
    Write-Warning "No safes selected. Exiting."
    return
}

# Select Action
Write-Host "Select the action you want to perform:`n" -ForegroundColor Cyan
Write-Host "1) Change Password"
Write-Host "2) Reconcile Password"
Write-Host "3) Verify Password`n"

do {
    $selection = Read-Host "Enter 1, 2, or 3"
} until ($selection -in @('1','2','3'))

switch ($selection) {
    '1' { $Action = 'Change' }
    '2' { $Action = 'Reconcile' }
    '3' { $Action = 'Verify' }
}

Write-Host "`nSelected action: $Action" -ForegroundColor Green

# Confirmation
Write-Host "`nThe following safes with accounts managed by a CPM will be set to '$action':`n" -ForegroundColor Yellow
$SelectedSafes | Format-Table safeName, managingCPM -AutoSize

$confirm = Read-Host "`nType YES to continue"
if ($confirm -ne "YES") {
    Write-Warning "Operation cancelled by user."
    return
}

# Update selected safes
foreach ($safe in $SelectedSafes) {
    Write-Host "Set safe to change '$($safe.safeName)'..." -ForegroundColor Cyan

    & 'C:\Scripts\epv-api-scripts\Get Accounts\Invoke-BulkAccountActions.ps1' `
        -PVWAURL $PVWAURL `
        -SafeName $safe.safeName `
        -Address $addressdomain `
        -AccountsAction $Action `
        -LogonToken $header
}

Write-Host "`nSafe accounts set to $Action." -ForegroundColor Green
