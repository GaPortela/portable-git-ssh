@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PENDRIVE_PATH=%%~fI"
set "CHAVE_PATH=%PENDRIVE_PATH%\id_ed25519"
set "ENV_PATH=%PENDRIVE_PATH%\.env"

set "GIT_NAME="
set "GIT_EMAIL="

call :LOAD_CONFIG
if errorlevel 1 exit /b 1

if not exist "%CHAVE_PATH%" (
    echo [ERRO] Chave SSH nao encontrada:
    echo        %CHAVE_PATH%
    pause
    exit /b 1
)

echo ==========================================
echo     GIT PORTATIL: CLONE E CONFIG (WIN 11)
echo ==========================================
echo Pendrive:   %PENDRIVE_PATH%
echo Identidade: %GIT_NAME% ^<%GIT_EMAIL%^>
echo.

set GIT_SSH_COMMAND=ssh -i '%CHAVE_PATH%' -o IdentitiesOnly=yes

:MENU
echo 1. Clonar um novo repositorio (Privado)
echo 2. Configurar um projeto ja clonado
echo 3. Sair
set /p opt="Escolha uma opcao: "

if "%opt%"=="1" goto CLONE
if "%opt%"=="2" goto CONFIG
if "%opt%"=="3" exit
goto MENU

:CLONE
call :CHECK_GIT

echo.
set /p url="URL SSH (git@github.com:usuario/projeto.git): "

if not defined url (
    echo [ERRO] URL vazia.
    pause
    goto MENU
)

for %%F in ("%url:/=" "%") do set "FOLDER_NAME=%%~nF"

for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Desktop') do (
    set "DESKTOP_PATH=%%b"
)
call set "DESKTOP_PATH=%DESKTOP_PATH%"

echo.
set "CLONE_PATH="
set /p CLONE_PATH="Diretorio para clonar [Enter = Area de Trabalho]: "

if not defined CLONE_PATH (
    set "CLONE_PATH=%DESKTOP_PATH%"
) else (
    set "CLONE_PATH=!CLONE_PATH:"=!"
)

if not exist "!CLONE_PATH!\" (
    echo [ERRO] Diretorio de destino nao encontrado: !CLONE_PATH!
    pause
    goto MENU
)

cd /d "!CLONE_PATH!" || (
    echo [ERRO] Nao foi possivel acessar: !CLONE_PATH!
    pause
    goto MENU
)

echo Clonando "!FOLDER_NAME!" em: !cd!

git -c core.sshCommand="ssh -i '%CHAVE_PATH:\=/%' -o IdentitiesOnly=yes" clone "%url%"

if exist "!FOLDER_NAME!" (
    echo.
    echo [INFO] Pasta detectada. Aplicando configuracoes...
    cd /d "!FOLDER_NAME!"

    git config core.sshCommand "ssh -i '%CHAVE_PATH:\=/%' -o IdentitiesOnly=yes"
    git config --local user.name "!GIT_NAME!"
    git config --local user.email "!GIT_EMAIL!"

    echo [SUCESSO] Repositorio clonado e configurado!
    echo Local: !cd!
    echo Identidade Git: !GIT_NAME! ^<!GIT_EMAIL!^>

    echo [INFO] Abrindo PowerShell no projeto...
    start "PowerShell Git: !FOLDER_NAME!" powershell.exe -NoExit -Command "Write-Host 'Identidade Git: !GIT_NAME!' -ForegroundColor Cyan; git status"
) else (
    echo [AVISO] Nao foi possivel entrar na pasta automaticamente.
)

pause
goto MENU

:CONFIG
set /p folder="Arraste a pasta do projeto para aqui e de Enter: "
set "folder=!folder:"=!"
cd /d "!folder!" || (
    echo [ERRO] Nao foi possivel acessar o diretorio informado.
    pause
    goto MENU
)

git config core.sshCommand "ssh -i '%CHAVE_PATH:\=/%' -o IdentitiesOnly=yes"
git config --local user.name "!GIT_NAME!"
git config --local user.email "!GIT_EMAIL!"

echo.
echo [SUCESSO] Projeto configurado com sua identidade em: !cd!
echo Identidade Git: !GIT_NAME! ^<!GIT_EMAIL!^>
pause
goto MENU

:LOAD_CONFIG
if not exist "%ENV_PATH%" (
    echo [ERRO] Arquivo .env nao encontrado:
    echo        %ENV_PATH%
    echo.
    echo Copie .env.example para .env na raiz do pendrive e configure:
    echo   GIT_USER_NAME=Seu Nome
    echo   GIT_USER_EMAIL=seu@email.com
    pause
    exit /b 1
)

for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"GIT_USER_NAME=" "%ENV_PATH%"') do set "GIT_NAME=%%B"
for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"GIT_USER_EMAIL=" "%ENV_PATH%"') do set "GIT_EMAIL=%%B"

set "GIT_NAME=!GIT_NAME:"=!"
set "GIT_EMAIL=!GIT_EMAIL:"=!"

if not defined GIT_NAME (
    echo [ERRO] GIT_USER_NAME nao foi definido corretamente em:
    echo        %ENV_PATH%
    pause
    exit /b 1
)

if not defined GIT_EMAIL (
    echo [ERRO] GIT_USER_EMAIL nao foi definido corretamente em:
    echo        %ENV_PATH%
    pause
    exit /b 1
)

exit /b 0

:CHECK_GIT
echo [INFO] Verificando integridade do Git...
set "PATH=%PATH%;C:\Program Files\Git\cmd;C:\Program Files\Git\bin"

git --version >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Git operacional.
    goto :eof
)

if exist "C:\Program Files\Git\cmd\git.exe" (
    echo [!] Git encontrado no disco. Reiniciando terminal para atualizar caminhos...
    timeout /t 2 >nul
    start "" cmd /c "%~f0"
    exit
)

echo [AVISO] Git nao localizado. Iniciando instalacao...
winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements

if %errorlevel% equ 0 (
    echo [SUCESSO] Instalacao concluida. Reiniciando script...
    timeout /t 3 >nul
    start "" cmd /c "%~f0"
    exit
) else (
    echo [ERRO] Falha na instalacao automatica.
    pause
    goto MENU
)
