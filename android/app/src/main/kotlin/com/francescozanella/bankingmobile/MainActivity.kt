package com.francescozanella.bankingmobile

import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity: richiesta da local_auth per la finestra biometrica.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Niente screenshot, registrazioni dello schermo né anteprima nelle app recenti.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        clearTemporaryCopies()
    }

    /**
     * Copie temporanee lasciate dai plugin nella cache dell'app: il .pem scelto
     * nel selettore (file_picker) e il CSV condiviso (share_plus). Il .pem vive
     * solo nel Keystore, il CSV solo nell'app che lo ha ricevuto.
     */
    private fun clearTemporaryCopies() {
        for (name in listOf("file_picker", "share_plus")) File(cacheDir, name).deleteRecursively()
    }

    /** Indizi di un telefono con root: solo per un avviso, l'app non si blocca. */
    private fun isRooted(): Boolean {
        val paths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/app/Superuser.apk",
            "/data/local/su", "/data/local/bin/su", "/data/local/xbin/su", "/su/bin/su",
            "/data/adb/magisk", "/system/bin/magisk",
        )
        return Build.TAGS?.contains("test-keys") == true || paths.any { File(it).exists() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bankingmobile/custom_tabs")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") return@setMethodCallHandler result.notImplemented()
                val url = call.argument<String>("url")
                if (url == null || !url.startsWith("https://")) return@setMethodCallHandler result.success(null)
                result.success(openBankPage(Uri.parse(url)))
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bankingmobile/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isRooted") result.success(isRooted()) else result.notImplemented()
            }
    }

    /**
     * Login con la banca in una Custom Tab effimera (come l'incognito): niente
     * cookie, cronologia o sessioni condivise con il Chrome di tutti i giorni,
     * e tutto sparisce alla chiusura. Se il browser non la supporta, Custom Tab
     * normale. Restituisce "ephemeral", "normal" oppure null se non si apre.
     */
    private fun openBankPage(url: Uri): String? {
        val browser = CustomTabsClient.getPackageName(this, null)
        val ephemeral = browser != null && CustomTabsClient.isEphemeralBrowsingSupported(this, browser)
        val tab = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .setUrlBarHidingEnabled(false) // l'indirizzo della banca resta sempre visibile
            .setEphemeralBrowsingEnabled(ephemeral)
            .build()
        if (browser != null) tab.intent.setPackage(browser)
        return try {
            tab.launchUrl(this, url)
            if (ephemeral) "ephemeral" else "normal"
        } catch (e: Exception) {
            null
        }
    }
}
