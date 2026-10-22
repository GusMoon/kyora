# Registra, quita o muestra la tarea programada que arranca Kyora al iniciar sesion.
# Lo usan instalar_inicio.bat y quitar_inicio.bat. Uso directo:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tarea_inicio.ps1 instalar|quitar|estado [-Nombre Kyora]
# (Los mensajes van sin tildes: Windows PowerShell 5.1 lee mal los .ps1 sin BOM.)
param(
    [Parameter(Position = 0)][ValidateSet('instalar', 'quitar', 'estado')][string]$Accion = 'estado',
    [string]$Nombre = 'Kyora'  # con otro nombre se puede probar sin tocar la tarea real
)
$ErrorActionPreference = 'Stop'

$raiz = Split-Path $PSScriptRoot -Parent
$codigo = Join-Path $raiz 'code'
$pythonw = Join-Path $codigo '.venv\Scripts\pythonw.exe'
$usuario = "$env:USERDOMAIN\$env:USERNAME"
$atajoViejo = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Kyora.lnk'
$esReal = $Nombre -eq 'Kyora'

function Buscar-Tarea { Get-ScheduledTask -TaskName $Nombre -ErrorAction SilentlyContinue }

function Instalar {
    if (-not (Test-Path $pythonw)) {
        throw "No existe $pythonw. Reinstala el entorno (GUIA_KYORA.md, seccion 5)."
    }
    # Se ejecuta pythonw directamente (no Kyora.vbs): asi la tarea figura "En ejecucion" mientras Kyora vive.
    $accion = New-ScheduledTaskAction -Execute $pythonw -Argument '-m kyora' -WorkingDirectory $codigo
    $disparador = New-ScheduledTaskTrigger -AtLogOn -User $usuario
    $disparador.Delay = 'PT5S'  # espera a que cargue el escritorio
    $ajustes = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $Nombre -Action $accion -Trigger $disparador -Settings $ajustes `
        -Principal $principal -Description 'Arranca Kyora al iniciar sesion.' -Force | Out-Null
    Write-Host "Listo: la tarea '$Nombre' arrancara Kyora al iniciar sesion (5 segundos despues)."
    if ($esReal -and (Test-Path $atajoViejo)) {
        Remove-Item $atajoViejo -Force  # el metodo anterior: si quedara, Kyora se intentaria abrir dos veces
        Write-Host 'Quitado el acceso directo anterior de la carpeta de Inicio.'
    }
}

function Quitar {
    $quitado = $false
    if (Buscar-Tarea) {
        Unregister-ScheduledTask -TaskName $Nombre -Confirm:$false
        Write-Host "Listo: quitada la tarea '$Nombre'. Kyora ya no arrancara sola."
        $quitado = $true
    }
    if ($esReal -and (Test-Path $atajoViejo)) {
        Remove-Item $atajoViejo -Force
        Write-Host 'Quitado tambien el acceso directo anterior de la carpeta de Inicio.'
        $quitado = $true
    }
    if (-not $quitado) { Write-Host 'Kyora no estaba configurada para arrancar sola.' }
}

function Estado {
    $tarea = Buscar-Tarea
    if (-not $tarea) {
        Write-Host "No hay tarea '$Nombre': Kyora NO arranca sola."
        if ($esReal -and (Test-Path $atajoViejo)) { Write-Host 'Pero existe el acceso directo anterior en la carpeta de Inicio.' }
        return
    }
    $info = Get-ScheduledTaskInfo -TaskName $Nombre
    $ajustes = $tarea.Settings
    Write-Host "Tarea '$Nombre': $($tarea.State)"
    Write-Host "  Se activa:        al iniciar sesion de $usuario, tras $($tarea.Triggers[0].Delay)"
    Write-Host "  Ejecuta:          $($tarea.Actions[0].Execute) $($tarea.Actions[0].Arguments)"
    Write-Host "  Limite de tiempo: $($ajustes.ExecutionTimeLimit) (PT0S = sin limite)"
    Write-Host "  Con bateria:      arranca=$($ajustes.DisallowStartIfOnBatteries -eq $false) sigue=$($ajustes.StopIfGoingOnBatteries -eq $false)"
    if ($info.LastRunTime.Year -lt 2000) {  # Windows usa 1999 para "nunca"
        Write-Host '  Ultima ejecucion: nunca (se ejecutara en el proximo inicio de sesion)'
    } else {
        Write-Host "  Ultima ejecucion: $($info.LastRunTime) (resultado $($info.LastTaskResult))"
    }
}

switch ($Accion) {
    'instalar' { Instalar }
    'quitar' { Quitar }
    'estado' { Estado }
}
