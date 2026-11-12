@echo off
rem Quita el arranque automatico de Kyora: borra la tarea programada (y el acceso directo anterior, si queda alguno).
rem Para probar sin tocar la tarea real: quitar_inicio.bat NombreDePrueba
setlocal
set "NOMBRE=%~1"
if "%NOMBRE%"=="" set "NOMBRE=Kyora"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tarea_inicio.ps1" quitar -Nombre "%NOMBRE%"
if "%~1"=="" pause
