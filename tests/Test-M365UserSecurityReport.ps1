# Run from the project root:
#   .\tests\Test-M365UserSecurityReport.ps1
# Uses a fixed review date so the sample results are reproducible.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptFile = Join-Path $root 'scripts\Get-M365UserSecurityReport.ps1'
$csvFile = Join-Path $root 'data\Sample-EntraUsers.csv'
$testOutput = Join-Path $root 'output\test'
& $scriptFile -InputPath $csvFile -OutputDir $testOutput -AsOfDate '2026-11-04'
$reportFile = Join-Path $testOutput 'M365-Security-Report_20261104.csv'
$htmlFile = Join-Path $testOutput 'M365-Security-Summary_20261104.html'
$rows = @(Import-Csv -LiteralPath $reportFile)

function Assert-Count([string]$description, [int]$expected, [int]$actual) {
    if ($actual -ne $expected) {
        throw "FAIL: $description - expected $expected, got $actual"
    }
    Write-Host "PASS: $description ($actual)"
}

Assert-Count 'Total accounts' 15 $rows.Count
Assert-Count 'Accounts requiring review' 10 @($rows | Where-Object { $_.RiskLevel -ne 'None' }).Count
Assert-Count 'No MFA' 5 @($rows | Where-Object { $_.NoMFA -eq 'True' }).Count
Assert-Count 'Inactive 90+ days' 4 @($rows | Where-Object { $_.Inactive -eq 'True' }).Count
Assert-Count 'Admin without MFA' 2 @($rows | Where-Object { $_.AdminWithoutMFA -eq 'True' }).Count
Assert-Count 'Disabled with licence' 2 @($rows | Where-Object { $_.DisabledWithLicense -eq 'True' }).Count
Assert-Count 'Missing sign-in data' 1 @($rows | Where-Object { $_.MissingSignInData -eq 'True' }).Count

$chloe = $rows | Where-Object UserPrincipalName -eq 'chloe.nguyen@example.com'
$ethan = $rows | Where-Object UserPrincipalName -eq 'ethan.wilson@example.com'
if ($chloe.Inactive -ne 'True' -or $ethan.Inactive -ne 'False') {
    throw 'FAIL: 90-day boundary test (Chloe: 90 days, Ethan: 89 days)'
}
Write-Host 'PASS: 90-day boundary (90 flagged, 89 not flagged)'
if (-not (Test-Path -LiteralPath $htmlFile -PathType Leaf)) {
    throw 'FAIL: HTML summary was not created'
}
Write-Host 'PASS: HTML summary created'
Write-Host 'All sample tests passed.'
