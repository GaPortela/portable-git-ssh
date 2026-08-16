# ============================================================
# GIT PORTATIL - DESMONTAR PENDRIVE DA WSL
#
# Estrutura esperada:
# <PENDRIVE>\
#   Windows\
#   Linux\
#   WSL\
#     desmontar_wsl.ps1
#
# Detecta automaticamente a letra do pendrive pela pasta
# onde este script esta localizado.
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PendriveRoot = Split-Path -Parent $ScriptDir
$Root = [System.IO.Path]::GetPathRoot($PendriveRoot)

if (-not $Root) {
    Write-Host "[ERRO] Nao foi possivel identificar a unidade do pendrive." -ForegroundColor Red
    exit 1
}

$DriveLetter = $Root.Substring(0, 1).ToLower()
$MountPoint = "/mnt/$DriveLetter"
$DistroName = "Ubuntu"

# Evita que o wsl.exe tente traduzir um diretorio atual localizado
# no proprio pendrive enquanto ele esta sendo desmontado.
Set-Location "$env:SystemRoot\System32"

function Test-UbuntuInstalled {
    $InstalledDistros = & "$env:SystemRoot\System32\wsl.exe" --list --quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel consultar as distribuicoes WSL instaladas."
    }

    $NormalizedDistros = @(
        $InstalledDistros | ForEach-Object { ($_ -replace "`0", "").Trim() }
    )

    return $NormalizedDistros -contains $DistroName
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       DESMONTAR PENDRIVE DA WSL          " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Unidade detectada: $($DriveLetter.ToUpper()):" -ForegroundColor Yellow
Write-Host "[INFO] Ponto de montagem: $MountPoint" -ForegroundColor Yellow
Write-Host ""

try {
    if (-not (Test-UbuntuInstalled)) {
        throw "A distribuicao WSL '$DistroName' nao esta instalada. Outra distribuicao nao sera utilizada."
    }

    Write-Host "[INFO] Distribuicao WSL: $DistroName" -ForegroundColor Yellow

    & "$env:SystemRoot\System32\wsl.exe" -d $DistroName -- mountpoint -q $MountPoint
    $IsMounted = ($LASTEXITCODE -eq 0)

    if (-not $IsMounted) {
        Write-Host "[INFO] $MountPoint nao esta montado." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "[INFO] Desmontando $MountPoint..." -ForegroundColor Yellow

    & "$env:SystemRoot\System32\wsl.exe" -d $DistroName -- sudo umount $MountPoint

    if ($LASTEXITCODE -ne 0) {
        throw "WSL retornou codigo $LASTEXITCODE ao desmontar $MountPoint."
    }

    Write-Host ""
    Write-Host "[SUCESSO] $MountPoint foi desmontado." -ForegroundColor Green
    Write-Host "[INFO] Agora o pendrive pode ser removido com seguranca da WSL." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "[ERRO] Falha ao desmontar: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
