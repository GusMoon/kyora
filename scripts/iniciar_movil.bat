@echo off
rem Abre la app del movil en un telefono Android conectado por USB (con la "depuracion USB" activada), en modo desarrollo.
rem Todo lo que escribas detras se pasa a "flutter run", por ejemplo:  iniciar_movil.bat -d <id_del_telefono>
rem Para ver los telefonos conectados:  flutter devices
setlocal
cd /d "%~dp0..\mobile"
if not exist "env.json" (
  call "%~dp0preparar_movil.bat"
  if errorlevel 1 exit /b 1
  cd /d "%~dp0..\mobile"
)
call flutter run --dart-define-from-file=env.json %*
if errorlevel 1 (
  echo.
  echo La app termino con un error. Si no ves tu telefono, ejecuta "flutter devices" y revisa la depuracion USB.
  pause
)
