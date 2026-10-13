# Script de Compilación para Kiora (Generación de Ejecutable Windows .exe)
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   KIORA - COMPILADOR A EJECUTABLE (.EXE)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

$VenvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (Test-Path $VenvPython) {
    $PythonCmd = $VenvPython
    Write-Host "✓ Usando entorno virtual: .venv" -ForegroundColor Green
} else {
    $PythonCmd = "python"
    Write-Host "✓ Usando Python global del sistema" -ForegroundColor Gray
}

Write-Host "Verificando dependencias de empaquetado..." -ForegroundColor Cyan
& $PythonCmd -m pip install --quiet pyinstaller

Write-Host "Compilando aplicación con PyInstaller..." -ForegroundColor Yellow
& $PythonCmd -m PyInstaller --noconfirm --clean "$PSScriptRoot\kiora.spec"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " ✓ ¡COMPILACIÓN EXITOSA!" -ForegroundColor Green
    Write-Host "   Ejecutable generado en:" -ForegroundColor White
    Write-Host "   $PSScriptRoot\dist\Kiora\Kiora.exe" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✕ Ocurrió un error durante la compilación." -ForegroundColor Red
}
