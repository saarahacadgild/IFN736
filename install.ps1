<#
.SYNOPSIS
    ReadAlert Delivery 1 – NoRLS database installation script.
.DESCRIPTION
    Runs the three database SQL scripts in the correct order against the target
    Cobbled_NoRLS database. Follows Developer Instructions §9: never defaults to
    production, fails closed, authentication mode is explicit.
.EXAMPLE
    # Windows Integrated Security (local SQL Server)
    pwsh .\scripts\install.ps1 -IntegratedSecurity

    # SQL Login (Docker / Mac / Azure SQL)
    pwsh .\scripts\install.ps1 -Server localhost,1433 -SqlLogin sa -SqlPassword (Read-Host -AsSecureString)
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

# Scripts run in this exact order — preflight first, then data, then SPs.
$scripts = @(
    '00_ReadAlert_Delivery1_TargetDatabase_Preflight_v2.0.sql',
    '01b_ReadAlert_Delivery1_TestData_v2.0.sql',
    '02_ReadAlert_Delivery1_StoredProcedures_API_v2.0.sql'
)

function Invoke-SqlScript([string]$scriptPath) {
    Write-Host "  Running: $(Split-Path $scriptPath -Leaf)"

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
        throw "Script failed with exit code $LASTEXITCODE : $scriptPath"
    }
}

Write-Host ''
Write-Host '=========================================='
Write-Host '  ReadAlert Delivery 1 - NoRLS Install'
Write-Host '=========================================='
Write-Host "  Target  : $Target"
Write-Host "  Server  : $Server"
Write-Host "  Database: $Database"
Write-Host ''

foreach ($s in $scripts) {
    $fullPath = Join-Path $dbDir $s
    if (-not (Test-Path $fullPath)) {
        throw "Required script not found: $fullPath"
    }
    Invoke-SqlScript $fullPath
}

Write-Host ''
Write-Host 'Installation complete.'
Write-Host 'Next step: run verify.ps1 to confirm all tables and stored procedures are present.'
Write-Host ''
