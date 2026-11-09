package cm.cetic.mezesse.cetic_mezesse

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Mises à jour en arrière-plan, application fermée : toutes les 6 heures environ, dès que le téléphone
 * a du réseau (WorkManager, y compris après un redémarrage), la tâche lit la fiche version.json de la
 * dernière Release, télécharge la nouvelle APK et l'installe si l'application n'est pas à l'écran.
 *
 * Le fichier est celui que lit l'application (cache, cetic-mezesse-<numéro>.apk) : si Android exige une
 * confirmation qu'il ne peut pas afficher en arrière-plan, l'APK est déjà prête à la prochaine ouverture
 * (lib/mise_a_jour.dart).
 */
class VerificationMiseAJour(context: Context, parametres: WorkerParameters) : Worker(context, parametres) {

    override fun doWork(): Result {
        val contexte = applicationContext
        // Version de développement : jamais de mise à jour.
        if ((contexte.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) return Result.success()
        return try {
            val fiche = JSONObject(lireTexte(ADRESSE_FICHE))
            val numero = fiche.getLong("numero")
            if (numero <= versionInstallee(contexte)) return Result.success()
            // Politique réglée depuis la console technique ; illisible, rien n'est téléchargé (nouvel essai plus tard).
            val politique = JSONObject(lireTexte("${Telemetrie.API}/mises-a-jour/politique"))
            val bloquees = politique.optJSONArray("versionsBloquees")
            val bloquee = bloquees != null && (0 until bloquees.length()).any { bloquees.optLong(it) == numero }
            if (politique.optBoolean("suspendue") || bloquee) return Result.success()
            val taille = fiche.optLong("taille", 0)
            val apk = File(contexte.cacheDir, "cetic-mezesse-$numero.apk")
            if (!(taille > 0 && apk.exists() && apk.length() == taille)) telecharger(fiche.getString("url"), apk, taille)
            Log.i(JOURNAL, "Version $numero téléchargée en arrière-plan")
            // Application ouverte : c'est elle qui installera, quand l'utilisateur la quittera.
            if (!MainActivity.auPremierPlan) Installation.lancer(contexte, apk)
            Result.success()
        } catch (e: Exception) {
            Log.w(JOURNAL, "Vérification de mise à jour impossible : ${e.message}")
            Result.retry()
        }
    }

    private fun versionInstallee(contexte: Context): Long {
        val paquet = contexte.packageManager.getPackageInfo(contexte.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            paquet.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            paquet.versionCode.toLong()
        }
    }

    private fun ouvrir(adresse: String): HttpURLConnection =
        (URL(adresse).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 60_000
            // GitHub renvoie vers son stockage : redirections suivies (https vers https).
            instanceFollowRedirects = true
        }

    private fun lireTexte(adresse: String): String {
        val connexion = ouvrir(adresse)
        try {
            if (connexion.responseCode != 200) throw IllegalStateException("fiche : ${connexion.responseCode}")
            return connexion.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connexion.disconnect()
        }
    }

    private fun telecharger(adresse: String, apk: File, taille: Long) {
        // Les APK des versions précédentes ne servent plus.
        apk.parentFile?.listFiles()?.forEach { f ->
            if (f.name.startsWith("cetic-mezesse-") && f.name.endsWith(".apk") && f.name != apk.name) f.delete()
        }
        val partiel = File(apk.parentFile, "${apk.name}.fond")
        val connexion = ouvrir(adresse)
        try {
            if (connexion.responseCode != 200) throw IllegalStateException("APK : ${connexion.responseCode}")
            connexion.inputStream.use { entree -> partiel.outputStream().use { sortie -> entree.copyTo(sortie) } }
        } finally {
            connexion.disconnect()
        }
        if (taille > 0 && partiel.length() != taille) {
            partiel.delete()
            throw IllegalStateException("APK incomplète (${partiel.length()} octets sur $taille)")
        }
        if (!partiel.renameTo(apk)) throw IllegalStateException("APK non enregistrée")
    }

    companion object {
        private const val JOURNAL = "CETIC"
        private const val TACHE = "cetic-mise-a-jour"

        /** Même adresse que lib/mise_a_jour.dart (adresseFiche). */
        private const val ADRESSE_FICHE =
            "https://github.com/Dominique-BRIA/cetic-mezesse-mobile/releases/latest/download/version.json"

        /** Planifiée à chaque ouverture ; KEEP garde la planification existante. */
        fun planifier(contexte: Context) {
            val conditions = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            val demande = PeriodicWorkRequestBuilder<VerificationMiseAJour>(6, TimeUnit.HOURS)
                .setConstraints(conditions)
                .build()
            WorkManager.getInstance(contexte).enqueueUniquePeriodicWork(TACHE, ExistingPeriodicWorkPolicy.KEEP, demande)
        }
    }
}
