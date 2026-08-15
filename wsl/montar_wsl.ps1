# ============================================================
# GIT PORTATIL - PREPARACAO DO PENDRIVE PARA WSL
# ============================================================

$ErrorActionPreference = "Stop"

# Descobre a unidade do pendrive ANTES de mudar o diretorio atual.
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$PendriveRoot = Split-Path -Parent $ScriptDir
$Root = [System.IO.Path]::GetPathRoot($PendriveRoot)

if (-not $Root) {
    Write-Host "[ERRO] Nao foi possivel identificar a unidade do pendrive." -ForegroundColor Red
    exit 1
}

$DriveLetter = $Root.Substring(0, 1).ToLower()
$WindowsDrive = "${DriveLetter}:"
$MountPoint = "/mnt/$DriveLetter"

# IMPORTANTE:
# impede o wsl.exe de tentar traduzir D:\WSL quando /mnt/d ainda nao existe.
Set-Location "$env:SystemRoot\System32"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       MONTAGEM DO PENDRIVE NO WSL        " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Unidade detectada: $WindowsDrive" -ForegroundColor Yellow
Write-Host "[INFO] Ponto de montagem: $MountPoint" -ForegroundColor Yellow
Write-Host ""

function Invoke-WSL {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ArgsList
    )

    & "$env:SystemRoot\System32\wsl.exe" -- @ArgsList

    if ($LASTEXITCODE -ne 0) {
        throw "WSL retornou codigo $LASTEXITCODE ao executar: $($ArgsList -join ' ')"
    }
}

try {
    Invoke-WSL @("sudo", "mkdir", "-p", $MountPoint)

    & "$env:SystemRoot\System32\wsl.exe" -- "mountpoint" "-q" $MountPoint
    $AlreadyMounted = ($LASTEXITCODE -eq 0)

    if ($AlreadyMounted) {
        Write-Host "[INFO] $MountPoint ja esta montado. Remontando..." -ForegroundColor Yellow
        Invoke-WSL @("sudo", "umount", $MountPoint)
    }

    Invoke-WSL @(
        "sudo",
        "mount",
        "-t",
        "drvfs",
        $WindowsDrive,
        $MountPoint,
        "-o",
        "metadata,uid=1000,gid=1000,umask=0077"
    )

    Write-Host ""
    Write-Host "[SUCESSO] Pendrive montado em $MountPoint" -ForegroundColor Green
    Write-Host ""
    Write-Host "Agora execute na WSL:" -ForegroundColor Cyan
    Write-Host "  cd $MountPoint/WSL"
    Write-Host "  chmod +x git_portatil_WSL.sh"
    Write-Host "  ./git_portatil_WSL.sh"
}
catch {
    Write-Host ""
    Write-Host "[ERRO] Falha ao preparar o pendrive: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
