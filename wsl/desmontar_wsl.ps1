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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       DESMONTAR PENDRIVE DA WSL          " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Unidade detectada: $($DriveLetter.ToUpper()):" -ForegroundColor Yellow
Write-Host "[INFO] Ponto de montagem: $MountPoint" -ForegroundColor Yellow
Write-Host ""

try {
    & wsl.exe -- mountpoint -q $MountPoint
    $IsMounted = ($LASTEXITCODE -eq 0)

    if (-not $IsMounted) {
        Write-Host "[INFO] $MountPoint nao esta montado." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "[INFO] Desmontando $MountPoint..." -ForegroundColor Yellow

    & wsl.exe -- sudo umount $MountPoint

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
