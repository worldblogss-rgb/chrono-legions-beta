param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$PackageRoot = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$pubspec = Join-Path $ProjectRoot "pubspec.yaml"
$sourceLib = Join-Path $PackageRoot "lib"
$sourceAssets = Join-Path $PackageRoot "assets"
$sourceCards = Join-Path $sourceAssets "images\v08\cards"

if (-not (Test-Path $pubspec)) {
    throw "No se encontró pubspec.yaml en: $ProjectRoot"
}
if (-not (Test-Path $sourceLib) -or -not (Test-Path $sourceAssets)) {
    throw "El paquete no contiene las carpetas lib y assets."
}

$cardCount = @(Get-ChildItem $sourceCards -File -Filter "*.png").Count
if ($cardCount -ne 55) {
    throw "El paquete debe contener 55 imágenes de cartas; se encontraron $cardCount."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $ProjectRoot "_backup_CL_V0_8_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null

$targets = @(
    "lib\main.dart",
    "lib\theme\chrono_assets.dart",
    "lib\theme\chrono_theme.dart",
    "lib\widgets\battlefield_backdrop.dart",
    "assets\images\v08"
)

foreach ($relative in $targets) {
    $target = Join-Path $ProjectRoot $relative
    if (Test-Path $target) {
        $backupTarget = Join-Path $backup $relative
        $backupParent = Split-Path $backupTarget -Parent
        New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
        Copy-Item $target $backupTarget -Recurse -Force
    }
}

Copy-Item (Join-Path $sourceLib "*") (Join-Path $ProjectRoot "lib") -Recurse -Force
Copy-Item (Join-Path $sourceAssets "*") (Join-Path $ProjectRoot "assets") -Recurse -Force

$lines = Get-Content $pubspec
$assetLine = "    - assets/images/v08/"

if (-not ($lines -contains $assetLine)) {
    $flutterIndex = -1
    $assetsIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^flutter:\s*$") {
            $flutterIndex = $i
            break
        }
    }
    if ($flutterIndex -lt 0) {
        throw "No se encontró la sección flutter: en pubspec.yaml"
    }
    for ($i = $flutterIndex + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^[A-Za-z0-9_-]+:\s*$") { break }
        if ($lines[$i] -match "^\s{2}assets:\s*$") {
            $assetsIndex = $i
            break
        }
    }

    $updated = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $updated.Add($lines[$i])
        if ($assetsIndex -ge 0 -and $i -eq $assetsIndex) {
            $updated.Add($assetLine)
        }
        elseif ($assetsIndex -lt 0 -and $i -eq $flutterIndex) {
            $updated.Add("  assets:")
            $updated.Add($assetLine)
        }
    }
    Set-Content -Path $pubspec -Value $updated -Encoding UTF8
}

Write-Host ""
Write-Host "CL V0.8 visual instalada correctamente." -ForegroundColor Green
Write-Host "Cartas ilustradas: $cardCount"
Write-Host "Respaldo: $backup"
Write-Host ""
Write-Host "Siguiente:"
Write-Host "  flutter pub get"
Write-Host "  flutter analyze"
Write-Host "  flutter run -d edge"
