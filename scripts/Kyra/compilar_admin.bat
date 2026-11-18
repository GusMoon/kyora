@echo off
rem Compila KyraAdmin (la app del administrador: solo acepta cuentas de administrador y gestiona todas las cuentas) y deja el APK en
rem Family\Kyra\KyraAdmin.apk. Si falta Family\Kyra\env.json lo crea antes (ver preparar_movil.bat). La primera compilacion tarda varios minutos.
setlocal
set "FLAVOR=admin"
set "APK=KyraAdmin.apk"
goto :build

:build
cd /d "%~dp0..\..\Family\Kyra"
if not exist "env.json" (
  echo [0/3] Falta Family\Kyra\env.json: ejecutando preparar_movil.bat...
  call "%~dp0preparar_movil.bat"
  if errorlevel 1 exit /b 1
  cd /d "%~dp0..\..\Family\Kyra"
)
echo [1/3] Analizando el codigo...
call flutter analyze
if errorlevel 1 goto :error
echo [2/3] Compilando %APK% (release, flavor %FLAVOR%)...
call flutter build apk --release --flavor %FLAVOR% --dart-define-from-file=env.json
if errorlevel 1 goto :error
echo [3/3] Copiando el APK...
copy /y "build\app\outputs\flutter-apk\app-%FLAVOR%-release.apk" "%APK%" >nul
if errorlevel 1 goto :error
echo.
echo Listo: %CD%\%APK%
echo En el telefono: permite "instalar apps desconocidas" para la app desde la que lo abras y pulsa el archivo.
if not defined KYRA_NO_EXPLORER explorer /select,"%CD%\%APK%"
exit /b 0

:error
echo.
echo La compilacion fallo. Revisa los mensajes de arriba.
if not defined KYRA_NO_EXPLORER pause
exit /b 1
