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
echo     GIT PORTATIL: CLONE E CONFIG (WIN)
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
if errorlevel 1 (
    pause
    goto MENU
)

echo.
:READ_CLONE_URL
set "url="
set /p url="URL SSH (git@github.com:usuario/projeto.git): "

if not defined url (
    echo [ERRO] URL vazia.
    pause
    goto MENU
)

set "SSH_URL_VALID="
set "SSH_URL_REMAINDER=!url:~6!"
set "SSH_URL_WITHOUT_SLASH=!SSH_URL_REMAINDER:/=!"
if /I "!url:~0,6!"=="ssh://" if not "!SSH_URL_REMAINDER!"=="!SSH_URL_WITHOUT_SLASH!" if not "!url:~-1!"=="/" set "SSH_URL_VALID=1"

set "URL_WITHOUT_SCHEME=!url:://=!"
set "SSH_URL_AFTER_AT="
for /f "tokens=1,* delims=@" %%A in ("!url!") do set "SSH_URL_AFTER_AT=%%B"
set "SSH_AFTER_AT_WITHOUT_COLON=!SSH_URL_AFTER_AT::=!"
if "!URL_WITHOUT_SCHEME!"=="!url!" if defined SSH_URL_AFTER_AT if not "!SSH_AFTER_AT_WITHOUT_COLON!"=="!SSH_URL_AFTER_AT!" if not "!url:~-1!"==":" set "SSH_URL_VALID=1"

if not defined SSH_URL_VALID (
    echo [ERRO] URL invalida. HTTP/HTTPS e outros formatos nao sao aceitos.
    echo [INFO] Informe uma URL SSH, por exemplo:
    echo        git@github.com:usuario/projeto.git
    echo.
    set "url="
    goto READ_CLONE_URL
)

set "FOLDER_NAME="
set "REPO_SOURCE=!url!"
if "!REPO_SOURCE:~-1!"=="/" set "REPO_SOURCE=!REPO_SOURCE:~0,-1!"
for %%F in ("!REPO_SOURCE:/=\!") do set "FOLDER_NAME=%%~nxF"
if /I "!FOLDER_NAME:~-4!"==".git" set "FOLDER_NAME=!FOLDER_NAME:~0,-4!"

if not defined FOLDER_NAME (
    echo [ERRO] Nao foi possivel determinar o nome do repositorio pela URL.
    pause
    goto MENU
)

if "!FOLDER_NAME!"=="." (
    echo [ERRO] Nome de repositorio invalido.
    pause
    goto MENU
)

if "!FOLDER_NAME!"==".." (
    echo [ERRO] Nome de repositorio invalido.
    pause
    goto MENU
)

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

if exist "!FOLDER_NAME!" (
    echo [ERRO] O destino ja existe: !CLONE_PATH!\!FOLDER_NAME!
    pause
    goto MENU
)

git -c core.sshCommand="ssh -i '%CHAVE_PATH:\=/%' -o IdentitiesOnly=yes" clone "!url!" "!FOLDER_NAME!"

if errorlevel 1 (
    echo [ERRO] Falha ao clonar o repositorio.
    echo [INFO] Verifique a mensagem do Git exibida acima.
    pause
    goto MENU
)

if exist "!FOLDER_NAME!" (
    echo.
    echo [INFO] Pasta detectada. Aplicando configuracoes...

    call :CONFIGURE_REPO "!CLONE_PATH!\!FOLDER_NAME!"
    if errorlevel 1 (
        echo [ERRO] O clone terminou, mas a configuracao local falhou.
        pause
        goto MENU
    )

    cd /d "!FOLDER_NAME!" || (
        echo [ERRO] Nao foi possivel acessar o repositorio clonado.
        pause
        goto MENU
    )

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
call :CHECK_GIT
if errorlevel 1 (
    pause
    goto MENU
)

set /p folder="Arraste a pasta do projeto para aqui e de Enter: "
set "folder=!folder:"=!"

call :CONFIGURE_REPO "!folder!"
if errorlevel 1 (
    echo [ERRO] Nao foi possivel configurar o diretorio informado.
    pause
    goto MENU
)

cd /d "!folder!" || (
    echo [ERRO] Nao foi possivel acessar o diretorio informado.
    pause
    goto MENU
)

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

:CONFIGURE_REPO
set "REPO_PATH=%~1"

if not exist "%REPO_PATH%\" (
    echo [ERRO] Diretorio nao encontrado: %REPO_PATH%
    exit /b 1
)

git -C "%REPO_PATH%" rev-parse --show-toplevel >nul 2>&1
if errorlevel 1 (
    echo [ERRO] O caminho informado nao e um repositorio Git valido:
    echo        %REPO_PATH%
    exit /b 1
)

git -C "%REPO_PATH%" config --local core.sshCommand "ssh -i '%CHAVE_PATH:\=/%' -o IdentitiesOnly=yes"
if errorlevel 1 exit /b 1

git -C "%REPO_PATH%" config --local user.name "!GIT_NAME!"
if errorlevel 1 exit /b 1

git -C "%REPO_PATH%" config --local user.email "!GIT_EMAIL!"
if errorlevel 1 exit /b 1

exit /b 0

:CHECK_GIT
echo [INFO] Verificando Git e OpenSSH...
set "PATH=%PATH%;C:\Program Files\Git\cmd;C:\Program Files\Git\bin"

git --version >nul 2>&1
if not errorlevel 1 (
    ssh -V >nul 2>&1
    if not errorlevel 1 (
        echo [OK] Git e OpenSSH operacionais.
        exit /b 0
    )
)

where winget >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Git ou OpenSSH nao foi localizado e o winget nao esta disponivel.
    echo [INFO] Instale o Git for Windows manualmente e execute novamente.
    exit /b 1
)

echo [AVISO] Git ou OpenSSH nao localizado. Iniciando instalacao pelo winget...
winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements

if errorlevel 1 (
    echo [ERRO] Falha na instalacao automatica.
    exit /b 1
)

set "PATH=%PATH%;C:\Program Files\Git\cmd;C:\Program Files\Git\bin"
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] A instalacao terminou, mas o Git ainda nao foi localizado.
    exit /b 1
)

ssh -V >nul 2>&1
if errorlevel 1 (
    echo [ERRO] A instalacao terminou, mas o OpenSSH ainda nao foi localizado.
    exit /b 1
)

echo [SUCESSO] Git e OpenSSH instalados e operacionais.
exit /b 0
