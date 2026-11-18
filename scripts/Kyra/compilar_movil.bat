@echo off
rem Compila las DOS apps del movil: KyraAdmin.apk (administrador) y KyraFamily.apk (familia), en Family\Kyra\. Para una sola, usa
rem compilar_admin.bat o compilar_family.bat. Se pueden instalar las dos en el mismo telefono (cada una con sus datos).
setlocal
set KYRA_NO_EXPLORER=1
call "%~dp0compilar_admin.bat"
if errorlevel 1 exit /b 1
call "%~dp0compilar_family.bat"
if errorlevel 1 exit /b 1
echo.
echo Listo: Family\Kyra\KyraAdmin.apk y Family\Kyra\KyraFamily.apk
explorer /select,"%~dp0..\..\Family\Kyra\KyraFamily.apk"
exit /b 0
