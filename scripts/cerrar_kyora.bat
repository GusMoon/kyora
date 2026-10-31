@echo off
rem Cierra Kyora (y su proceso del teclado) y deja todo como estaba: ventanas ocultas, barra de tareas y acomodo de Windows.
setlocal
cd /d "%~dp0..\code"
echo Cerrando Kyora...
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match '-m kyora' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
timeout /t 2 /nobreak >nul
echo Devolviendo las ventanas y la barra de tareas...
".venv\Scripts\python.exe" -m kyora --rescue
echo Listo.
timeout /t 3 >nul
