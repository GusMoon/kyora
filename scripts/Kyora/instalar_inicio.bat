@echo off
rem Hace que Kyora arranque sola al iniciar sesion: registra una tarea programada (ver ARRANQUE.md).
rem Si habia un acceso directo en la carpeta de Inicio (metodo anterior), lo quita para que no se abra dos veces.
rem Se puede ejecutar de nuevo sin problema: reemplaza la tarea. No necesita permisos de administrador.
rem Para probar sin tocar la tarea real: instalar_inicio.bat NombreDePrueba
setlocal
set "NOMBRE=%~1"
if "%NOMBRE%"=="" set "NOMBRE=Kyora"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tarea_inicio.ps1" instalar -Nombre "%NOMBRE%"
if errorlevel 1 (
  echo.
  echo No se pudo crear la tarea. Revisa los mensajes de arriba.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tarea_inicio.ps1" estado -Nombre "%NOMBRE%"
if "%~1"=="" pause
