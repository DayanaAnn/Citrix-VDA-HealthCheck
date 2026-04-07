<#
.SYNOPSIS
    Citrix Session Report

.DESCRIPTION
    Generates a report of all active and disconnected sessions across Citrix
    Delivery Groups. Exports to CSV and optionally sends an email summary.
    Useful for capacity planning and session auditing.

.AUTHOR
    Dayana Ann V M

.VERSION
    1.0

.NOTES
    Requirements:
    - Citrix PowerShell SDK (Citrix.Broker.Admin.V2)
    - SMTP server access for email summary
    - Citrix Delivery Controller admin permissions
#>

# -----------------------------------------------
# CONFIGURATION
# -----------------------------------------------
$DeliveryController = "your-delivery-controller.domain.com"
$LogDirectory       = "C:\Logs\CitrixSessions"
$SMTPServer         = "smtp.yourdomain.com"
$SMTPPort           = 25
$ReportFrom         = "citrix-reports@yourdomain.com"
$ReportTo           = "infra-team@yourdomain.com"
$ReportSubject      = "Citrix Session Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

# -----------------------------------------------
# INITIALISE
# -----------------------------------------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile   = "$LogDirectory\CitrixSessions_$Timestamp.csv"
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
# RETRIEVE SESSIONS
# -----------------------------------------------
Write-Host "[INFO] Retrieving sessions from $DeliveryController..." -ForegroundColor Cyan

try {
    $Sessions = Get-BrokerSession -AdminAddress $DeliveryController -MaxRecordCount 10000
    Write-Host "[INFO] Total sessions found: $($Sessions.Count)"
} catch {
    Write-Error "[ERROR] Failed to retrieve sessions: $_"
    exit 1
}

# -----------------------------------------------
# BUILD REPORT
# -----------------------------------------------
foreach ($Session in $Sessions) {
    $Results += [PSCustomObject]@{
        UserName         = $Session.UserName
        MachineName      = $Session.MachineName
        DesktopGroup     = $Session.DesktopGroupName
        SessionState     = $Session.SessionState        # Active / Disconnected
        Protocol         = $Session.Protocol            # HDX / RDP / Console
        ClientName       = $Session.ClientName
        ClientAddress    = $Session.ClientAddress
        SessionStart     = $Session.EstablishmentTime
        IdleTime         = $Session.SessionStateChangeTime
        ApplicationsInUse = ($Session.ApplicationsInUse -join ", ")
        ReportedAt       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# -----------------------------------------------
# SUMMARY COUNTS
# -----------------------------------------------
$ActiveCount       = ($Results | Where-Object { $_.SessionState -eq "Active" }).Count
$DisconnectedCount = ($Results | Where-Object { $_.SessionState -eq "Disconnected" }).Count
$TotalCount        = $Results.Count

Write-Host ""
Write-Host "===== SESSION SUMMARY =====" -ForegroundColor Cyan
Write-Host "Total Sessions      : $TotalCount"
Write-Host "Active              : $ActiveCount" -ForegroundColor Green
Write-Host "Disconnected        : $DisconnectedCount" -ForegroundColor Yellow
Write-Host "===========================" -ForegroundColor Cyan

# -----------------------------------------------
# EXPORT CSV
# -----------------------------------------------
$Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8
Write-Host "[INFO] Report exported: $LogFile"

# -----------------------------------------------
# EMAIL SUMMARY
# -----------------------------------------------
$Body = @"
Citrix Session Report
======================
Date/Time    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Total        : $TotalCount
Active       : $ActiveCount
Disconnected : $DisconnectedCount

Full report attached.
"@

try {
    Send-MailMessage `
        -From $ReportFrom `
        -To $ReportTo `
        -Subject $ReportSubject `
        -Body $Body `
        -SmtpServer $SMTPServer `
        -Port $SMTPPort `
        -Attachments $LogFile

    Write-Host "[INFO] Report sent to $ReportTo" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to send email: $_"
}
