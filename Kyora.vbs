' Inicia Kyora sin ventana de consola (doble clic, o desde un acceso directo).
' El arranque automatico con Windows ya no pasa por aqui: lo hace la tarea programada (scripts\ARRANQUE.md).
' Con el argumento /inicio espera unos segundos a que cargue el escritorio de Windows antes de arrancar.
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
raiz = fso.GetParentFolderName(WScript.ScriptFullName)
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "/inicio" Then WScript.Sleep 5000
End If
shell.CurrentDirectory = raiz & "\code"
shell.Run """" & raiz & "\code\.venv\Scripts\pythonw.exe"" -m kyora", 0, False
