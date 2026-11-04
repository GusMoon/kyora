package com.kyora.kyora_chat

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.media.audiofx.Visualizer
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

// AudioServiceActivity es un FlutterActivity que además deja al reproductor hablar con su notificacion.
class MainActivity : AudioServiceActivity() {
    // La respuesta pendiente del selector de carpeta (solo puede haber uno abierto a la vez).
    private var pendingFolder: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureAudioLevels(flutterEngine)
        configureBackground(flutterEngine)
        configureDevice(flutterEngine)
        // Guarda una canción (MP3): en la carpeta que la persona eligió con el selector de Android, o si no hay, en Música o
        // Descargas dentro de una subcarpeta. Lo usa la pantalla de música.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/music_saver").setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> try {
                    val name = call.argument<String>("name") ?: throw IOException("Falta el nombre del archivo")
                    val bytes = call.argument<ByteArray>("bytes") ?: throw IOException("Falta el contenido del archivo")
                    val treeUri = (call.argument<String>("treeUri") ?: "").trim()
                    if (treeUri.isNotEmpty()) {
                        result.success(saveInTree(name, bytes, Uri.parse(treeUri)))
                    } else {
                        val base = call.argument<String>("base") ?: "music"
                        val folder = (call.argument<String>("folder") ?: "").trim().trim('/')
                        result.success(saveAudio(name, bytes, base, folder))
                    }
                } catch (e: FolderLostException) {
                    result.error("folder_lost", e.message, null)
                } catch (e: Exception) {
                    result.error("save_failed", e.message ?: "No se pudo guardar la canción.", null)
                }
                "pickFolder" -> pickFolder(result)
                "listDir" -> listDir(call.argument<String>("treeUri") ?: "", call.argument<String>("dirUri") ?: "", result)
                "createFolder" -> createFolder(
                    call.argument<String>("treeUri") ?: "",
                    call.argument<String>("parentUri") ?: "",
                    call.argument<String>("name") ?: "",
                    result,
                )
                "moveSongs" -> moveSongs(
                    call.argument<String>("treeUri") ?: "",
                    call.argument<List<String>>("uris") ?: emptyList(),
                    call.argument<String>("fromUri") ?: "",
                    call.argument<String>("toUri") ?: "",
                    result,
                )
                "readDurations" -> readDurations(call.argument<List<String>>("uris") ?: emptyList(), result)
                "readArt" -> readArt(call.argument<List<String>>("uris") ?: emptyList(), result)
                "prepareCover" -> inThread(result, "cover_failed", "No se pudo abrir esa imagen.") {
                    prepareCover(call.argument<String>("path") ?: "")
                }
                "storeCover" -> inThread(result, "cover_failed", "No se pudo guardar la imagen.") {
                    storeCover(call.argument<String>("key") ?: "", call.argument<ByteArray>("bytes") ?: ByteArray(0), call.argument<Boolean>("keep") ?: false)
                }
                "readFile" -> inThread(result, "read_failed", "No se pudo leer la canción.") {
                    readSong(call.argument<String>("uri") ?: "")
                }
                "writeFile" -> inThread(result, "write_failed", "No se pudo escribir en la canción.") {
                    writeSong(call.argument<String>("uri") ?: "", call.argument<ByteArray>("bytes") ?: ByteArray(0))
                    null
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- qué tan fuerte suena (para los aros del reproductor) ----------

    private var visualizer: Visualizer? = null
    private var levelSink: EventChannel.EventSink? = null
    private var pendingLevels: MethodChannel.Result? = null

    private fun configureAudioLevels(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/audio_levels").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startLevels(result)
                "stop" -> {
                    stopVisualizer()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/audio_levels/stream").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                levelSink = events
            }

            override fun onCancel(arguments: Any?) {
                levelSink = null
            }
        })
    }

    private fun startLevels(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            if (pendingLevels != null) {
                result.success(false)
                return
            }
            pendingLevels = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), ASK_AUDIO)
            return
        }
        result.success(startVisualizer())
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ASK_AUDIO) return
        val result = pendingLevels ?: return
        pendingLevels = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && startVisualizer())
    }

    /// Escucha la salida de audio (sesión 0: el reproductor en segundo plano no da la suya) y manda la fuerza del sonido, de 0 a 1.
    private fun startVisualizer(): Boolean {
        if (visualizer != null) return true
        return try {
            val created = Visualizer(0)
            val range = Visualizer.getCaptureSizeRange()
            created.captureSize = 256.coerceIn(range[0], range[1])
            created.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(source: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                    val samples = waveform ?: return
                    if (samples.isEmpty()) return
                    var sum = 0.0
                    for (sample in samples) {
                        val centered = ((sample.toInt() and 0xff) - 128) / 128.0
                        sum += centered * centered
                    }
                    val level = Math.sqrt(sum / samples.size)
                    runOnUiThread { levelSink?.success(level) }
                }

                override fun onFftDataCapture(source: Visualizer?, fft: ByteArray?, samplingRate: Int) {}
            }, minOf(Visualizer.getMaxCaptureRate(), 20000), true, false)
            created.enabled = true
            visualizer = created
            true
        } catch (e: Exception) {
            stopVisualizer()
            false
        }
    }

    private fun stopVisualizer() {
        val current = visualizer ?: return
        visualizer = null
        try {
            current.enabled = false
            current.release()
        } catch (_: Exception) {
        }
    }

    // En segundo plano Android calla el sonido que lee el Visualizer y medirlo solo gasta batería: al dejar la pantalla se apaga (al volver,
    // la app lo enciende otra vez).
    override fun onStop() {
        stopVisualizer()
        super.onStop()
    }

    override fun onDestroy() {
        stopVisualizer()
        super.onDestroy()
    }

    // ---------- música en segundo plano: que Android no la detenga ----------

    /** El bloqueo de Wi-Fi vive aparte de la pantalla: sigue activo aunque la actividad se destruya mientras la música suena. */
    private object BackgroundLocks {
        private var wifi: WifiManager.WifiLock? = null

        @Suppress("DEPRECATION")
        fun wifi(context: Context, on: Boolean) {
            if (on) {
                if (wifi?.isHeld == true) return
                val manager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifi = manager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "kyora:musica").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } else {
                wifi?.let { if (it.isHeld) it.release() }
                wifi = null
            }
        }
    }

    private fun configureBackground(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/background").setMethodCallHandler { call, result ->
            when (call.method) {
                // La música que llega por internet no se corta cuando la pantalla se apaga y el Wi-Fi quiere dormirse.
                "wifiLock" -> try {
                    BackgroundLocks.wifi(this, call.argument<Boolean>("on") == true)
                    result.success(null)
                } catch (e: Exception) {
                    result.success(null)
                }
                // ¿Android deja a la app en paz en segundo plano? (excluida de la optimización de batería)
                "batteryUnrestricted" -> {
                    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.M || power.isIgnoringBatteryOptimizations(packageName))
                }
                // Abre el aviso del sistema para excluir la app; si el teléfono no lo permite, la lista de ajustes de batería.
                "requestBatteryExemption" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                        )
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        } catch (_: Exception) {
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // El espacio del almacenamiento interno, para la tarjeta de Inicio.
    private fun configureDevice(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "storage" -> try {
                    val stat = StatFs(Environment.getDataDirectory().path)
                    result.success(mapOf("total" to stat.totalBytes, "free" to stat.availableBytes))
                } catch (e: Exception) {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- carpeta elegida con el selector de Android ----------

    private class FolderLostException(message: String) : IOException(message)

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolder != null) {
            result.error("busy", "Ya hay un selector de carpeta abierto.", null)
            return
        }
        pendingFolder = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, PICK_FOLDER)
        } catch (e: Exception) {
            pendingFolder = null
            result.error("no_picker", "Este teléfono no tiene selector de carpetas.", null)
        }
    }

    @Deprecated("Lo usa el selector de carpeta (FlutterActivity todavía no ofrece otra forma).")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER) return
        val result = pendingFolder ?: return
        pendingFolder = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // la persona cerró el selector sin elegir
            return
        }
        try {
            // Para que el permiso siga valiendo cuando se cierre la app y se reinicie el teléfono.
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            result.success(mapOf("uri" to uri.toString(), "name" to folderName(uri)))
        } catch (e: Exception) {
            result.error("pick_failed", e.message ?: "No se pudo usar esa carpeta.", null)
        }
    }

    /// El nombre que ve la persona: el de la carpeta («Música», «Mis canciones»…).
    private fun folderName(tree: Uri): String {
        val folder = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        return try {
            contentResolver.query(folder, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: "Carpeta elegida"
        } catch (e: Exception) {
            "Carpeta elegida"
        }
    }

    // ---------- carpetas: ver, crear y mover (cambios reales en el almacenamiento) ----------

    /// La dirección del documento de una carpeta: la de la raíz elegida si `dir` viene vacío.
    private fun docUri(tree: Uri, dir: String): Uri =
        if (dir.isBlank()) DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree)) else Uri.parse(dir)

    private fun isAudio(name: String, mime: String) = name.lowercase().endsWith(".mp3") || mime == "audio/mpeg"

    /// Hace el trabajo en un hilo aparte (con muchas canciones tarda) y contesta en el hilo principal.
    private fun inThread(result: MethodChannel.Result, code: String, fallback: String, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: FolderLostException) {
                runOnUiThread { result.error("folder_lost", e.message, null) }
            } catch (e: Exception) {
                runOnUiThread { result.error(code, e.message ?: fallback, null) }
            }
        }.start()
    }

    /// Lo que hay dentro de UNA carpeta (sin bajar a las subcarpetas): `{folders: [{uri, name, count}], songs: [{uri, name, size, modified}]}`.
    /// `count` son los .mp3 que tiene directamente cada subcarpeta.
    private fun listDir(treeUri: String, dirUri: String, result: MethodChannel.Result) {
        if (treeUri.isEmpty()) {
            result.success(mapOf("folders" to emptyList<Any>(), "songs" to emptyList<Any>()))
            return
        }
        inThread(result, "list_failed", "No se pudo leer la carpeta.") { readDir(Uri.parse(treeUri), dirUri) }
    }

    private fun childrenOf(tree: Uri, dir: Uri, columns: Array<String>, shown: String): Cursor {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(dir))
        val queried = try {
            contentResolver.query(children, columns, null, null, null)
        } catch (e: SecurityException) {
            throw FolderLostException("Android ya no deja leer «$shown»: elige la carpeta otra vez.")
        } catch (e: IllegalArgumentException) {
            throw FolderLostException("La carpeta «$shown» ya no existe: elige otra.")
        }
        return queried ?: throw FolderLostException("No se pudo leer «$shown»: elige la carpeta otra vez.")
    }

    private fun readDir(tree: Uri, dirUri: String): Map<String, Any?> {
        val shown = folderName(tree)
        val dir = docUri(tree, dirUri)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val folders = mutableListOf<Map<String, Any?>>()
        val songs = mutableListOf<Map<String, Any?>>()
        childrenOf(tree, dir, columns, shown).use {
            while (it.moveToNext() && songs.size < MAX_SONGS) {
                val id = it.getString(0) ?: continue
                val name = it.getString(1) ?: continue
                val mime = it.getString(2) ?: ""
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id).toString()
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    folders.add(mapOf("uri" to uri, "name" to name))
                } else if (isAudio(name, mime)) {
                    songs.add(
                        mapOf(
                            "uri" to uri,
                            "name" to name,
                            "size" to (if (it.isNull(3)) 0L else it.getLong(3)),
                            "modified" to (if (it.isNull(4)) 0L else it.getLong(4)),
                        )
                    )
                }
            }
        }
        // cuántas canciones tiene cada subcarpeta: se cuentan varias a la vez para que entrar sea rápido
        val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
        val counted = try {
            val jobs = folders.map { f -> java.util.concurrent.Callable { f + ("count" to countSongs(tree, Uri.parse(f["uri"] as String), shown)) } }
            pool.invokeAll(jobs).map { it.get() }
        } finally {
            pool.shutdown()
        }
        return mapOf("folders" to counted, "songs" to songs)
    }

    private fun countSongs(tree: Uri, dir: Uri, shown: String): Int {
        val columns = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
        return try {
            childrenOf(tree, dir, columns, shown).use {
                var n = 0
                while (it.moveToNext()) {
                    val mime = it.getString(1) ?: ""
                    if (mime != DocumentsContract.Document.MIME_TYPE_DIR && isAudio(it.getString(0) ?: "", mime)) n++
                }
                n
            }
        } catch (e: Exception) {
            0
        }
    }

    private fun displayName(doc: Uri): String? = try {
        contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }

    /// Crea una carpeta de verdad dentro de otra (la raíz elegida si `parentUri` viene vacío). Si ya hay una con ese nombre, Android le
    /// pone «(1)».
    private fun createFolder(treeUri: String, parentUri: String, name: String, result: MethodChannel.Result) {
        inThread(result, "create_failed", "No se pudo crear la carpeta.") {
            val tree = Uri.parse(treeUri)
            val shown = folderName(tree)
            val created = try {
                DocumentsContract.createDocument(contentResolver, docUri(tree, parentUri), DocumentsContract.Document.MIME_TYPE_DIR, name)
            } catch (e: SecurityException) {
                throw FolderLostException("Android ya no deja escribir en «$shown»: elige la carpeta otra vez.")
            } catch (e: IllegalArgumentException) {
                throw FolderLostException("La carpeta «$shown» ya no existe: elige otra.")
            } catch (e: java.io.FileNotFoundException) {
                throw FolderLostException("La carpeta «$shown» ya no existe: elige otra.")
            }
            val folder = created ?: throw IOException("Android no dejó crear la carpeta «$name».")
            mapOf("uri" to folder.toString(), "name" to (displayName(folder) ?: name), "count" to 0)
        }
    }

    /// Mueve canciones de una carpeta a otra, en el almacenamiento (siguen ahí aunque se borre la app). Primero intenta el movimiento
    /// nativo de Android; si esa carpeta no lo permite (o ya hay una con ese nombre), copia el archivo y SOLO si la copia quedó completa
    /// borra el original. Devuelve `{moved: n, failed: {uri: motivo}}`.
    private fun moveSongs(treeUri: String, uris: List<String>, fromUri: String, toUri: String, result: MethodChannel.Result) {
        inThread(result, "move_failed", "No se pudo mover.") {
            val tree = Uri.parse(treeUri)
            val from = docUri(tree, fromUri)
            val to = docUri(tree, toUri)
            var moved = 0
            val failed = HashMap<String, String>()
            for (text in uris) {
                try {
                    moveOne(Uri.parse(text), from, to)
                    moved++
                } catch (e: Exception) {
                    failed[text] = e.message ?: "No se pudo mover."
                }
            }
            mapOf("moved" to moved, "failed" to failed)
        }
    }

    private fun moveOne(source: Uri, from: Uri, to: Uri) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                if (DocumentsContract.moveDocument(contentResolver, source, from, to) != null) return
            } catch (_: Exception) {
                // esta carpeta no deja moverlo (o el nombre ya existe): se copia
            }
        }
        copyThenDelete(source, to)
    }

    private fun copyThenDelete(source: Uri, to: Uri) {
        var name = "canción.mp3"
        var mime = "audio/mpeg"
        var size = -1L
        contentResolver.query(
            source,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE),
            null, null, null,
        )?.use {
            if (it.moveToFirst()) {
                it.getString(0)?.let { n -> name = n }
                it.getString(1)?.let { m -> mime = m }
                size = if (it.isNull(2)) -1L else it.getLong(2)
            }
        }
        val target = DocumentsContract.createDocument(contentResolver, to, mime, name) ?: throw IOException("No se pudo crear el archivo en la carpeta de destino.")
        try {
            val input = contentResolver.openInputStream(source) ?: throw IOException("No se pudo abrir el archivo.")
            val output = contentResolver.openOutputStream(target) ?: run {
                input.close()
                throw IOException("No se pudo escribir en la carpeta de destino.")
            }
            var copied = 0L
            input.use { i -> output.use { o -> copied = i.copyTo(o) } }
            if (size >= 0 && copied != size) throw IOException("La copia quedó incompleta.")
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(contentResolver, target) // no dejar una copia a medias
            } catch (_: Exception) {
            }
            throw e
        }
        // la copia está completa: recién ahora se borra el original
        if (!DocumentsContract.deleteDocument(contentResolver, source)) throw IOException("Se copió, pero no se pudo borrar el original.")
    }

    /// Lo que dura cada archivo: `{uri: milisegundos}`. Lee los metadatos del .mp3 en un hilo aparte; los archivos que no se
    /// puedan leer se saltan (la lista sigue sin su duración).
    private fun readDurations(uris: List<String>, result: MethodChannel.Result) {
        Thread {
            val found = HashMap<String, Long>()
            for (text in uris) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(this, Uri.parse(text))
                    val millis = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                    if (millis != null && millis > 0) found[text] = millis
                } catch (_: Exception) {
                } finally {
                    try {
                        retriever.release()
                    } catch (_: Exception) {
                    }
                }
            }
            runOnUiThread { result.success(found) }
        }.start()
    }

    /// La carátula incrustada de cada .mp3, reducida a ~96 px y guardada en la caché de la app: `{uri: ruta}`. Lo ya leído se
    /// reutiliza (y los que no traen carátula quedan marcados para no volver a abrirlos).
    private fun readArt(uris: List<String>, result: MethodChannel.Result) {
        Thread {
            val dir = File(cacheDir, "art").apply { mkdirs() }
            val found = HashMap<String, String>()
            for (text in uris) {
                val name = hashName(text)
                val image = File(dir, "$name-1200.jpg")
                File(dir, "$name-600.jpg").delete() // la versión pequeña de antes
                val none = File(dir, "$name.none")
                if (image.exists()) {
                    found[text] = image.absolutePath
                    continue
                }
                if (none.exists()) continue
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(this, Uri.parse(text))
                    val bytes = retriever.embeddedPicture
                    val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                    if (bitmap == null) {
                        none.createNewFile()
                    } else {
                        // es el fondo del reproductor: tal cual si cabe (sin perder calidad), y solo si es enorme se reduce a 1200 px
                        val scale = 1200f / maxOf(bitmap.width, bitmap.height)
                        if (scale >= 1f) {
                            image.writeBytes(bytes)
                        } else {
                            val small = Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true)
                            image.outputStream().use { small.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                        }
                        found[text] = image.absolutePath
                    }
                } catch (_: Exception) {
                } finally {
                    try {
                        retriever.release()
                    } catch (_: Exception) {
                    }
                }
            }
            runOnUiThread { result.success(found) }
        }.start()
    }

    private fun hashName(text: String) =
        java.security.MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    // ---------- cambiar la carátula de una canción ----------

    /// La imagen elegida lista para usarse de carátula: JPEG, derecha (las fotos guardan su giro aparte) y de 1200 px como mucho.
    private fun prepareCover(path: String): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        if (longest <= 0) throw IOException("No se pudo abrir esa imagen.")
        var sample = 1
        while (longest / (sample * 2) >= COVER_SIDE) sample *= 2
        val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IOException("No se pudo abrir esa imagen.")
        val degrees = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        val scale = minOf(1f, COVER_SIDE.toFloat() / maxOf(decoded.width, decoded.height))
        val matrix = Matrix().apply {
            postScale(scale, scale)
            postRotate(degrees)
        }
        val ready = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        return ByteArrayOutputStream().also { ready.compress(Bitmap.CompressFormat.JPEG, 88, it) }.toByteArray()
    }

    /// Guarda una imagen con un nombre nuevo cada vez (quien la enseña la reconoce por su ruta: con la misma ruta seguiría viendo la de
    /// antes) y borra la anterior de esa canción. Con `keep`, donde Android no la borra por su cuenta.
    private fun storeCover(key: String, bytes: ByteArray, keep: Boolean): String {
        val dir = File(if (keep) filesDir else cacheDir, "covers").apply { mkdirs() }
        val name = hashName(key)
        dir.listFiles { file -> file.name.startsWith("$name-") }?.forEach { it.delete() }
        val file = File(dir, "$name-${System.currentTimeMillis()}.jpg")
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun readSong(text: String): ByteArray = try {
        contentResolver.openInputStream(Uri.parse(text))?.use { it.readBytes() } ?: throw IOException("No se pudo abrir la canción.")
    } catch (e: SecurityException) {
        throw FolderLostException("Android ya no deja leer esa canción: elige la carpeta otra vez.")
    }

    /// Reescribe el archivo de la canción. Si algo sale mal, o lo escrito no es exactamente lo que se pidió, deja el contenido de antes.
    private fun writeSong(text: String, bytes: ByteArray) {
        val uri = Uri.parse(text)
        val backup = File.createTempFile("cancion", ".bak", cacheDir)
        try {
            backup.writeBytes(readSong(text))
            try {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: throw IOException("No se pudo abrir la canción para escribir.")
                if (!readSong(text).contentEquals(bytes)) throw IOException("La canción no quedó bien escrita.")
            } catch (e: SecurityException) {
                throw FolderLostException("Android ya no deja escribir en esa canción: elige la carpeta otra vez.")
            } catch (e: Exception) {
                contentResolver.openOutputStream(uri, "wt")?.use { out -> backup.inputStream().use { it.copyTo(out) } }
                throw e
            }
            // lo que se había leído de este archivo ya no vale
            val art = File(cacheDir, "art")
            val name = hashName(text)
            File(art, "$name-1200.jpg").delete()
            File(art, "$name.none").delete()
        } finally {
            backup.delete()
        }
    }

    /// Crea el archivo dentro de la carpeta elegida. Si ya hay uno con ese nombre, Android le pone «(1)».
    private fun saveInTree(name: String, bytes: ByteArray, tree: Uri): String {
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val shown = folderName(tree)
        val created = try {
            DocumentsContract.createDocument(contentResolver, parent, "audio/mpeg", name)
        } catch (e: SecurityException) {
            throw FolderLostException("Android ya no deja escribir en «$shown»: elige la carpeta otra vez.")
        } catch (e: IllegalArgumentException) {
            throw FolderLostException("La carpeta «$shown» ya no existe: elige otra.")
        } catch (e: java.io.FileNotFoundException) {
            throw FolderLostException("La carpeta «$shown» ya no existe: elige otra.")
        }
        val file = created ?: throw FolderLostException("No se pudo crear el archivo en «$shown»: elige la carpeta otra vez.")
        try {
            contentResolver.openOutputStream(file)?.use { it.write(bytes) } ?: throw IOException("No se pudo abrir el archivo en «$shown»")
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(contentResolver, file) // no dejar un archivo a medias
            } catch (_: Exception) {
            }
            throw e
        }
        return shown
    }

    // ---------- Música o Descargas (sin carpeta elegida) ----------

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

    private companion object {
        const val PICK_FOLDER = 4711
        const val ASK_AUDIO = 4712
        const val MAX_SONGS = 3000
        const val COVER_SIDE = 1200
    }
}
