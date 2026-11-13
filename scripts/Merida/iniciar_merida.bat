@echo off
rem Abre Merida (la app web local) en el navegador: http://127.0.0.1:5180
rem La primera vez instala sus paquetes (necesita Node.js). Cierra esta ventana para apagar Merida y su servicio de musica.
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
rem El servicio de musica (tus listas de YouTube con tus cookies, descargar y enviar): el mismo motor que Kyora, con su Python.
rem Corre en esta misma ventana: al cerrarla se apaga junto con Merida. Si no esta el entorno de Kyora, Merida abre igual sin el.
set "KYORA=%~dp0..\..\Family\Kyora"
if exist "%KYORA%\.venv\Scripts\python.exe" (
  echo Arrancando el servicio de musica de Merida...
  pushd "%KYORA%"
  start "" /b ".venv\Scripts\python.exe" -m kyora.merida
  popd
) else (
  echo Aviso: no encuentro el entorno de Kyora, asi que Merida abre sin su servicio de musica.
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
