@echo off
rem Prepara la app del movil (Flutter): crea mobile\env.json con la URL y la clave publica de tu Supabase (salen de supabase\.env;
rem NUNCA el correo ni la contrasena) y descarga los paquetes de la app. Se ejecuta una vez, o cuando cambies de proyecto de Supabase.
setlocal
cd /d "%~dp0..\code"
echo [1/2] Creando mobile\env.json desde supabase\.env...
".venv\Scripts\python.exe" -m kyora.chat.mobile_env
if errorlevel 1 goto :error
where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo No encuentro Flutter. Instalalo (ver mobile\README.md) o abre una consola nueva si lo acabas de instalar.
  goto :error
)
echo [2/2] Descargando los paquetes de la app...
cd /d "%~dp0..\mobile"
call flutter pub get
if errorlevel 1 goto :error
echo.
echo Listo. Ahora usa compilar_movil.bat (crea el APK para instalar en el telefono) o iniciar_movil.bat (con el telefono conectado por USB).
exit /b 0

:error
echo.
echo La preparacion fallo. Revisa los mensajes de arriba.
pause
exit /b 1
