package cm.cetic.mezesse.cetic_mezesse

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal « cetic/installation » : installe la nouvelle APK téléchargée par l'application
 * (lib/mise_a_jour.dart) avec le PackageInstaller d'Android.
 *
 * Sur Android 12 et plus, l'application qui se met à jour elle-même peut le faire sans demander
 * de confirmation (USER_ACTION_NOT_REQUIRED). Si Android exige quand même une confirmation, ou sur
 * une version plus ancienne, ResultatInstallation affiche l'écran « Mettre à jour » d'Android.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cetic/installation").setMethodCallHandler { appel, resultat ->
            when (appel.method) {
                "installer" -> {
                    try {
                        installer(File(appel.argument<String>("chemin")!!))
                        resultat.success(true)
                    } catch (e: Exception) {
                        resultat.error("installation", e.message ?: e.toString(), null)
                    }
                }
                else -> resultat.notImplemented()
            }
        }
    }

    private fun installer(apk: File) {
        val installeur = packageManager.packageInstaller
        val reglages = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val id = installeur.createSession(reglages)
        installeur.openSession(id).use { session ->
            apk.inputStream().use { entree ->
                session.openWrite("cetic-mezesse.apk", 0, apk.length()).use { sortie ->
                    entree.copyTo(sortie)
                    session.fsync(sortie)
                }
            }
            // Android complète cette intention avec le résultat : elle doit rester modifiable.
            val drapeaux = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val retour = PendingIntent.getBroadcast(this, id, Intent(this, ResultatInstallation::class.java), drapeaux)
            session.commit(retour.intentSender)
        }
    }
}
