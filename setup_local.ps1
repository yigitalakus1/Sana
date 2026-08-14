[CmdletBinding()]
param(
    [string]$Model = "llama3.2:3b",
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"

$root = $PSScriptRoot
$backendDir = Join-Path $root "sana-rag-backend"
$flutterDir = Join-Path $root "sana-app"
$venvDir = Join-Path $backendDir ".venv"
$backendPython = Join-Path $venvDir "Scripts\python.exe"
$requirements = Join-Path $backendDir "requirements.txt"
$startScript = Join-Path $root "start_local.ps1"
$shortcutScript = Join-Path $root "create_shortcut.ps1"

function Write-Step {
    param([int]$Number, [int]$Total, [string]$Message)
    Write-Host "[$Number/$Total] $Message" -ForegroundColor Cyan
}

function Test-Endpoint {
    param([string]$Url, [int]$TimeoutSeconds = 3)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSeconds | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Find-Python {
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source -3.11 -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return @{ Executable = $py.Source; Prefix = @("-3.11") }
        }
    }

    foreach ($name in @("python.exe", "python")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $supported = & $command.Source -c "import sys; print('yes' if sys.version_info >= (3, 11) else 'no')" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$supported".Trim() -eq "yes") {
            return @{ Executable = $command.Source; Prefix = @() }
        }
    }

    return $null
}

foreach ($requiredPath in @($backendDir, $flutterDir, $requirements, $startScript, $shortcutScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Gerekli proje dosyası bulunamadı: $requiredPath"
    }
}

$setupMutex = New-Object System.Threading.Mutex($false, "Local\SanaLocalSetup")
if (-not $setupMutex.WaitOne(0)) {
    throw "Sana kurulumu zaten çalışıyor. Açık kurulum penceresinin tamamlanmasını bekleyin."
}

Write-Host ""
Write-Host "Sana yerel kurulum" -ForegroundColor Green
Write-Host "Proje: $root" -ForegroundColor DarkGray
Write-Host ""

Write-Step 1 7 "Python 3.11 veya üzeri kontrol ediliyor..."
$python = Find-Python
if (-not $python) {
    throw "Python 3.11+ bulunamadı. https://www.python.org/downloads/ adresinden kurup bu betiği yeniden çalıştırın. Kurulumda 'Add Python to PATH' seçeneğini işaretleyin."
}
$pythonExe = $python.Executable
$pythonPrefix = @($python.Prefix)
$pythonVersion = & $pythonExe @pythonPrefix -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"
Write-Host "      Python hazır: $pythonVersion" -ForegroundColor Green

Write-Step 2 7 "Backend sanal ortamı hazırlanıyor..."
if (-not (Test-Path -LiteralPath $backendPython)) {
    & $pythonExe @pythonPrefix -m venv $venvDir
    if ($LASTEXITCODE -ne 0) { throw "Python sanal ortamı oluşturulamadı." }
}
& $backendPython -m pip install --disable-pip-version-check -r $requirements
if ($LASTEXITCODE -ne 0) { throw "Backend paketleri kurulamadı. İnternet bağlantısını kontrol edin." }
Write-Host "      Backend paketleri hazır." -ForegroundColor Green

Write-Step 3 7 "Flutter kontrol ediliyor..."
$flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
$flutter = if ($flutterCommand) { $flutterCommand.Source } else { "C:\Users\$env:USERNAME\flutter\bin\flutter.bat" }
if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter bulunamadı. https://docs.flutter.dev/get-started/install/windows adresindeki Windows kurulumunu tamamlayıp bu betiği yeniden çalıştırın."
}
Push-Location $flutterDir
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter paketleri indirilemedi. İnternet bağlantısını kontrol edin." }
}
finally {
    Pop-Location
}
Write-Host "      Flutter paketleri hazır." -ForegroundColor Green

Write-Step 4 7 "Ollama kontrol ediliyor..."
$ollamaCommand = Get-Command ollama.exe -ErrorAction SilentlyContinue
$ollama = if ($ollamaCommand) { $ollamaCommand.Source } else { Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe" }
if (-not (Test-Path -LiteralPath $ollama)) {
    throw "Ollama bulunamadı. https://ollama.com/download/windows adresinden kurup bu betiği yeniden çalıştırın."
}

$siblingOllamaModels = Join-Path (Split-Path $root -Parent) "OllamaModels"
if ((-not $env:OLLAMA_MODELS -or -not (Test-Path -LiteralPath $env:OLLAMA_MODELS)) -and
    (Test-Path -LiteralPath $siblingOllamaModels)) {
    $env:OLLAMA_MODELS = $siblingOllamaModels
}

if (-not (Test-Endpoint "http://127.0.0.1:11434/api/tags")) {
    Start-Process -FilePath $ollama -ArgumentList @("serve") -WindowStyle Hidden | Out-Null
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        if (Test-Endpoint "http://127.0.0.1:11434/api/tags") { break }
        Start-Sleep -Milliseconds 500
    }
}
if (-not (Test-Endpoint "http://127.0.0.1:11434/api/tags")) {
    throw "Ollama servisi başlatılamadı. Ollama uygulamasını açıp kurulumu yeniden deneyin."
}
Write-Host "      Ollama hazır." -ForegroundColor Green

Write-Step 5 7 "Yerel dil modeli kontrol ediliyor..."
$tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 5
$modelNames = @($tags.models | ForEach-Object { $_.name })
if ($modelNames -notcontains $Model) {
    Write-Host "      $Model indiriliyor. Model boyutuna göre bu işlem sürebilir..." -ForegroundColor DarkYellow
    & $ollama pull $Model
    if ($LASTEXITCODE -ne 0) { throw "$Model modeli indirilemedi. İnternet bağlantısını kontrol edin." }
}
Write-Host "      Model hazır: $Model" -ForegroundColor Green

Write-Step 6 7 "Yerel tahlil veritabanı oluşturuluyor..."
Push-Location $backendDir
try {
    & $backendPython -m tools.ingest_docs --docs-dir data/medical_docs --db-path data/sana_rag.db
    if ($LASTEXITCODE -ne 0) { throw "Yerel RAG veritabanı oluşturulamadı." }
}
finally {
    Pop-Location
}
Write-Host "      Yerel veritabanı hazır." -ForegroundColor Green

Write-Step 7 7 "Masaüstü kısayolu oluşturuluyor..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $shortcutScript
if ($LASTEXITCODE -ne 0) { throw "Masaüstü kısayolu oluşturulamadı." }

Write-Host ""
Write-Host "Sana kurulumu tamamlandı." -ForegroundColor Green
Write-Host "Bundan sonra masaüstündeki Sana simgesini kullanabilirsiniz."
Write-Host ""

if (-not $NoStart) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startScript -Model $Model
    if ($LASTEXITCODE -ne 0) { throw "Kurulum tamamlandı ancak Sana başlatılamadı." }
}
