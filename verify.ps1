<#
.SYNOPSIS
    ReadAlert Delivery 1 – NoRLS database verification script.
.DESCRIPTION
    Runs the two verification SQL scripts to confirm tables and stored procedures
    deployed correctly. Must be run after install.ps1 succeeds.
    Follows Developer Instructions §10: any SQL failure is a failed release test.
.EXAMPLE
    # Windows Integrated Security
    pwsh .\scripts\verify.ps1 -IntegratedSecurity

    # SQL Login (Docker / Mac)
    pwsh .\scripts\verify.ps1 -Server localhost,1433 -SqlLogin sa -SqlPassword (Read-Host -AsSecureString)
#>
[CmdletBinding()]
param(
    [ValidateSet('NoRLS')]
    [string]$Target = 'NoRLS',

    [string]$Server   = 'localhost,1433',
    [string]$Database = 'Cobbled_NoRLS',

    [string]$SqlLogin,
    [securestring]$SqlPassword,
    [switch]$IntegratedSecurity
)

$ErrorActionPreference = 'Stop'

# Path: scripts/ -> .. -> project root -> database/no-rls/
$dbDir = Join-Path $PSScriptRoot '..\database\no-rls'

if (-not (Test-Path $dbDir)) {
    throw "Database directory not found: $dbDir. Ensure you are running from the scripts/ folder."
}

$scripts = @(
    '01a_ReadAlert_Delivery1_NoRLS_Verification_v2.0.sql',
    '02a_ReadAlert_Delivery1_SP_API_Verification_v2.0.sql'
)

function Invoke-SqlScript([string]$scriptPath) {
    Write-Host "  Verifying: $(Split-Path $scriptPath -Leaf)"

    if ($IntegratedSecurity) {
        & sqlcmd -S $Server -d $Database -E -b -i $scriptPath
    }
    else {
        if (-not $SqlLogin -or -not $SqlPassword) {
            throw 'Supply -IntegratedSecurity or both -SqlLogin and -SqlPassword.'
        }
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlPassword)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            & sqlcmd -S $Server -d $Database -U $SqlLogin -P $plain -b -i $scriptPath
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Verification failed with exit code $LASTEXITCODE : $scriptPath"
    }
}

Write-Host ''
Write-Host '=========================================='
Write-Host '  ReadAlert Delivery 1 - NoRLS Verify'
Write-Host '=========================================='
Write-Host "  Target  : $Target"
Write-Host "  Server  : $Server"
Write-Host "  Database: $Database"
Write-Host ''

foreach ($s in $scripts) {
    $fullPath = Join-Path $dbDir $s
    if (-not (Test-Path $fullPath)) {
        throw "Required verification script not found: $fullPath"
    }
    Invoke-SqlScript $fullPath
}

Write-Host ''
Write-Host 'Verification complete. All tables and stored procedures confirmed.'
Write-Host ''
