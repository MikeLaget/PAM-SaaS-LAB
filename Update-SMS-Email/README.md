# 📱 Identity-SMS-Update

A simple PowerShell script that updates the mobile (cell) number and email for lab users in CyberArk Identity. This allows SMS authentication to be redirected to your own phone or email for testing purposes.

## 🔧 What It Does

This script sets your provided mobile number / email for all lab users so that when you log in as one of them, SMS-based MFA will send a code to your number instead of a pre-configured one.

## ▶️ How to Use

1. Open PowerShell and run the script:

    ```powershell
    .\Update-SMS-Email.ps1
    ```

2. When prompted, enter your mobile number in **international format**, e.g.:

    ```
    +61411111111
    ```

3. Once complete, you can log into CyberArk Identity using any of the following lab accounts:

    - **mike**
    - **carlos**
    - **cindy**
    - **tom**
    - **john**
    - **pam**
    - **robert**
    - **paul**

    The SMS authentication code will now be sent to your number.

## 🧪 Example Use Case

This is useful for authenticating to CyberArk Identity with different personas using SMS multi-factor authentication (MFA) in the CyberArk SkyTap environment.

## ⚠️ Notes

- This script is intended for **CyberArk lab environments only**.

## 🛠️ Requirements

- PowerShell 5.1 or later
- ActiveDirectory PowerShell Module