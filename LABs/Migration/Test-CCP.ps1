# Variable Definitions
$restresponse = $null
$object = "svc.cm.sa.ccp"
$CCPAddress = "https://ccp.acme.corp"
$AppID = "App-CyberArk-Certificate-Manager"
$URI = "$CCPAddress/AIMWebService/api/Accounts?AppID=$AppID&Object=$object"

# Creation of REST Web Request
$restresponse = Invoke-RestMethod -Uri $URI -Method GET

# REST Output
$restresponse
