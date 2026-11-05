<#
.SYNOPSIS
    Creates an offline M365-style security review from a fictional user CSV.
.DESCRIPTION
    Checks enabled users for missing MFA, inactive accounts, and privileged
    accounts without MFA. Checks disabled users for assigned licences. A blank
    sign-in date on an enabled account is reported as "Needs review" instead
    of assuming 90+ days of inactivity.

    MFAStatus is a simplified sample-data indicator; it is NOT proof that
    MFA is enforced in a real Microsoft Entra tenant.
.EXAMPLE
    .\scripts\Get-M365UserSecurityReport.ps1 -AsOfDate '2026-11-04'
#>
[CmdletBinding()]
param(
    [string]$InputPath = (Join-Path $PSScriptRoot '..\data\Sample-EntraUsers.csv'),
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\output'),
    [ValidateRange(1, 3650)]
    [int]$StaleDays = 90,
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$AsOfDate = (Get-Date -Format 'yyyy-MM-dd')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# STEP 1: Read and validate the input.
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input CSV not found: $InputPath"
}

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$asOf = [datetime]::ParseExact($AsOfDate, 'yyyy-MM-dd', $culture)
$users = @(Import-Csv -LiteralPath $InputPath -Encoding UTF8)
if ($users.Count -eq 0) {
    throw 'The input CSV has no user records.'
}

$requiredColumns = @(
    'DisplayName', 'UserPrincipalName', 'Department', 'License',
    'MFAStatus', 'LastSignInDate', 'AdminRole', 'AccountEnabled'
)
$actualColumns = @($users[0].PSObject.Properties.Name)
foreach ($column in $requiredColumns) {
    if ($actualColumns -notcontains $column) {
        throw "Missing required CSV column: $column"
    }
}

# STEP 2: Check every account, one row at a time.
$report = @(foreach ($user in $users) {
    $upn = "$($user.UserPrincipalName)".Trim()
    $mfaStatus = "$($user.MFAStatus)".Trim()
    $accountStatus = "$($user.AccountEnabled)".Trim()
    $licence = "$($user.License)".Trim()
    $adminRole = "$($user.AdminRole)".Trim()
    $dateText = "$($user.LastSignInDate)".Trim()

    if ([string]::IsNullOrWhiteSpace($upn)) {
        throw "A user record has no UserPrincipalName: $($user.DisplayName)"
    }
    if ($mfaStatus -notin @('Enabled', 'Disabled')) {
        throw "Invalid MFAStatus for ${upn}: '$mfaStatus' (use Enabled or Disabled)"
    }
    if ($accountStatus -notin @('True', 'False')) {
        throw "Invalid AccountEnabled for ${upn}: '$accountStatus' (use True or False)"
    }

    $isEnabled = ($accountStatus -eq 'True')
    $hasLicence = (-not [string]::IsNullOrWhiteSpace($licence)) -and ($licence -ne 'None')
    $isAdmin = (-not [string]::IsNullOrWhiteSpace($adminRole)) -and ($adminRole -ne 'None')

    $daysSinceSignIn = $null
    if (-not [string]::IsNullOrWhiteSpace($dateText)) {
        try {
            $lastSignIn = [datetime]::ParseExact($dateText, 'yyyy-MM-dd', $culture)
        }
        catch {
            throw "Invalid LastSignInDate for ${upn}: '$dateText' (use YYYY-MM-DD)"
        }
        if ($lastSignIn -gt $asOf) {
            throw "LastSignInDate for $upn is after the review date ($AsOfDate)."
        }
        $daysSinceSignIn = [int]($asOf - $lastSignIn).TotalDays
    }

    # Focus access-risk checks on accounts that can still sign in.
    $noMfa = $isEnabled -and ($mfaStatus -eq 'Disabled')
    $inactive = $isEnabled -and ($null -ne $daysSinceSignIn) -and ($daysSinceSignIn -ge $StaleDays)
    $adminWithoutMfa = $isAdmin -and $noMfa
    $disabledWithLicence = (-not $isEnabled) -and $hasLicence
    $missingSignInData = $isEnabled -and [string]::IsNullOrWhiteSpace($dateText)

    $findings = [System.Collections.Generic.List[string]]::new()
    $actions = [System.Collections.Generic.List[string]]::new()

    if ($noMfa) {
        $findings.Add('MFA not configured')
        $actions.Add('Review MFA registration and Conditional Access requirements')
    }
    if ($inactive) {
        $findings.Add("No recorded sign-in for $StaleDays+ days")
        $actions.Add('Confirm owner and business need before considering disablement')
    }
    if ($adminWithoutMfa) {
        $findings.Add('Privileged account without MFA')
        $actions.Add('Urgently review privileged access and MFA protections')
    }
    if ($disabledWithLicence) {
        $findings.Add('Disabled account has a licence')
        $actions.Add('Check licence assignment and reclaim if appropriate')
    }
    if ($missingSignInData) {
        $findings.Add('No sign-in date available')
        $actions.Add('Check sign-in history before making an inactivity decision')
    }

    $riskLevel = if ($adminWithoutMfa) { 'Critical' }
                 elseif ($noMfa -or $inactive) { 'High' }
                 elseif ($disabledWithLicence) { 'Medium' }
                 elseif ($missingSignInData) { 'Review' }
                 else { 'None' }

    [pscustomobject]@{
        ReviewDate          = $asOf.ToString('yyyy-MM-dd')
        DisplayName         = "$($user.DisplayName)".Trim()
        UserPrincipalName   = $upn
        Department          = "$($user.Department)".Trim()
        AccountEnabled      = $isEnabled
        License             = $licence
        MFAStatus           = $mfaStatus
        AdminRole           = $adminRole
        LastSignInDate      = $dateText
        DaysSinceSignIn     = $daysSinceSignIn
        NoMFA               = $noMfa
        Inactive            = $inactive
        AdminWithoutMFA     = $adminWithoutMfa
        DisabledWithLicense = $disabledWithLicence
        MissingSignInData   = $missingSignInData
        RiskLevel           = $riskLevel
        Findings            = ($findings -join '; ')
        RecommendedAction   = ($actions -join '; ')
    }
})

# STEP 3: Export a detailed CSV and an easy-to-read HTML summary.
if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$stamp = $asOf.ToString('yyyyMMdd')
$csvPath = Join-Path $OutputDir "M365-Security-Report_$stamp.csv"
$htmlPath = Join-Path $OutputDir "M365-Security-Summary_$stamp.html"

$report | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$flagged = @($report | Where-Object { $_.RiskLevel -ne 'None' })

$metrics = @(
    [pscustomobject]@{ Metric = 'Accounts reviewed'; Count = $report.Count }
    [pscustomobject]@{ Metric = 'Accounts requiring review'; Count = $flagged.Count }
    [pscustomobject]@{ Metric = 'Active accounts without MFA'; Count = @($report | Where-Object NoMFA).Count }
    [pscustomobject]@{ Metric = "Active accounts inactive $StaleDays+ days"; Count = @($report | Where-Object Inactive).Count }
    [pscustomobject]@{ Metric = 'Active admins without MFA'; Count = @($report | Where-Object AdminWithoutMFA).Count }
    [pscustomobject]@{ Metric = 'Disabled accounts with licences'; Count = @($report | Where-Object DisabledWithLicense).Count }
    [pscustomobject]@{ Metric = 'Active accounts missing sign-in data'; Count = @($report | Where-Object MissingSignInData).Count }
)

$metricsHtml = $metrics | ConvertTo-Html -Fragment
if ($flagged.Count -gt 0) {
    $findingsHtml = $flagged |
        Select-Object DisplayName, UserPrincipalName, RiskLevel, Findings, RecommendedAction |
        ConvertTo-Html -Fragment
}
else {
    $findingsHtml = '<p>No review findings in the provided sample data.</p>'
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>M365 User Security Review - $($asOf.ToString('yyyy-MM-dd'))</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; max-width: 1120px; margin: 38px auto; padding: 0 18px; color: #1f2937; line-height: 1.5; }
h1 { color: #16325c; margin-bottom: 0; }
h2 { color: #16325c; margin-top: 32px; }
.subtitle { color: #526174; margin-top: 4px; }
.notice { background: #f0f5fc; border-left: 4px solid #3565ab; padding: 12px 16px; }
table { border-collapse: collapse; width: 100%; margin-top: 14px; font-size: 14px; }
th, td { border: 1px solid #d7dee7; text-align: left; padding: 10px; vertical-align: top; }
th { background: #173a66; color: white; }
tr:nth-child(even) { background: #f7f9fc; }
.small { font-size: 13px; color: #526174; }
@media print { body { margin: 12px; } }
</style>
</head>
<body>
<h1>Microsoft 365 User Security Review</h1>
<p class="subtitle">Review date: $($asOf.ToString('yyyy-MM-dd')) &nbsp; | &nbsp; Inactivity threshold: $StaleDays days</p>
<p class="notice"><strong>Portfolio demonstration:</strong> fictional data, analysed offline. MFAStatus is a simplified sample field, not an assertion about real MFA policy enforcement. Findings require human investigation.</p>
<h2>Executive summary</h2>
$metricsHtml
<h2>Accounts requiring review</h2>
$findingsHtml
<p class="small">An account can trigger more than one check. Category counts overlap; do not add them to calculate the number of unique accounts requiring review. Blank sign-in dates are reviewed separately and are not counted as 90+ days inactive.</p>
</body>
</html>
"@
$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8

Write-Host "Completed review of $($report.Count) accounts; $($flagged.Count) require review."
Write-Host "CSV report: $csvPath"
Write-Host "HTML summary: $htmlPath"
