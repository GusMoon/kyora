@echo off
rem Inicia Kyora CON consola (para ver errores). Uso diario: Kyora.vbs o el acceso directo, sin consola.
rem Para probar sin ocultar la barra de tareas de Windows: iniciar_kyora.bat --no-taskbar
cd /d "%~dp0..\code"
".venv\Scripts\python.exe" -m kyora %*
if errorlevel 1 (
  echo.
  echo Kyora termino con un error. Registro completo: %APPDATA%\Kyora\kyora.log
  pause
)
