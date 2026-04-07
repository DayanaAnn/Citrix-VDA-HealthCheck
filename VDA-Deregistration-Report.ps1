<#
.SYNOPSIS
    Citrix VDA Deregistration Report

.DESCRIPTION
    Pulls all unregistered VDAs across all Delivery Groups in a Citrix CVAD
    environment. Exports a timestamped CSV report and sends an email alert
    to the infrastructure team.

.AUTHOR
    Dayana Ann V M

.VERSION
    1.0

.NOTES
    Requirements:
    - Citrix PowerShell SDK (Citrix.Broker.Admin.V2)
    - SMTP server access for email alerts
    - Citrix Delivery Controller admin permissions
#>

# -----------------------------------------------
# CONFIGURATION
# -----------------------------------------------
$DeliveryController = "your-delivery-controller.domain.com"
$LogDirectory       = "C:\Logs\VDADeregistration"
$SMTPServer         = "smtp.yourdomain.com"
$SMTPPort           = 25
$AlertFrom          = "vda-monitor@yourdomain.com"
$AlertTo            = "infra-team@yourdomain.com"
$AlertSubject       = "Citrix VDA Deregistration Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

# -----------------------------------------------
# INITIALISE
# -----------------------------------------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile   = "$LogDirectory\VDADeregistration_$Timestamp.csv"
$Results   = @()

if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory | Out-Null
}

# -----------------------------------------------
# LOAD CITRIX SNAP-IN
# -----------------------------------------------
try {
    Add-PSSnapin Citrix.Broker.Admin.V2 -ErrorAction Stop
} catch {
    Write-Error "[ERROR] Failed to load Citrix SDK: $_"
    exit 1
}

# -----------------------------------------------
# RETRIEVE UNREGISTERED VDAs
# -----------------------------------------------
Write-Host "[INFO] Querying unregistered VDAs from $DeliveryController..." -ForegroundColor Cyan

try {
    $UnregisteredVDAs = Get-BrokerMachine -AdminAddress $DeliveryController `
        -RegistrationState "Unregistered" -MaxRecordCount 5000
    Write-Host "[INFO] Found $($UnregisteredVDAs.Count) unregistered VDA(s)." -ForegroundColor Yellow
} catch {
    Write-Error "[ERROR] Failed to retrieve VDAs: $_"
    exit 1
}

# -----------------------------------------------
# BUILD REPORT
# -----------------------------------------------
foreach ($VDA in $UnregisteredVDAs) {
    $Results += [PSCustomObject]@{
        MachineName        = $VDA.MachineName
        CatalogName        = $VDA.CatalogName
        DesktopGroup       = $VDA.DesktopGroupName
        RegistrationState  = $VDA.RegistrationState
        PowerState         = $VDA.PowerState
        InMaintenanceMode  = $VDA.InMaintenanceMode
        SessionCount       = $VDA.SessionCount
        LastDeregistered   = $VDA.LastDeregistrationTime
        DeregistrationReason = $VDA.LastDeregistrationReason
        ReportedAt         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    Write-Host "[UNREGISTERED] $($VDA.MachineName) | Power: $($VDA.PowerState) | Reason: $($VDA.LastDeregistrationReason)" -ForegroundColor Red
}

# -----------------------------------------------
# EXPORT CSV
# -----------------------------------------------
if ($Results.Count -gt 0) {
    $Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8
    Write-Host "[INFO] Report exported: $LogFile"

    # -----------------------------------------------
    # EMAIL ALERT
    # -----------------------------------------------
    $Body = @"
Citrix VDA Deregistration Report
==================================
Date/Time          : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Unregistered VDAs  : $($Results.Count)

Please review the attached CSV for full details.
"@

    try {
        Send-MailMessage `
            -From $AlertFrom `
            -To $AlertTo `
            -Subject $AlertSubject `
            -Body $Body `
            -SmtpServer $SMTPServer `
            -Port $SMTPPort `
            -Attachments $LogFile

        Write-Host "[INFO] Alert sent to $AlertTo" -ForegroundColor Yellow
    } catch {
        Write-Error "[ERROR] Failed to send email: $_"
    }
} else {
    Write-Host "[INFO] No unregistered VDAs found. Environment is healthy." -ForegroundColor Green
}
