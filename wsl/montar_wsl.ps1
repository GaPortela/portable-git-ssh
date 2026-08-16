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
$DistroName = "Ubuntu"

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

function Invoke-Ubuntu {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ArgsList
    )

    & "$env:SystemRoot\System32\wsl.exe" -d $DistroName -- @ArgsList

    if ($LASTEXITCODE -ne 0) {
        throw "$DistroName retornou codigo $LASTEXITCODE ao executar: $($ArgsList -join ' ')"
    }
}

try {
    if (-not (Test-UbuntuInstalled)) {
        throw "A distribuicao WSL '$DistroName' nao esta instalada. Outra distribuicao nao sera utilizada."
    }

    $UserUid = (Invoke-Ubuntu -ArgsList @("id", "-u") | Select-Object -Last 1).Trim()
    $UserGid = (Invoke-Ubuntu -ArgsList @("id", "-g") | Select-Object -Last 1).Trim()

    if ($UserUid -notmatch '^\d+$' -or $UserGid -notmatch '^\d+$') {
        throw "Nao foi possivel determinar UID/GID do usuario no $DistroName."
    }

    Write-Host "[INFO] Distribuicao WSL: $DistroName" -ForegroundColor Yellow
    Write-Host "[INFO] UID/GID detectados: $UserUid/$UserGid" -ForegroundColor Yellow
    Write-Host ""

    Invoke-Ubuntu -ArgsList @("sudo", "mkdir", "-p", $MountPoint)

    & "$env:SystemRoot\System32\wsl.exe" -d $DistroName -- "mountpoint" "-q" $MountPoint
    $AlreadyMounted = ($LASTEXITCODE -eq 0)

    if ($AlreadyMounted) {
        Write-Host "[INFO] $MountPoint ja esta montado. Remontando..." -ForegroundColor Yellow
        Invoke-Ubuntu -ArgsList @("sudo", "umount", $MountPoint)
    }

    Invoke-Ubuntu -ArgsList @(
        "sudo",
        "mount",
        "-t",
        "drvfs",
        $WindowsDrive,
        $MountPoint,
        "-o",
        "metadata,uid=$UserUid,gid=$UserGid,umask=0077"
    )

    Write-Host ""
    Write-Host "[SUCESSO] Pendrive montado em $MountPoint" -ForegroundColor Green
    Write-Host ""
    Write-Host "Agora execute no Ubuntu:" -ForegroundColor Cyan
    Write-Host "  cd $MountPoint/wsl"
    Write-Host "  chmod +x git_portatil_WSL.sh"
    Write-Host "  ./git_portatil_WSL.sh"
}
catch {
    Write-Host ""
    Write-Host "[ERRO] Falha ao preparar o pendrive: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
