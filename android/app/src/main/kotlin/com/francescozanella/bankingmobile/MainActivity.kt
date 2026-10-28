package com.francescozanella.bankingmobile

import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: richiesta da local_auth per la finestra biometrica.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Niente screenshot, registrazioni dello schermo né anteprima nelle app recenti.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
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
