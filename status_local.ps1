[CmdletBinding()]
param(
    [int]$BackendPort = 8000,
    [int]$WebPort = 57009,
    [string]$Model = "llama3.2:3b"
)

function Test-Endpoint {
    param([string]$Url)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Show-Status {
    param([string]$Name, [bool]$Ready, [string]$Address)
    $label = if ($Ready) { "HAZIR" } else { "KAPALI" }
    $color = if ($Ready) { "Green" } else { "Red" }
    Write-Host ("{0,-10} {1,-7} {2}" -f $Name, $label, $Address) -ForegroundColor $color
}

$ollamaUrl = "http://127.0.0.1:11434"
$backendUrl = "http://127.0.0.1:$BackendPort"
$webUrl = "http://127.0.0.1:$WebPort"

$ollamaReady = Test-Endpoint "$ollamaUrl/api/tags"
$backendReady = Test-Endpoint "$backendUrl/health"
$webReady = Test-Endpoint $webUrl

Write-Host "Sana yerel çalışma durumu" -ForegroundColor Cyan
Show-Status "Ollama" $ollamaReady $ollamaUrl
Show-Status "Backend" $backendReady $backendUrl
Show-Status "Web" $webReady $webUrl

if ($ollamaReady) {
    try {
        $tags = Invoke-RestMethod -Uri "$ollamaUrl/api/tags" -TimeoutSec 3
        $models = @($tags.models | ForEach-Object { $_.name })
        $modelState = if ($models -contains $Model) { "kurulu" } else { "eksik" }
        Write-Host "Model      $Model ($modelState)"
    }
    catch {
        Write-Host "Model      liste okunamadı" -ForegroundColor DarkYellow
    }
}
