param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$assetDir = Join-Path $ProjectRoot "assets\images\v08"
$pubspec = Join-Path $ProjectRoot "pubspec.yaml"

if (-not (Test-Path $assetDir)) {
    throw "No existe la carpeta: $assetDir"
}

$required = @(
    "menu_v08.png",
    "chrono_logo.png",
    "battlefield_v08.png",
    "icons_resources_battle.png",
    "icons_ui.png",
    "scipio.png",
    "hannibal.png",
    "hannibal_gold.png"
)

# Si las imágenes fueron descargadas con sus títulos originales,
# intenta localizar cada una y crear el nombre canónico que usa el código.
$patterns = @{
    "menu_v08.png" = "*Men*Chrono*Roma*Cartago*.png"
    "chrono_logo.png" = "*Emblema*dorado*Chrono*.png"
    "battlefield_v08.png" = "*Tablero*oscuro*romano*.png"
    "icons_resources_battle.png" = "*recursos*batalla*.png"
    "icons_ui.png" = "*ocho*iconos*.png"
    "scipio.png" = "*Escipi*n*Africano*.png"
    "hannibal.png" = "*An*bal*Barca*.png"
    "hannibal_gold.png" = "*An*bal*medall*n*dorado*.png"
}

foreach ($name in $required) {
    $target = Join-Path $assetDir $name
    if (-not (Test-Path $target)) {
        $pattern = $patterns[$name]
        $candidate = Get-ChildItem $assetDir -File -Filter "*.png" |
            Where-Object { $_.Name -like $pattern } |
            Select-Object -First 1
        if ($candidate) {
            Copy-Item $candidate.FullName $target
            Write-Host "Creado alias: $name <- $($candidate.Name)"
        }
    }
}

$missing = @()
foreach ($name in $required) {
    if (-not (Test-Path (Join-Path $assetDir $name))) {
        $missing += $name
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "FALTAN ESTAS IMAGENES:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    throw "Completa o renombra las imágenes antes de continuar."
}

if (-not (Test-Path $pubspec)) {
    throw "No se encontró pubspec.yaml en $ProjectRoot"
}

$lines = Get-Content $pubspec
$assetLine = "    - assets/images/v08/"

if (-not ($lines -contains $assetLine)) {
    $flutterIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^flutter:\s*$") {
            $flutterIndex = $i
            break
        }
    }

    if ($flutterIndex -lt 0) {
        throw "No se encontró la sección flutter: en pubspec.yaml"
    }

    $assetsIndex = -1
    for ($i = $flutterIndex + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^[A-Za-z0-9_-]+:\s*$") {
            break
        }
        if ($lines[$i] -match "^\s{2}assets:\s*$") {
            $assetsIndex = $i
            break
        }
    }

    $newLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $newLines.Add($lines[$i])
        if ($assetsIndex -ge 0 -and $i -eq $assetsIndex) {
            $newLines.Add($assetLine)
        }
        elseif ($assetsIndex -lt 0 -and $i -eq $flutterIndex) {
            $newLines.Add("  assets:")
            $newLines.Add($assetLine)
        }
    }

    Set-Content -Path $pubspec -Value $newLines -Encoding UTF8
    Write-Host "pubspec.yaml actualizado con assets/images/v08/"
}
else {
    Write-Host "pubspec.yaml ya contiene assets/images/v08/"
}

Write-Host ""
Write-Host "IMAGENES V0.8 OK:" -ForegroundColor Green
Get-ChildItem $assetDir -File | Where-Object { $_.Name -in $required } |
    Select-Object Name, Length | Format-Table -AutoSize

Write-Host ""
Write-Host "Siguiente:" -ForegroundColor Cyan
Write-Host "  flutter pub get"
Write-Host "  flutter analyze"
Write-Host "  flutter run -d edge"
