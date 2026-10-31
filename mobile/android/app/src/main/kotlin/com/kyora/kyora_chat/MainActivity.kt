package com.kyora.kyora_chat

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Guarda una canción (MP3) en Música o Descargas, dentro de una subcarpeta: lo usa la pantalla de música.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/music_saver").setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val name = call.argument<String>("name") ?: throw IOException("Falta el nombre del archivo")
                val bytes = call.argument<ByteArray>("bytes") ?: throw IOException("Falta el contenido del archivo")
                val base = call.argument<String>("base") ?: "music"
                val folder = (call.argument<String>("folder") ?: "").trim().trim('/')
                result.success(saveAudio(name, bytes, base, folder))
            } catch (e: Exception) {
                result.error("save_failed", e.message ?: "No se pudo guardar la canción.", null)
            }
        }
    }

    /// Devuelve «Música/Kyora»: dónde quedó, para enseñárselo a la persona.
    private fun saveAudio(name: String, bytes: ByteArray, base: String, folder: String): String {
        val download = base == "download"
        val baseDir = if (download) Environment.DIRECTORY_DOWNLOADS else Environment.DIRECTORY_MUSIC
        val relative = if (folder.isEmpty()) baseDir else "$baseDir/$folder"
        val shown = (if (download) "Descargas" else "Música") + (if (folder.isEmpty()) "" else "/$folder")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10 y posteriores: MediaStore, sin pedir permisos. La canción sale también en el reproductor.
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "audio/mpeg")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = if (download) MediaStore.Downloads.EXTERNAL_CONTENT_URI else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val resolver = contentResolver
            val uri = resolver.insert(collection, values) ?: throw IOException("Android no dejó crear el archivo en $shown")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: throw IOException("No se pudo abrir el archivo en $shown")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null) // no dejar un archivo a medias
                throw e
            }
        } else {
            // Android 9 y anteriores: se escribe directo (necesita el permiso de almacenamiento del manifiesto).
            val dir = File(Environment.getExternalStoragePublicDirectory(baseDir), folder)
            if (!dir.exists() && !dir.mkdirs()) throw IOException("No se pudo crear la carpeta $shown")
            val file = File(dir, name)
            file.writeBytes(bytes)
            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("audio/mpeg"), null)
        }
        return shown
    }
}
