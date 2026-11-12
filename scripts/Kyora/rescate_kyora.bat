@echo off
rem Si Kyora se cerro mal: vuelve a mostrar las ventanas ocultas y la barra de tareas.
cd /d "%~dp0..\..\Family\Kyora"
".venv\Scripts\python.exe" -m kyora --rescue
pause
