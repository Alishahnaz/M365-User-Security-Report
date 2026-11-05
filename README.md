# Microsoft 365 User Security Report (PowerShell)

An **offline, read-only security reporting project** that reviews a fictional Microsoft Entra-style user export and highlights accounts needing investigation.

## What it checks

- **MFA not configured** on an enabled account
- **90+ days inactive** based on the sample `LastSignInDate` field
- **Privileged account without MFA** (an additional, higher-priority finding)
- **Licence on a disabled account** (potential licence reclamation)
- **Missing sign-in date** on an enabled account (needs review, not automatically considered inactive)

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Optional: Visual Studio Code and the PowerShell extension
- No Microsoft 365 account, Entra tenant, administrator access, or external PowerShell modules required

## Run the project

1. Extract this project folder to your Desktop.
2. Open the folder in VS Code (File > Open Folder).
3. In VS Code select **Terminal > New Terminal**, then select a **PowerShell** terminal.
4. From the project root run:

   ```powershell
   .\scripts\Get-M365UserSecurityReport.ps1 -AsOfDate '2026-11-04'
   ```

5. Open these two files inside the `output` folder:
   - `M365-Security-Report_20261104.csv` — details, flags and recommended actions for all accounts
   - `M365-Security-Summary_20261104.html` — manager-friendly summary (open in a web browser)

The fixed date keeps the sample result predictable. Omit `-AsOfDate` to review against today's date. To choose an inactivity threshold, add `-StaleDays 120`.

If Windows blocks scripts, use this **for the current PowerShell terminal only** and then rerun the script:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Only use this after you have reviewed the local script and trust its source. Do not change your entire computer's security policy for this exercise.

## Sample test: confirm the result is correct

```powershell
.\tests\Test-M365UserSecurityReport.ps1
```

Expected with `-AsOfDate 2026-11-04`:

| Check | Expected |
|---|---:|
| Accounts reviewed | 15 |
| Accounts requiring review (unique) | 10 |
| Active accounts without MFA | 5 |
| Inactive for 90+ days | 4 |
| Active privileged accounts without MFA | 2 |
| Disabled accounts with assigned licences | 2 |
| Active accounts with no sign-in date | 1 |

**Boundary check:** Chloe Nguyen's sign-in date is exactly 90 days before 4 Nov 2026, so she is flagged; Ethan Wilson is at 89 days, so he is not flagged.

## CSV fields

`DisplayName,UserPrincipalName,Department,License,MFAStatus,LastSignInDate,AdminRole,AccountEnabled`

- `MFAStatus`: `Enabled` or `Disabled` (simplified simulated indicator)
- `AccountEnabled`: `True` or `False`
- `LastSignInDate`: `YYYY-MM-DD`, or blank for unavailable data
- `AdminRole`: a role name or `None`
- `License`: plan name or `None`

All accounts use the reserved demonstration domain `example.com`. You can add fictional rows in `data/Sample-EntraUsers.csv`, keeping the header names and formats unchanged.

## File structure

```text
M365-User-Security-Report/
  data/Sample-EntraUsers.csv
  scripts/Get-M365UserSecurityReport.ps1
  tests/Test-M365UserSecurityReport.ps1
  output/                  # generated files; ignored by Git
  .gitignore
  README.md
```

## How it works

1. Import and validate the CSV.
2. Calculate days since the recorded sign-in, relative to the review date.
3. Apply rules to **enabled** accounts for access-risk findings. Independently check **disabled** accounts for licence assignments.
4. Return one row per account with independent flags, an overall review priority and recommended actions.
5. Export a CSV and a formatted HTML summary. No account changes are made.

## Interpreting results and limitations

- This is an **Entra-inspired combined dataset**, not a claim that the standard Entra **Download users** feature exports every column in this sample. In real environments, MFA registration, role assignments, licences and sign-in information may come from separate Entra reports or Microsoft Graph queries.
- `MFAStatus` in this demo is an assumed value for practice, **not proof of Conditional Access or MFA enforcement**. Authentication-method registration and actual MFA requirements must be assessed separately.
- Real `lastSignInDateTime` can reflect sign-in *attempts*, including unsuccessful ones; a better production signal for actual usage is `lastSuccessfulSignInDateTime` where available. Blank data is treated as "review" rather than 90-day inactivity.
- The risk levels are **illustrative prioritisation** for a demonstration, not a formal risk rating or compliance decision.
- The script performs no tenant connection and makes no changes to user accounts or licences. Humans should verify findings before remediation.
- Never upload real employee account details or tenant exports to a public GitHub repository.

## Suggested screenshots for your portfolio

1. Script visible in VS Code.
2. Terminal output showing successful execution and file paths.
3. CSV filtered to show flagged accounts and suggested action.
4. HTML executive summary opened in a browser.
5. Test script showing `PASS` messages, including the 90-day boundary check.

## Future enhancements

Connect to approved Microsoft Graph endpoints using appropriate permissions; collect MFA registration, role assignments, licence usage and reliable sign-in data; implement input schema mapping, unit tests and a scheduled report. For a live tenant, scope permissions to least privilege and keep account data confidential.

## Official reference documentation

- [Download users from Microsoft Entra](https://learn.microsoft.com/en-us/entra/identity/users/users-bulk-download)
- [Microsoft Graph signInActivity](https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0)
- [Authentication methods activity](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-methods-activity)
- [PowerShell ConvertTo-Html](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-html)
