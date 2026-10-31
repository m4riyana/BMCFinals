# IBASHO Stationery: start and diagnose the existing backend (Windows PowerShell).
# Run from backend folder: powershell -ExecutionPolicy Bypass -File .\start-ibasho.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
Write-Host 'IBASHO backend startup checks' -ForegroundColor Cyan
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Write-Error 'Node.js is missing. Install Node.js LTS and reopen the terminal.'; exit 1 }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Write-Error 'npm is missing. Install Node.js LTS and reopen the terminal.'; exit 1 }
if (-not (Test-Path '.env')) {
    Copy-Item '.env.example' '.env'
    Write-Warning 'Created backend/.env from the example. Open it and fill in your existing Supabase credentials and Xendit TEST key. Never share this file.'
    exit 1
}
$required = @('SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_DB_URL')
$settings = @{}
foreach ($line in (Get-Content '.env')) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $value = $Matches[2].Trim().Trim('"').Trim("'")
        $settings[$Matches[1]] = $value
    }
}
$missing = @($required | Where-Object { -not $settings.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($settings[$_]) -or $settings[$_] -match '^(YOUR_|postgresql://USER:PASSWORD@)' })
if ($missing.Count -gt 0) {
    Write-Warning ('Missing or placeholder backend/.env values: ' + ($missing -join ', '))
    Write-Host 'Configure the existing Supabase project credentials in backend/.env. Supabase Auth login in Flutter alone is not enough for the shop API.'
    exit 1
}
if (-not $settings.ContainsKey('XENDIT_SECRET_KEY') -or [string]::IsNullOrWhiteSpace($settings['XENDIT_SECRET_KEY']) -or $settings['XENDIT_SECRET_KEY'] -match '^YOUR_') {
    Write-Warning 'XENDIT_SECRET_KEY not configured: catalog may work, but Xendit checkout will be unavailable.'
} elseif (-not $settings['XENDIT_SECRET_KEY'].StartsWith('xnd_development_')) {
    Write-Warning 'Xendit key is not a Test Mode development key. This project deliberately accepts Test Mode keys only.'
}
if (-not (Test-Path 'node_modules')) {
    Write-Host 'Installing backend npm dependencies...'
    npm ci
    if ($LASTEXITCODE -ne 0) { Write-Error 'npm ci failed. Review the npm error above.'; exit 1 }
}
$port = 3000
if ($settings.ContainsKey('PORT') -and $settings['PORT'] -match '^\d+$') { $port = [int]$settings['PORT'] }
Write-Host "Checking http://localhost:$port/ ..."
try {
    $response = Invoke-RestMethod -Uri "http://localhost:$port/" -TimeoutSec 3
    if ($response.message -like '*backend is running*') {
        Write-Host "Backend is already running at http://localhost:$port" -ForegroundColor Green
        Write-Host "Open http://localhost:$port/api/catalog to test catalog."
        exit 0
    }
    Write-Warning "Port $port is occupied by a different service. Check the configured port."
    exit 1
} catch {}
Write-Host 'Starting backend. Leave this PowerShell terminal open.' -ForegroundColor Cyan
Write-Host "After startup, visit http://localhost:$port/api/catalog. If startup fails, read the error printed below."
node server.js
if ($LASTEXITCODE -ne 0) { Write-Host 'Startup failed. Common causes: incorrect Supabase DB credentials, missing public.ibasho_documents table, or blocked database connection.' -ForegroundColor Yellow }
exit $LASTEXITCODE
