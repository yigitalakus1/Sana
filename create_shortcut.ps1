<#
    Masaüstünde "Sana" kısayolu oluşturur.

    Kısayolun kendisi (.lnk) mutlak yol içerdiği için depoya konmaz; her
    bilgisayarda bu script ile üretilir. Yollar bu dosyanın bulunduğu klasöre
    göre hesaplanır, yani depo nereye klonlanırsa çalışır.
#>

[CmdletBinding()]
param(
    # Kısayolun görünen adı.
    [string]$Name = 'Sana',

    # Masaüstü yerine başka bir klasöre koymak için.
    [string]$Destination
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$target = Join-Path $root 'Sana Baslat.cmd'
$icon = Join-Path $root 'sana.ico'

if (-not (Test-Path $target)) {
    throw "Başlatıcı bulunamadı: $target"
}

if (-not $Destination) {
    $Destination = [Environment]::GetFolderPath('Desktop')
}
if (-not (Test-Path $Destination)) {
    throw "Hedef klasör bulunamadı: $Destination"
}

$linkPath = Join-Path $Destination "$Name.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($linkPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $root
$shortcut.Description = 'Sana - tahlil sonuclarini sade Turkce aciklar (yerel calisir)'
$shortcut.WindowStyle = 1
if (Test-Path $icon) {
    $shortcut.IconLocation = "$icon,0"
}
$shortcut.Save()

Write-Host ''
Write-Host "  Kısayol oluşturuldu:" -ForegroundColor Green
Write-Host "  $linkPath"
Write-Host ''
Write-Host '  Masaüstündeki Sana simgesine çift tıklayarak uygulamayı açabilirsin.'
Write-Host ''
