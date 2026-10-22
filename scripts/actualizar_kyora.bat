@echo off
rem Actualiza Kyora despues de reemplazar sus archivos: cierra Kyora, instala dependencias, pasa las pruebas y la vuelve a abrir.
rem Si algo falla se detiene y NO abre una version rota.
setlocal
cd /d "%~dp0..\code"
echo [1/4] Cerrando Kyora...
".venv\Scripts\python.exe" -c "import win32gui,win32con;h=win32gui.FindWindow(None,'KyoraBar');h and win32gui.PostMessage(h,win32con.WM_CLOSE,0,0)"
timeout /t 4 /nobreak >nul
".venv\Scripts\python.exe" -m kyora --rescue
echo [2/4] Instalando dependencias...
".venv\Scripts\python.exe" -m pip install -r requirements-dev.txt
if errorlevel 1 goto :error
echo [3/4] Pasando las pruebas...
".venv\Scripts\python.exe" -m pytest -q
if errorlevel 1 goto :error
echo [4/4] Abriendo Kyora...
rem Si el arranque automatico esta instalado, se abre por la tarea: arranca igual que al iniciar sesion y la tarea figura "En ejecucion".
schtasks /query /tn "Kyora" >nul 2>&1
if errorlevel 1 (
  wscript "%~dp0..\Kyora.vbs"
) else (
  schtasks /run /tn "Kyora" >nul
)
echo Listo.
timeout /t 3 >nul
exit /b 0

:error
echo.
echo La actualizacion fallo. Kyora NO se ha abierto. Revisa los mensajes de arriba.
echo Si algo quedo raro en la pantalla, ejecuta scripts\rescate_kyora.bat.
pause
exit /b 1
