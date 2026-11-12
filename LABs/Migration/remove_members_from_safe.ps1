#This script is built to remove all acme_user_XXXX from the safe "T-ACME-WIN-DOM-TEST-02".
#v26-11.13

# Configuration
$PVWA_URL = "https://pvwa.acme.corp/PasswordVault"
$Username = "mike"
$SafeName = "T-ACME-WIN-DOM-TEST-02"

# 1. Prompt for password securely
$Credential = Get-Credential -UserName $Username -Message "Enter LDAP password for $Username"
$Password = $Credential.GetNetworkCredential().Password

# Define a splatting dictionary for Invoke-RestMethod
$RestParams = @{
    Method = "POST"
    ContentType = "application/json"
    Headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell" }
}

# Handle SSL/TLS errors depending on the PowerShell version
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $RestParams.Add("SkipCertificateCheck", $true)
} else {
    add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# 2. Authenticate via LDAP
Write-Host "[*] Authenticating to $PVWA_URL as $Username (LDAP)..." -ForegroundColor Cyan
$LogonUrl = "$PVWA_URL/API/auth/LDAP/Logon/"
$LogonBody = @{
    username = $Username
    password = $Password
    concurrentSession = $true
} | ConvertTo-Json

try {
    $RestParams.Uri = $LogonUrl
    $RestParams.Body = $LogonBody
    $LogonResponse = Invoke-RestMethod @RestParams
    $SessionToken = $LogonResponse

    if ($SessionToken -is [string]) {
        $SessionToken = $SessionToken.Trim('"')
    }

    # Update headers for subsequent requests
    $RestParams.Headers = @{
        "Authorization" = $SessionToken
        "Content-Type" = "application/json"
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell"
    }
    Write-Host "[+] Authentication successful." -ForegroundColor Green
}
catch {
    Write-Host "[-] Authentication failed: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.ErrorDetails) {
        Write-Host "    Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit
}

# 3. Verify the Safe exists (Get Safe Details)
Write-Host "[*] Verifying Safe: $SafeName..." -ForegroundColor Cyan
$SafeUrlId = [uri]::EscapeDataString($SafeName)
$GetSafeUrl = "$PVWA_URL/API/Safes/$SafeUrlId/"

try {
    $RestParams.Method = "GET"
    $RestParams.Uri = $GetSafeUrl
    $RestParams.Remove("Body") # Body is not used for GET

    $SafeResponse = Invoke-RestMethod @RestParams
    Write-Host "[+] Found Safe: $SafeName" -ForegroundColor Green
}
catch {
    Write-Host "[-] Safe '$SafeName' not found or you do not have permission to view it: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# 4. Remove users from the Safe
Write-Host "[*] Removing users acme_test_0001 to acme_test_0068..." -ForegroundColor Cyan
$RestParams.Method = "DELETE"

$SuccessCount = 0
$ErrorCount = 0

for ($i = 1; $i -le 68; $i++) {
    $MemberName = "acme_test_{0:D4}" -f $i

    # URL encode the member name to ensure special characters don't break the path
    $EncodedMemberName = [uri]::EscapeDataString($MemberName)
    $RemoveMemberUrl = "$PVWA_URL/API/Safes/$SafeUrlId/Members/$EncodedMemberName/"
    $RestParams.Uri = $RemoveMemberUrl

    try {
        $RemoveResponse = Invoke-RestMethod @RestParams
        Write-Host "  [+] Removed $MemberName successfully." -ForegroundColor Green
        $SuccessCount++
    }
    catch {
        $StatusCode = 0
        if ($_.Exception.Response) {
            # Handle PS5 vs PS7 status code differences
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $StatusCode = $_.Exception.Response.StatusCode.value__
            } else {
                $StatusCode = $_.Exception.Response.StatusCode
            }
        }

        # 404 indicates the user is already not a member of the Safe
        if ($StatusCode -eq 404) {
            Write-Host "  [-] $MemberName is not a member of the safe." -ForegroundColor Yellow
        }
        else {
            $ErrMsg = ""
            if ($_.ErrorDetails) {
                $ErrMsg = $_.ErrorDetails.Message
            } elseif ($PSVersionTable.PSVersion.Major -lt 6 -and $_.Exception.Response) {
                $StreamReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $ErrMsg = $StreamReader.ReadToEnd()
            } else {
                $ErrMsg = $_.Exception.Message
            }

            Write-Host "  [!] Failed to remove $MemberName : HTTP $StatusCode - $ErrMsg" -ForegroundColor Red
            $ErrorCount++
        }
    }
}

Write-Host "[*] Finished processing. Successfully removed: $SuccessCount, Errors/Not Found: $ErrorCount" -ForegroundColor Cyan
