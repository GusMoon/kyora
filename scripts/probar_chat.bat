@echo off
rem Comprueba el chat desde la PC: inicia sesion en tu Supabase (datos de supabase\.env), saca la conversacion General y
rem enseña los ultimos mensajes. Con --send manda ademas un mensaje de prueba que se ve en el movil.
rem Uso: probar_chat.bat            (solo comprueba)       probar_chat.bat --send     (comprueba y manda la prueba)
cd /d "%~dp0..\code"
".venv\Scripts\python.exe" -m kyora.chat.check %*
set RESULTADO=%errorlevel%
if not "%RESULTADO%"=="0" (
  echo.
  echo La comprobacion no termino bien. Lee el mensaje de arriba.
  pause
)
exit /b %RESULTADO%
