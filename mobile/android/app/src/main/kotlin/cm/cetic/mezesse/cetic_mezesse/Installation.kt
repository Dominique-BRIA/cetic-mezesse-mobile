package cm.cetic.mezesse.cetic_mezesse

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File

/**
 * Installe une nouvelle APK de l'application avec le PackageInstaller d'Android, depuis l'écran
 * (MainActivity) ou depuis la tâche de fond (VerificationMiseAJour).
 *
 * Sur Android 12 et plus, l'application qui se met à jour elle-même peut le faire sans demander
 * de confirmation (USER_ACTION_NOT_REQUIRED). Si Android exige quand même une confirmation, ou sur
 * une version plus ancienne, ResultatInstallation affiche l'écran « Mettre à jour » d'Android.
 */
object Installation {
    fun lancer(context: Context, apk: File) {
        val installeur = context.packageManager.packageInstaller
        val reglages = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
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
            val retour = PendingIntent.getBroadcast(context, id, Intent(context, ResultatInstallation::class.java), drapeaux)
            session.commit(retour.intentSender)
        }
    }
}
