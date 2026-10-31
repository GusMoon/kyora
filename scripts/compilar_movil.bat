@echo off
rem Compila la app del movil y deja el APK en mobile\KyoraChat.apk, listo para pasar al telefono (cable, Drive, WhatsApp...).
rem Si falta mobile\env.json lo crea antes (ver preparar_movil.bat). La primera compilacion tarda varios minutos.
setlocal
cd /d "%~dp0..\mobile"
if not exist "env.json" (
  echo [0/3] Falta mobile\env.json: ejecutando preparar_movil.bat...
  call "%~dp0preparar_movil.bat"
  if errorlevel 1 exit /b 1
  cd /d "%~dp0..\mobile"
)
echo [1/3] Analizando el codigo...
call flutter analyze
if errorlevel 1 goto :error
echo [2/3] Compilando el APK (release)...
call flutter build apk --release --dart-define-from-file=env.json
if errorlevel 1 goto :error
echo [3/3] Copiando el APK...
copy /y "build\app\outputs\flutter-apk\app-release.apk" "KyoraChat.apk" >nul
if errorlevel 1 goto :error
echo.
echo Listo: %CD%\KyoraChat.apk
echo En el telefono: permite "instalar apps desconocidas" para la app desde la que lo abras y pulsa el archivo.
explorer /select,"%CD%\KyoraChat.apk"
exit /b 0

:error
echo.
echo La compilacion fallo. Revisa los mensajes de arriba.
pause
exit /b 1
