package com.kyora.kyora_chat

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.speech.tts.TextToSpeech
import java.util.Locale

// La voz de KyraAdmin: con la PANTALLA APAGADA lee en voz alta las notificaciones de las apps elegidas en Configuración → Voz
// («Mensaje de WhatsApp. Ana dice: ya llegué»; en el chat de Kyra, «Ana te escribió: …»). Al encender la pantalla se calla.
// Android mantiene vivo este servicio mientras tenga el «acceso a notificaciones» (lo concede la persona en los ajustes del teléfono).
// La configuración (encendida y qué apps) la escribe la app con el canal `kyora/voice` en las preferencias `kyra_voice`.
class KyraNotificationListener : NotificationListenerService(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var screenOff = false
    private var receiverOn = false

    /// Lo que ya se dijo hace poco (para no repetir la misma notificación cuando la app la actualiza).
    private val recent = LinkedHashMap<String, Long>()

    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> screenOff = true
                Intent.ACTION_SCREEN_ON -> {
                    screenOff = false
                    tts?.stop() // al encender la pantalla se calla
                }
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOff = !power.isInteractive
        if (!receiverOn) {
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF).apply { addAction(Intent.ACTION_SCREEN_ON) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screen, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(screen, filter)
            }
            receiverOn = true
        }
        if (tts == null) tts = TextToSpeech(this, this)
    }

    override fun onListenerDisconnected() {
        release()
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }

    private fun release() {
        if (receiverOn) {
            try {
                unregisterReceiver(screen)
            } catch (e: Exception) {
                // ya no estaba
            }
            receiverOn = false
        }
        tts?.shutdown()
        tts = null
        ready = false
    }

    override fun onInit(status: Int) {
        val engine = tts ?: return
        ready = status == TextToSpeech.SUCCESS
        if (!ready) return
        val mx = engine.setLanguage(Locale("es", "MX"))
        if (mx == TextToSpeech.LANG_MISSING_DATA || mx == TextToSpeech.LANG_NOT_SUPPORTED) engine.setLanguage(Locale("es"))
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!screenOff && power.isInteractive) return // solo con la pantalla apagada
        val packages = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
        val pkg = sbn.packageName
        val kyraChat = pkg.startsWith(KYRA_PREFIX)
        if (pkg !in packages && !(kyraChat && KYRA_CHAT in packages)) return
        val n = sbn.notification
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0 || n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        // de Kyra solo los mensajes del chat (no los recordatorios ni la música)
        if (kyraChat && n.channelId != KYRA_CHAT_CHANNEL) return
        val extras = n.extras
        var title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
        var text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
        // apps de mensajería (WhatsApp, Telegram…): el último mensaje con quién lo manda
        @Suppress("DEPRECATION")
        val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        val last = messages?.lastOrNull() as? Bundle
        if (last != null) {
            last.getCharSequence("text")?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { text = it }
            last.getCharSequence("sender")?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { title = it }
        }
        val body = text
        if (body.isNullOrEmpty()) return
        val key = "$pkg|$title|$body"
        val now = System.currentTimeMillis()
        recent.entries.removeAll { now - it.value > 120_000 }
        if (recent.containsKey(key)) return
        recent[key] = now
        val phrase = if (kyraChat) {
            "${title ?: "Alguien"} te escribió: $body"
        } else {
            val app = appLabel(pkg)
            if (title.isNullOrEmpty()) "Mensaje de $app. $body" else "Mensaje de $app. $title dice: $body"
        }
        speak(phrase, sbn.key)
    }

    private fun speak(phrase: String, id: String) {
        val engine = tts ?: return
        if (!ready) return
        engine.speak(phrase, TextToSpeech.QUEUE_ADD, null, id)
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, PackageManager.GET_META_DATA)).toString()
    } catch (e: Exception) {
        pkg
    }

    companion object {
        const val PREFS = "kyra_voice"
        const val KEY_ENABLED = "enabled"
        const val KEY_PACKAGES = "packages"

        /// La opción fija «Chat de Kyra» (vale para KyraAdmin y KyraFamily) y el canal de sus avisos de mensajes.
        const val KYRA_CHAT = "kyra.chat"
        const val KYRA_PREFIX = "com.kyora.kyora_chat"
        const val KYRA_CHAT_CHANNEL = "com.kyora.kyora_chat.dm"
    }
}
