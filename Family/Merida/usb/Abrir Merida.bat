@echo off
rem Merida desde el USB (o desde esta carpeta): abre http://127.0.0.1:5180 y arranca el servicio de musica.
rem No hace falta instalar nada: trae su propio Node, Python y FFmpeg en runtime\. Cierra esta ventana para apagarlo todo.
rem El correo y la contrasena se escriben en la pantalla de acceso; esta carpeta no guarda ninguna credencial.
setlocal
cd /d "%~dp0"

if not exist "web\index.html" goto :falta
if not exist "runtime\node\node.exe" goto :falta

rem Si Merida ya esta abierta en otra ventana, solo abre el navegador en lugar de fallar por el puerto ocupado.
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 5180 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 (
  echo Merida ya esta abierta: abriendo el navegador.
  start "" "http://127.0.0.1:5180"
  exit /b 0
)

rem Node y FFmpeg propios: el servicio de musica los busca en el PATH.
set "PATH=%~dp0runtime\node;%~dp0runtime\ffmpeg;%PATH%"

if exist "runtime\python\python.exe" (
  echo Arrancando el servicio de musica...
  start "" /b "runtime\python\python.exe" -m kyora.merida
) else (
  echo Aviso: no esta el Python de runtime, asi que Merida abre sin su servicio de musica.
)

"runtime\node\node.exe" server.mjs --open
if errorlevel 1 (
  echo.
  echo Merida no pudo arrancar. Revisa los mensajes de arriba.
  pause
  exit /b 1
)
exit /b 0

:falta
echo Faltan archivos de esta carpeta. En el equipo de desarrollo ejecuta, dentro de Family\Merida:
echo     npm run build:usb
pause
exit /b 1
