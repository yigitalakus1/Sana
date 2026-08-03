[CmdletBinding()]
param(
    [string]$Model = "llama3.2:3b",
    [int]$BackendPort = 8000,
    [int]$WebPort = 57009,
    [switch]$RebuildWeb,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"

$root = $PSScriptRoot
$backendDir = Join-Path $root "sana-rag-backend"
$flutterDir = Join-Path $root "sana-app"
$python = Join-Path $backendDir ".venv\Scripts\python.exe"
$stateDir = Join-Path $root ".sana-local"
$backendUrl = "http://127.0.0.1:$BackendPort"
$webUrl = "http://127.0.0.1:$WebPort"

# Disk taşımasından sonra eski OLLAMA_MODELS yolu kalmış olabilir. Projenin
# yanındaki taşınmış model deposunu yalnız mevcut ayar geçersizse kullan.
$siblingOllamaModels = Join-Path (Split-Path $root -Parent) "OllamaModels"
if ((-not $env:OLLAMA_MODELS -or -not (Test-Path $env:OLLAMA_MODELS)) -and
    (Test-Path $siblingOllamaModels)) {
    $env:OLLAMA_MODELS = $siblingOllamaModels
}

function Test-Endpoint {
    param([string]$Url, [int]$TimeoutSeconds = 2)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSeconds | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Wait-ForEndpoint {
    param([string]$Url, [string]$Name, [int]$Attempts = 30)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        if (Test-Endpoint -Url $Url) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "$Name zamanında başlatılamadı. Günlükleri $stateDir klasöründe kontrol edin."
}

function Save-ProcessState {
    param([string]$Name, [System.Diagnostics.Process]$Process, [string]$ExpectedName)
    @{
        process_id = $Process.Id
        process_name = $ExpectedName
        started_at = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $stateDir "$Name.json")
}

if (-not (Test-Path $python)) {
    throw "Backend Python ortamı bulunamadı: $python"
}
if (-not (Test-Path $flutterDir)) {
    throw "Flutter projesi bulunamadı: $flutterDir"
}

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$ollamaCommand = Get-Command ollama.exe -ErrorAction SilentlyContinue
$ollama = if ($ollamaCommand) {
    $ollamaCommand.Source
} else {
    Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
}
if (-not (Test-Path $ollama)) {
    throw "Ollama bulunamadı. Ollama kurulumunu kontrol edin."
}

Write-Host "[1/5] Ollama kontrol ediliyor..." -ForegroundColor Cyan
Write-Host "      Model deposu: $env:OLLAMA_MODELS" -ForegroundColor DarkGray
if (-not (Test-Endpoint -Url "http://127.0.0.1:11434/api/tags")) {
    $ollamaProcess = Start-Process -FilePath $ollama `
        -ArgumentList @("serve") `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $stateDir "ollama.out.log") `
        -RedirectStandardError (Join-Path $stateDir "ollama.err.log") `
        -PassThru
    Save-ProcessState -Name "ollama" -Process $ollamaProcess -ExpectedName "ollama"
    Wait-ForEndpoint -Url "http://127.0.0.1:11434/api/tags" -Name "Ollama"
}

$tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 5
$modelNames = @($tags.models | ForEach-Object { $_.name })
if ($modelNames -notcontains $Model) {
    throw "'$Model' modeli kurulu değil. Önce şu komutu çalıştırın: ollama pull $Model"
}
Write-Host "      Model hazır: $Model" -ForegroundColor Green

Write-Host "[2/5] Yerel RAG veritabanı güncelleniyor..." -ForegroundColor Cyan
Push-Location $backendDir
try {
    & $python -m tools.ingest_docs --docs-dir data/medical_docs --db-path data/sana_rag.db
    if ($LASTEXITCODE -ne 0) { throw "RAG ingestion başarısız oldu." }
}
finally {
    Pop-Location
}

Write-Host "[3/5] Backend kontrol ediliyor..." -ForegroundColor Cyan
if (-not (Test-Endpoint -Url "$backendUrl/health")) {
    $env:SANA_RAG_MODE = "local"
    $env:SANA_RAG_DB_PATH = "data\sana_rag.db"
    $env:SANA_PROVIDER = "ollama"
    $env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
    $env:OLLAMA_MODEL = $Model
    $env:OLLAMA_TIMEOUT_SECONDS = "120"
    $env:SANA_ENABLE_EXTERNAL_AI = "false"

    $backendProcess = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$BackendPort") `
        -WorkingDirectory $backendDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $stateDir "backend.out.log") `
        -RedirectStandardError (Join-Path $stateDir "backend.err.log") `
        -PassThru
    Save-ProcessState -Name "backend" -Process $backendProcess -ExpectedName "python"
    Wait-ForEndpoint -Url "$backendUrl/health" -Name "Backend"
} else {
    Write-Host "      8000 portundaki çalışan backend kullanılacak." -ForegroundColor DarkYellow
}
Write-Host "      Backend hazır: $backendUrl" -ForegroundColor Green

Write-Host "[4/5] Flutter web sürümü kontrol ediliyor..." -ForegroundColor Cyan
$buildIndex = Join-Path $flutterDir "build\web\index.html"
$needsBuild = $RebuildWeb -or -not (Test-Path $buildIndex)
if (-not $needsBuild) {
    $latestSource = Get-ChildItem (Join-Path $flutterDir "lib") -Recurse -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    $needsBuild = $latestSource.LastWriteTimeUtc -gt (Get-Item $buildIndex).LastWriteTimeUtc
}

if ($needsBuild) {
    $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
    $flutter = if ($flutterCommand) {
        $flutterCommand.Source
    } else {
        "C:\Users\Asus\flutter\bin\flutter.bat"
    }
    if (-not (Test-Path $flutter)) { throw "Flutter komutu bulunamadı." }

    $flutterRoot = Split-Path (Split-Path $flutter -Parent) -Parent
    $flutterDart = Join-Path $flutterRoot "bin\cache\dart-sdk\bin\dart.exe"
    $flutterSnapshot = Join-Path $flutterRoot "bin\cache\flutter_tools.snapshot"
    $flutterPackages = Join-Path $flutterRoot "packages\flutter_tools\.dart_tool\package_config.json"
    foreach ($requiredPath in @($flutterDart, $flutterSnapshot, $flutterPackages)) {
        if (-not (Test-Path $requiredPath)) {
            throw "Flutter çalışma bileşeni bulunamadı: $requiredPath"
        }
    }

    Push-Location $flutterDir
    try {
        $flutterBuildOut = Join-Path $stateDir "flutter-build.out.log"
        $flutterBuildErr = Join-Path $stateDir "flutter-build.err.log"
        $buildProcess = Start-Process -FilePath $flutterDart `
            -ArgumentList @(
                "--packages=$flutterPackages",
                $flutterSnapshot,
                "build",
                "web",
                "--release",
                "--no-pub",
                "--dart-define=SANA_API_BASE_URL=$backendUrl"
            ) `
            -WindowStyle Hidden `
            -RedirectStandardOutput $flutterBuildOut `
            -RedirectStandardError $flutterBuildErr `
            -Wait `
            -PassThru
        if ($buildProcess.ExitCode -ne 0) {
            $buildError = Get-Content -Raw $flutterBuildErr -ErrorAction SilentlyContinue
            throw "Flutter web build başarısız oldu (çıkış kodu: $($buildProcess.ExitCode)). $buildError"
        }
        Write-Host "      Flutter web derlemesi tamamlandı." -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

Write-Host "[5/5] Web sunucusu kontrol ediliyor..." -ForegroundColor Cyan
if (-not (Test-Endpoint -Url $webUrl)) {
    $webRoot = Join-Path $flutterDir "build\web"
    $webProcess = Start-Process -FilePath $python `
        -ArgumentList @("-m", "http.server", "$WebPort", "--bind", "127.0.0.1") `
        -WorkingDirectory $webRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $stateDir "web.out.log") `
        -RedirectStandardError (Join-Path $stateDir "web.err.log") `
        -PassThru
    Save-ProcessState -Name "web" -Process $webProcess -ExpectedName "python"
    Wait-ForEndpoint -Url $webUrl -Name "Web sunucusu"
}

Write-Host ""
Write-Host "Sana hazır: $webUrl" -ForegroundColor Green
Write-Host "Durum: .\status_local.cmd"
Write-Host "Durdur: .\stop_local.cmd"
Write-Host "Değerlendir: .\evaluate_local.cmd"

if (-not $NoBrowser) {
    Start-Process $webUrl
}
