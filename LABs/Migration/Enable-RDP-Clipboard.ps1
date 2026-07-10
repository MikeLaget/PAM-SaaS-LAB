# Enable clipboard redirection for RDP

$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$RegName = "fDisableCdm"
$RegValue = 0

# Ensure registry path exists
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Set registry value
Set-ItemProperty -Path $RegPath -Name $RegName -Type DWord -Value $RegValue

Write-Host "RDP clipboard redirection has been ENABLED."

# Restart Remote Desktop Services to apply change
Restart-Service -Name TermService -Force

Write-Host "Remote Desktop Services restarted. Copy/paste via RDP should now work."