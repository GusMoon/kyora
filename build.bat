@echo off
title Compilador de Kiora (.exe)
echo ========================================
echo    KIORA - COMPILADOR A EJECUTABLE (.EXE)
echo ========================================
echo.

if exist "%~dp0.venv\Scripts\python.exe" (
    set "PYTHON_CMD=%~dp0.venv\Scripts\python.exe"
    echo [OK] Usando entorno virtual: .venv
) else (
    set "PYTHON_CMD=python"
    echo [INFO] Usando Python del sistema
)

echo [1/2] Verificando PyInstaller...
"%PYTHON_CMD%" -m pip install --quiet pyinstaller

echo [2/2] Compilando Kiora...
"%PYTHON_CMD%" -m PyInstaller --noconfirm --clean "%~dp0kiora.spec"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ==========================================================
    echo  [EXITO] Ejecutable generado correctamente en:
    echo  %~dp0dist\Kiora\Kiora.exe
    echo ==========================================================
) else (
    echo.
    echo [ERROR] Hubo un error durante la compilacion.
)

pause
