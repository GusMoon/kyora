package com.kyora.kyora_chat

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.ActivityOptions
import android.bluetooth.BluetoothManager
import android.os.BatteryManager
import android.os.StatFs
import android.app.role.RoleManager
import android.content.ComponentName
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
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.speech.tts.TextToSpeech
import java.util.Locale
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

    // La respuesta pendiente del selector de archivos del Vault («Exportar») y a qué carpeta van a ir.
    private var pendingImport: MethodChannel.Result? = null
    private var importTree: String = ""
    private var importDir: String = ""
    private var importMove: Boolean = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureAudioLevels(flutterEngine)
        configureBackground(flutterEngine)
        configureApps(flutterEngine)
        configureSystem(flutterEngine)
        configureVoice(flutterEngine)
        configureContacts(flutterEngine)
        configureVault(flutterEngine)
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
                "deleteSongs" -> deleteSongs(call.argument<List<String>>("uris") ?: emptyList(), result)
                "renameEntry" -> renameEntry(call.argument<String>("uri") ?: "", call.argument<String>("name") ?: "", result)
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

    // ---------- la voz de KyraAdmin (lee notificaciones con la pantalla apagada; ver KyraNotificationListener) ----------

    private var testVoice: TextToSpeech? = null

    private fun configureVoice(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/voice").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(KyraNotificationListener.PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                // ¿La persona ya le dio a Kyra el «acceso a notificaciones»?
                "isAccessGranted" -> {
                    val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                    val me = ComponentName(this, KyraNotificationListener::class.java).flattenToString()
                    result.success(enabled.split(":").any { it == me })
                }
                "openAccessSettings" -> result.success(openPanel(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                "getConfig" -> result.success(
                    mapOf(
                        "enabled" to prefs.getBoolean(KyraNotificationListener.KEY_ENABLED, false),
                        "packages" to (prefs.getStringSet(KyraNotificationListener.KEY_PACKAGES, emptySet()) ?: emptySet()).toList(),
                    ),
                )
                "setConfig" -> {
                    prefs.edit()
                        .putBoolean(KyraNotificationListener.KEY_ENABLED, call.argument<Boolean>("enabled") ?: false)
                        .putStringSet(KyraNotificationListener.KEY_PACKAGES, (call.argument<List<String>>("packages") ?: emptyList()).toSet())
                        .apply()
                    result.success(true)
                }
                // «Probar voz»: dice una frase de ejemplo ya mismo (sin esperar a que se apague la pantalla).
                "testSpeak" -> {
                    val phrase = call.argument<String>("text") ?: "Mensaje de WhatsApp. Ana dice: ya llegué."
                    testVoice?.shutdown()
                    var engine: TextToSpeech? = null
                    engine = TextToSpeech(this) { status ->
                        val tts = engine ?: return@TextToSpeech
                        if (status == TextToSpeech.SUCCESS) {
                            tts.setLanguage(Locale("es", "MX"))
                            tts.speak(phrase, TextToSpeech.QUEUE_FLUSH, null, "kyra-test")
                        }
                    }
                    testVoice = engine
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- las apps instaladas (el disco de Inicio) ----------

    // El estado del teléfono para Inicio: batería, memoria, almacenamiento, Wi-Fi y Bluetooth; y los paneles del sistema para cambiarlos
    // (desde Android 10 una app no puede encender el Wi-Fi ni el Bluetooth por su cuenta: se abre el panel del sistema).
    private fun configureSystem(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "stats" -> try {
                    result.success(systemStats())
                } catch (e: Exception) {
                    result.error("stats_failed", "No se pudo leer el estado del teléfono.", e.message)
                }
                // El panel flotante con los interruptores del Wi-Fi y de los datos (Android 10+); antes, los ajustes del Wi-Fi.
                "openWifi", "openInternetPanel" -> result.success(openPanel(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_WIFI_SETTINGS))
                "openNetworkSettings" -> result.success(openPanel(Settings.ACTION_WIRELESS_SETTINGS))
                "openMobileData" -> result.success(openPanel(Settings.ACTION_DATA_ROAMING_SETTINGS) || openPanel(Settings.ACTION_NETWORK_OPERATOR_SETTINGS))
                "openBluetooth" -> result.success(openPanel(Settings.ACTION_BLUETOOTH_SETTINGS))
                else -> result.notImplemented()
            }
        }
    }

    private fun systemStats(): Map<String, Any?> {
        val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val memory = ActivityManager.MemoryInfo()
        (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val disk = StatFs(Environment.getDataDirectory().path)
        val wifi = try {
            (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).isWifiEnabled
        } catch (e: Exception) {
            null
        }
        val bluetooth = try {
            (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter?.isEnabled
        } catch (e: Exception) {
            null
        }
        // Los datos móviles: hay una red celular con salida a internet (aunque ahora se use el Wi-Fi). Es «en uso», no el interruptor.
        val mobileData = try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            @Suppress("DEPRECATION")
            cm.allNetworks.any { network ->
                val caps = cm.getNetworkCapabilities(network)
                caps != null && caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) &&
                    caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
            }
        } catch (e: Exception) {
            null
        }
        return mapOf(
            "battery" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
            "charging" to battery.isCharging,
            "ramTotal" to memory.totalMem,
            "ramFree" to memory.availMem,
            "storageTotal" to disk.totalBytes,
            "storageFree" to disk.availableBytes,
            "wifi" to wifi,
            "bluetooth" to bluetooth,
            "mobileData" to mobileData,
        )
    }

    private fun openPanel(action: String): Boolean = try {
        startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    private fun configureApps(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/apps").setMethodCallHandler { call, result ->
            when (call.method) {
                // Las apps que se pueden abrir: `[{package, label, icon (PNG)}]`, por nombre y sin la propia Kyra.
                "listApps" -> inThread(result, "apps_failed", "No se pudieron leer las apps.") { listLaunchableApps() }
                // ¿Kyra es la pantalla de inicio del teléfono?
                "isDefaultLauncher" -> result.success(isDefaultHome())
                // Pide a Android que Kyra sea la pantalla de inicio: el aviso directo (Android 10 o más) o, si no, la lista de apps de inicio.
                "chooseLauncher" -> result.success(chooseLauncher())
                // Enciende o apaga que Kyra se ofrezca como pantalla de inicio (solo el administrador la ofrece).
                "setLauncherEnabled" -> result.success(setLauncherEnabled(call.argument<Boolean>("enabled") ?: false))
                "launch" -> try {
                    val pkg = call.argument<String>("package") ?: ""
                    val intent = packageManager.getLaunchIntentForPackage(pkg)
                    if (intent == null) {
                        result.success(false)
                    } else {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        // la app entra subiendo desde abajo (prueba de la transición; `kyra_enter_bottom` está en res/anim)
                        val options = ActivityOptions.makeCustomAnimation(this, R.anim.kyra_enter_bottom, R.anim.kyra_hold)
                        startActivity(intent, options.toBundle())
                        // Android 14+ prefiere esta vía (la anterior está en desuso): se pide justo después de lanzar
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, R.anim.kyra_enter_bottom, R.anim.kyra_hold)
                        }
                        result.success(true)
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isDefaultHome(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val info = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return info?.activityInfo?.packageName == packageName
    }

    // El filtro «pantalla de inicio» está en el alias HomeAlias del manifiesto (apagado de fábrica): aquí se enciende o se apaga sin
    // reiniciar la app. Apagado, Android no ofrece a Kyra como launcher (y si lo era, vuelve a su launcher anterior).
    private fun setLauncherEnabled(enabled: Boolean): Boolean = try {
        packageManager.setComponentEnabledSetting(
            ComponentName(this, "com.kyora.kyora_chat.HomeAlias"),
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        true
    } catch (e: Exception) {
        false
    }

    private fun chooseLauncher(): Boolean {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roles = getSystemService(RoleManager::class.java)
                if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_HOME) && !roles.isRoleHeld(RoleManager.ROLE_HOME)) {
                    startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_HOME), REQUEST_HOME_ROLE)
                    return true
                }
            }
        } catch (e: Exception) {
            // se prueba con la lista de apps de inicio
        }
        for (action in listOf(Settings.ACTION_HOME_SETTINGS, Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)) {
            try {
                startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) {
                // siguiente
            }
        }
        return false
    }

    private fun listLaunchableApps(): List<Map<String, Any>> {
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val found = packageManager.queryIntentActivities(query, 0)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any>>()
        for (info in found) {
            val pkg = info.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val icon = try {
                iconBytes(info.loadIcon(packageManager))
            } catch (e: Exception) {
                continue
            }
            apps.add(mapOf("package" to pkg, "label" to info.loadLabel(packageManager).toString(), "icon" to icon))
        }
        apps.sortBy { (it["label"] as String).lowercase() }
        return apps
    }

    /// El icono de una app como PNG de 96 px (los iconos adaptables son vectores: se dibujan sobre un lienzo).
    private fun iconBytes(drawable: android.graphics.drawable.Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
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
        if (requestCode == ASK_CONTACTS) {
            val asked = pendingContacts ?: return
            pendingContacts = null
            asked.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            return
        }
        if (requestCode != ASK_AUDIO) return
        val result = pendingLevels ?: return
        pendingLevels = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && startVisualizer())
    }

    /// Escucha la salida de audio (sesión 0: el reproductor en segundo plano no da la suya) y manda `[fuerza, bajos, ...onda]`: la fuerza del
    /// sonido de 0 a 1, la de los bajos sin normalizar y la forma de la onda de -1 a 1 en 48 puntos.
    private fun startVisualizer(): Boolean {
        if (visualizer != null) return true
        return try {
            val created = Visualizer(0)
            val range = Visualizer.getCaptureSizeRange()
            // con 1024 muestras cada banda de la FFT mide unos 45 Hz: alcanza para separar los bajos
            created.captureSize = 1024.coerceIn(range[0], range[1])
            var bass = 0.0
            created.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(source: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                    val samples = waveform ?: return
                    if (samples.isEmpty()) return
                    val points = 48
                    val frame = DoubleArray(points + 2)
                    var sum = 0.0
                    for ((i, sample) in samples.withIndex()) {
                        val centered = ((sample.toInt() and 0xff) - 128) / 128.0
                        sum += centered * centered
                        frame[2 + i * points / samples.size] += centered
                    }
                    // cada punto de la onda es la media de sus muestras
                    val perPoint = maxOf(samples.size.toDouble() / points, 1.0)
                    for (i in 2 until frame.size) frame[i] /= perPoint
                    frame[0] = Math.sqrt(sum / samples.size)
                    frame[1] = bass
                    runOnUiThread { levelSink?.success(frame) }
                }

                override fun onFftDataCapture(source: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    val data = fft ?: return
                    if (data.size < 4) return
                    // `samplingRate` viene en milihercios; la banda k mide k * muestreo / tamaño. Los pares de bytes (2k, 2k+1) son su parte real e imaginaria
                    val hzPerBand = samplingRate / 1000.0 / data.size
                    val last = (data.size / 2) - 1
                    val from = Math.ceil(45.0 / hzPerBand).toInt().coerceIn(1, last)
                    val to = Math.floor(190.0 / hzPerBand).toInt().coerceIn(from, last)
                    var total = 0.0
                    for (k in from..to) {
                        val real = data[2 * k].toDouble()
                        val imaginary = data[2 * k + 1].toDouble()
                        total += Math.sqrt(real * real + imaginary * imaginary) / 128.0
                    }
                    bass = total / (to - from + 1)
                }
            }, minOf(Visualizer.getMaxCaptureRate(), 20000), true, true)
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
        testVoice?.shutdown()
        testVoice = null
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
        if (requestCode == IMPORT_FILES) {
            finishImport(resultCode, data)
            return
        }
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

    /// Borra canciones del almacenamiento (el permiso de la carpeta elegida incluye escribir). Devuelve `{deleted: n, failed: {uri: motivo}}`.
    private fun deleteSongs(uris: List<String>, result: MethodChannel.Result) {
        inThread(result, "delete_failed", "No se pudo borrar.") {
            var deleted = 0
            val failed = HashMap<String, String>()
            for (text in uris) {
                try {
                    if (DocumentsContract.deleteDocument(contentResolver, Uri.parse(text))) deleted++ else failed[text] = "Android no lo borró."
                } catch (e: Exception) {
                    failed[text] = e.message ?: "No se pudo borrar."
                }
            }
            mapOf("deleted" to deleted, "failed" to failed)
        }
    }

    /// Le cambia el nombre a una carpeta o a un archivo. Devuelve la dirección nueva (Android puede cambiarla al renombrar).
    private fun renameEntry(uri: String, name: String, result: MethodChannel.Result) {
        inThread(result, "rename_failed", "No se pudo cambiar el nombre.") {
            if (uri.isEmpty() || name.isBlank()) throw IOException("Falta el nombre.")
            val renamed = try {
                DocumentsContract.renameDocument(contentResolver, Uri.parse(uri), name)
            } catch (e: SecurityException) {
                throw FolderLostException("Android ya no deja escribir en esa carpeta: elígela otra vez.")
            } catch (e: java.io.FileNotFoundException) {
                throw FolderLostException("Eso ya no existe: vuelve a leer la carpeta.")
            }
            (renamed ?: throw IOException("Android no dejó cambiar el nombre a «$name».")).toString()
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
        copyDocument(source, to, "canción.mp3", "audio/mpeg")
        // la copia está completa: recién ahora se borra el original
        if (!DocumentsContract.deleteDocument(contentResolver, source)) throw IOException("Se copió, pero no se pudo borrar el original.")
    }

    /// Copia un documento dentro de la carpeta `to` (con su mismo nombre y tipo) y devuelve la copia. Si la copia queda a medias, la borra.
    private fun copyDocument(source: Uri, to: Uri, fallbackName: String, fallbackMime: String): Uri {
        var name = fallbackName
        var mime = fallbackMime
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
        return target
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

    // ---------- Contactos: los del teléfono, llamar y abrir el chat de WhatsApp ----------

    // La respuesta pendiente del permiso de contactos.
    private var pendingContacts: MethodChannel.Result? = null

    private fun configureContacts(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/contacts").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasContactsPermission())
                "request" -> when {
                    hasContactsPermission() -> result.success(true)
                    pendingContacts != null -> result.error("busy", "Ya se está pidiendo el permiso.", null)
                    else -> {
                        pendingContacts = result
                        requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), ASK_CONTACTS)
                    }
                }
                "list" -> inThread(result, "contacts_failed", "No se pudieron leer los contactos.") { listContacts() }
                // Se abre el marcador con el número ya escrito (sin pedir permiso de llamadas: la persona da el último toque).
                "call" -> result.success(startIntent(Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(call.argument<String>("number") ?: "")))))
                "whatsapp" -> result.success(openWhatsApp(call.argument<String>("number") ?: ""))
                else -> result.notImplemented()
            }
        }
    }

    private fun hasContactsPermission() = checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    /// Los contactos con teléfono, por nombre: `[{id, name, phones: [...]}]` (uno por persona, con todos sus números sin repetir).
    private fun listContacts(): List<Map<String, Any>> {
        if (!hasContactsPermission()) throw SecurityException("Falta el permiso de contactos.")
        val phone = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val columns = arrayOf(
            android.provider.ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        val people = LinkedHashMap<Long, HashMap<String, Any>>()
        contentResolver.query(phone, columns, null, null, "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} COLLATE NOCASE ASC")?.use {
            while (it.moveToNext()) {
                val id = it.getLong(0)
                val name = it.getString(1) ?: continue
                val number = it.getString(2)?.trim() ?: continue
                if (number.isEmpty()) continue
                val person = people.getOrPut(id) { hashMapOf("id" to id.toString(), "name" to name, "phones" to ArrayList<String>()) }
                @Suppress("UNCHECKED_CAST")
                val phones = person["phones"] as ArrayList<String>
                val digits = number.filter { c -> c.isDigit() }
                if (phones.none { p -> p.filter { c -> c.isDigit() } == digits }) phones.add(number)
            }
        }
        return people.values.toList()
    }

    private fun startIntent(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    /// Abre el chat de WhatsApp con ese número (solo cifras, con el prefijo del país). Primero WhatsApp y, si no, WhatsApp Business o el
    /// navegador.
    private fun openWhatsApp(digits: String): Boolean {
        if (digits.isEmpty()) return false
        val link = Uri.parse("https://wa.me/$digits")
        for (pack in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            if (startIntent(Intent(Intent.ACTION_VIEW, link).setPackage(pack))) return true
        }
        return startIntent(Intent(Intent.ACTION_VIEW, link))
    }

    // ---------- el Vault: ver las carpetas y los archivos de una carpeta elegida ----------

    private fun configureVault(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kyora/vault").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "list" -> inThread(result, "list_failed", "No se pudo leer la carpeta.") {
                    vaultList(Uri.parse(call.argument<String>("treeUri") ?: ""), call.argument<String>("dirUri") ?: "")
                }
                "read" -> inThread(result, "read_failed", "No se pudo leer el archivo.") { vaultRead(call.argument<String>("uri") ?: "") }
                "thumb" -> inThread(result, "thumb_failed", "No se pudo abrir esa imagen.") {
                    vaultThumb(call.argument<String>("uri") ?: "", call.argument<Int>("side") ?: 480, call.argument<String>("mime") ?: "")
                }
                "open" -> result.success(vaultOpen(call.argument<String>("uri") ?: "", call.argument<String>("mime") ?: ""))
                "import" -> vaultImport(
                    call.argument<String>("treeUri") ?: "",
                    call.argument<String>("dirUri") ?: "",
                    call.argument<Boolean>("move") ?: true,
                    result,
                )
                "rename" -> renameEntry(call.argument<String>("uri") ?: "", call.argument<String>("name") ?: "", result)
                "share" -> result.success(vaultShare(call.argument<String>("uri") ?: "", call.argument<String>("mime") ?: "", call.argument<String>("name") ?: ""))
                else -> result.notImplemented()
            }
        }
    }

    /// Lo que hay dentro de UNA carpeta (sin bajar a las subcarpetas): `[{uri, name, dir, mime, size, modified}]`, de todo tipo.
    private fun vaultList(tree: Uri, dirUri: String): List<Map<String, Any?>> {
        val shown = folderName(tree)
        val dir = docUri(tree, dirUri)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val found = ArrayList<Map<String, Any?>>()
        childrenOf(tree, dir, columns, shown).use {
            while (it.moveToNext() && found.size < MAX_VAULT) {
                val id = it.getString(0) ?: continue
                val name = it.getString(1) ?: continue
                val mime = it.getString(2) ?: ""
                found.add(
                    mapOf(
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                        "name" to name,
                        "dir" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                        "mime" to mime,
                        "size" to (if (it.isNull(3)) 0L else it.getLong(3)),
                        "modified" to (if (it.isNull(4)) 0L else it.getLong(4)),
                    )
                )
            }
        }
        return found
    }

    /// El archivo entero, tal cual (así se ve la imagen original).
    private fun vaultRead(text: String): ByteArray = try {
        contentResolver.openInputStream(Uri.parse(text))?.use { it.readBytes() } ?: throw IOException("No se pudo abrir el archivo.")
    } catch (e: SecurityException) {
        throw FolderLostException("Android ya no deja leer ese archivo: elige la carpeta otra vez.")
    }

    /// La imagen reducida (de `side` px como mucho) para la cuadrícula, derecha y sin ningún efecto. Las que pueden tener transparencia
    /// (PNG, WebP, GIF) siguen en PNG; el resto, en JPEG.
    private fun vaultThumb(text: String, side: Int, mime: String): ByteArray {
        val uri = Uri.parse(text)
        try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            val longest = maxOf(bounds.outWidth, bounds.outHeight)
            if (longest <= 0) throw IOException("No se pudo abrir esa imagen.")
            var sample = 1
            while (longest / (sample * 2) >= side) sample *= 2
            val decoded = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
                ?: throw IOException("No se pudo abrir esa imagen.")
            val degrees = try {
                contentResolver.openInputStream(uri)?.use { stream ->
                    when (ExifInterface(stream).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                        ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                        ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                        ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                        else -> 0f
                    }
                } ?: 0f
            } catch (e: Exception) {
                0f
            }
            val ready = if (degrees == 0f) decoded else Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply { postRotate(degrees) }, true)
            val alpha = mime.contains("png") || mime.contains("webp") || mime.contains("gif")
            return ByteArrayOutputStream().also {
                if (alpha) ready.compress(Bitmap.CompressFormat.PNG, 100, it) else ready.compress(Bitmap.CompressFormat.JPEG, 92, it)
            }.toByteArray()
        } catch (e: SecurityException) {
            throw FolderLostException("Android ya no deja leer esa imagen: elige la carpeta otra vez.")
        }
    }

    /// «Exportar»: abre el selector de archivos del sistema (el almacenamiento interno, la tarjeta, un USB u otras apps de archivos) para elegir
    /// varios, los copia en la carpeta `dirUri` del Vault (la raíz si viene vacía) y, con `move`, borra los originales cuando la copia quedó
    /// completa. Devuelve `{copied: n, moved: n, failed: {nombre: motivo}}`, o `null` si se cerró el selector sin elegir.
    private fun vaultImport(treeUri: String, dirUri: String, move: Boolean, result: MethodChannel.Result) {
        if (treeUri.isEmpty()) {
            result.error("no_vault", "Elige primero la carpeta del Vault en Configuración.", null)
            return
        }
        if (pendingImport != null) {
            result.error("busy", "Ya hay un selector de archivos abierto.", null)
            return
        }
        pendingImport = result
        importTree = treeUri
        importDir = dirUri
        importMove = move
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, IMPORT_FILES)
        } catch (e: Exception) {
            pendingImport = null
            result.error("no_picker", "Este teléfono no tiene selector de archivos.", null)
        }
    }

    private fun finishImport(resultCode: Int, data: Intent?) {
        val result = pendingImport ?: return
        pendingImport = null
        val picked = ArrayList<Uri>()
        data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { picked.add(it) } }
        data?.data?.let { if (picked.isEmpty()) picked.add(it) }
        if (resultCode != Activity.RESULT_OK || picked.isEmpty()) {
            result.success(null) // la persona cerró el selector sin elegir
            return
        }
        val tree = Uri.parse(importTree)
        val into = docUri(tree, importDir)
        val move = importMove
        Thread {
            var copied = 0
            var moved = 0
            val failed = HashMap<String, String>()
            for (uri in picked) {
                val shown = displayName(uri) ?: uri.lastPathSegment ?: "archivo"
                try {
                    copyDocument(uri, into, shown, "application/octet-stream")
                    copied++
                    if (move) {
                        try {
                            if (DocumentsContract.deleteDocument(contentResolver, uri)) moved++
                        } catch (_: Exception) {
                            // el almacenamiento de origen no deja borrar: queda copiado, no movido
                        }
                    }
                } catch (e: SecurityException) {
                    failed[shown] = "Android no dejó escribir en la carpeta del Vault."
                } catch (e: Exception) {
                    failed[shown] = e.message ?: "No se pudo copiar."
                }
            }
            runOnUiThread { result.success(mapOf("copied" to copied, "moved" to moved, "failed" to failed)) }
        }.start()
    }

    /// Manda el archivo a otra app (mensajes, correo, WhatsApp…) con el menú de compartir del sistema.
    private fun vaultShare(text: String, mime: String, name: String): Boolean {
        if (text.isEmpty()) return false
        val send = Intent(Intent.ACTION_SEND).apply {
            type = if (mime.isEmpty()) "*/*" else mime
            putExtra(Intent.EXTRA_STREAM, Uri.parse(text))
            if (name.isNotEmpty()) putExtra(Intent.EXTRA_TITLE, name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return startIntent(Intent.createChooser(send, name.ifEmpty { "Compartir" }).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }

    /// Abre el archivo con la app del teléfono que sepa verlo.
    private fun vaultOpen(text: String, mime: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(text), if (mime.isEmpty()) "*/*" else mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return startIntent(intent)
    }

    private companion object {
        const val PICK_FOLDER = 4711
        const val IMPORT_FILES = 4715
        const val REQUEST_HOME_ROLE = 4713
        const val ASK_AUDIO = 4712
        const val ASK_CONTACTS = 4714
        const val MAX_VAULT = 5000
        const val MAX_SONGS = 3000
        const val COVER_SIDE = 1200
    }
}
