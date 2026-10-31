param(
    [Parameter(Mandatory = $true)]
    [string]$BackendUrl,
    [string]$FlutterPath = 'flutter'
)

$ErrorActionPreference = 'Stop'
$backendUri = $null
if (-not [Uri]::TryCreate($BackendUrl, [UriKind]::Absolute, [ref]$backendUri) -or
    $backendUri.Scheme -ne 'https' -or $backendUri.IsLoopback -or
    $backendUri.UserInfo -or $backendUri.Query -or $backendUri.Fragment) {
    throw 'Provide the public HTTPS backend origin, for example https://your-backend.example.com.'
}
$BackendUrl = $BackendUrl.TrimEnd('/')
Write-Host 'Checking the public backend catalog...'
$response = Invoke-WebRequest -UseBasicParsing -Uri "$BackendUrl/api/catalog" -TimeoutSec 60
$catalog = $response.Content | ConvertFrom-Json
if ($response.StatusCode -ne 200 -or -not ($catalog.PSObject.Properties.Name -contains 'products')) {
    throw 'The public URL did not return the expected catalog. Check the backend before building.'
}

if (-not $env:JAVA_HOME -and (Test-Path 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe')) {
    $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
}
Push-Location $PSScriptRoot
try {
    & $FlutterPath build apk --release "--dart-define=BACKEND_URL=$BackendUrl"
    if ($LASTEXITCODE -ne 0) { throw "Flutter build failed with exit code $LASTEXITCODE." }
    Write-Host "APK: $PSScriptRoot\build\app\outputs\flutter-apk\app-release.apk"
} finally {
    Pop-Location
}
