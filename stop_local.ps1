[CmdletBinding()]
param()

$stateDir = Join-Path $PSScriptRoot ".sana-local"

function Stop-TrackedProcess {
    param([string]$Name)

    $statePath = Join-Path $stateDir "$Name.json"
    if (-not (Test-Path $statePath)) {
        Write-Host ("{0,-10} bu script tarafından başlatılmamış." -f $Name)
        return
    }

    try {
        $state = Get-Content -Raw $statePath | ConvertFrom-Json
        $processId = [int]$state.process_id
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $sameStart = $false
        if ($process -and $state.started_at) {
            $expectedStart = [DateTime]::Parse($state.started_at).ToUniversalTime()
            $actualStart = $process.StartTime.ToUniversalTime()
            $sameStart = [Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -lt 5
        }
        if ($process -and $process.ProcessName -like "$($state.process_name)*" -and $sameStart) {
            Stop-Process -Id $processId
            $process.WaitForExit(5000) | Out-Null
            Write-Host ("{0,-10} durduruldu." -f $Name) -ForegroundColor Green
        } else {
            Write-Host ("{0,-10} zaten kapalı veya süreç kaydı eski." -f $Name)
        }
    }
    finally {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $stateDir)) {
    Write-Host "Bu script tarafından başlatılmış bir Sana süreci bulunamadı."
    return
}

Stop-TrackedProcess "web"
Stop-TrackedProcess "backend"
Stop-TrackedProcess "ollama"
