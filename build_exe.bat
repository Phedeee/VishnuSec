@echo off
REM =====================================================================
REM  build_exe.bat - Genera el ejecutable de la aplicacion SOC en Windows
REM  Uso: doble clic, o escribir  .\build_exe.bat  en la carpeta app_soc
REM  Resultado: dist\SOC_App\SOC_App.exe
REM  (este archivo esta escrito sin tildes a proposito, para que se vea
REM   bien en cualquier consola de Windows)
REM =====================================================================
setlocal
cd /d "%~dp0"

echo.
echo === Construccion del ejecutable SOC_App ===
echo.

where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python no esta instalado o no esta en el PATH.
    echo         Reinstale Python marcando la casilla "Add Python to PATH".
    goto :error
)

if not exist ".venv_build\Scripts\activate.bat" (
    echo [1/5] Creando entorno virtual de construccion...
    python -m venv .venv_build
    if errorlevel 1 goto :error
) else (
    echo [1/5] Entorno virtual de construccion ya existe.
)

call ".venv_build\Scripts\activate.bat"
if errorlevel 1 goto :error

echo [2/5] Instalando dependencias (puede tardar unos minutos la primera vez)...
python -m pip install --upgrade pip --quiet
pip install -r requirements.txt pyinstaller --quiet
if errorlevel 1 goto :error

echo [3/5] Generando el ejecutable con PyInstaller...
pyinstaller soc_app.spec --noconfirm --clean
if errorlevel 1 goto :error

echo [4/5] Copiando el archivo de configuracion junto al ejecutable...
copy /y config.ini "dist\SOC_App\config.ini" >nul

echo [5/5] Creando el archivo comprimido dist\SOC_App.zip ...
powershell -NoProfile -Command "Compress-Archive -Path 'dist\SOC_App' -DestinationPath 'dist\SOC_App.zip' -Force"
if errorlevel 1 echo         (no se pudo crear el .zip; puede comprimir la carpeta manualmente)

echo.
echo ====================================================================
echo  LISTO. El ejecutable esta en:
echo      %cd%\dist\SOC_App\SOC_App.exe
echo.
echo  Para llevarlo a otro computador copie TODA la carpeta dist\SOC_App
echo  (no solo el .exe) o use el archivo dist\SOC_App.zip. Para cambiar el servidor o la base de datos edite
echo  dist\SOC_App\config.ini con el Bloc de notas.
echo ====================================================================
echo.
pause
exit /b 0

:error
echo.
echo [ERROR] No se pudo generar el ejecutable. Revise los mensajes de arriba.
echo.
pause
exit /b 1
