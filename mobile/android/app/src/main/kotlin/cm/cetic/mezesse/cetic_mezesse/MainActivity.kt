package cm.cetic.mezesse.cetic_mezesse

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal « cetic/installation » : installe la nouvelle APK téléchargée par l'application
 * (lib/mise_a_jour.dart), voir Installation. Planifie aussi la vérification en arrière-plan
 * (VerificationMiseAJour), qui fonctionne application fermée.
 */
class MainActivity : FlutterActivity() {
    companion object {
        /** Lu par la tâche de fond : application à l'écran, elle n'installe pas (l'utilisateur travaille). */
        @Volatile
        var auPremierPlan = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        VerificationMiseAJour.planifier(this)
        creerCanalNotifications()
    }

    /** Canal des notifications push (Android 8 et plus) : priorité haute, pour qu'elles s'affichent en bandeau. */
    private fun creerCanalNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel("cetic_notifications", "Notifications CETIC", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Saisie des notes, décisions et rappels de l'établissement"
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(canal)
    }

    override fun onResume() {
        super.onResume()
        auPremierPlan = true
    }

    override fun onPause() {
        auPremierPlan = false
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cetic/installation").setMethodCallHandler { appel, resultat ->
            when (appel.method) {
                "installer" -> {
                    try {
                        Installation.lancer(this, File(appel.argument<String>("chemin")!!))
                        resultat.success(true)
                    } catch (e: Exception) {
                        resultat.error("installation", e.message ?: e.toString(), null)
                    }
                }
                // Ce que l'application signale à la console technique (lib/signalement.dart).
                "identite" -> resultat.success(
                    mapOf(
                        "installationId" to Telemetrie.installationId(this),
                        "modele" to Build.MODEL,
                        "versionAndroid" to Build.VERSION.RELEASE,
                    ),
                )
                else -> resultat.notImplemented()
            }
        }
    }
}
