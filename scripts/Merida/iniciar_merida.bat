@echo off
rem Abre Merida (la app web local) en el navegador: http://127.0.0.1:5180
rem La primera vez instala sus paquetes (necesita Node.js). Cierra esta ventana para apagar Merida.
rem Lee la URL y la clave publica de Server\supabase\.env (o de %APPDATA%\Kyora\chat.env); el correo y la contrasena se escriben en la app.
setlocal
cd /d "%~dp0..\..\Family\Merida"
where npm >nul 2>&1
if errorlevel 1 (
  echo No encuentro Node.js. Instalalo desde https://nodejs.org y abre una consola nueva.
  pause
  exit /b 1
)
rem Si Merida ya esta abierta en otra ventana, solo abre el navegador en lugar de fallar por el puerto ocupado.
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 5180 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 (
  echo Merida ya esta abierta: abriendo el navegador.
  start "" "http://127.0.0.1:5180"
  exit /b 0
)
if not exist "node_modules" (
  echo Instalando los paquetes de Merida, solo la primera vez...
  call npm install
  if errorlevel 1 goto :error
)
call npm run dev -- --open
if errorlevel 1 goto :error
exit /b 0

:error
echo.
echo Merida no pudo arrancar. Revisa los mensajes de arriba.
pause
exit /b 1
