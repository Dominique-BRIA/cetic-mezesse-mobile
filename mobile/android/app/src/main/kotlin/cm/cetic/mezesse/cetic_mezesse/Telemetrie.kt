package cm.cetic.mezesse.cetic_mezesse

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * Identité de l'installation et rapports de plantage pour la console technique. Un rapport est écrit
 * sur le téléphone avant d'être envoyé : s'il n'a pas pu partir, il repart au lancement suivant.
 */
object Telemetrie {
    /** Même adresse que lib/api.dart (Api.base) dans les APK publiées. */
    const val API = "https://cetic-mezesse-api-dgfxfucegjg8gscb.francecentral-01.azurewebsites.net/api"

    private const val PREFERENCES = "cetic_console"
    private const val CLE_INSTALLATION = "installationId"
    private const val EN_ATTENTE_MAX = 10
    private const val DELAI_ENVOI_MS = 2_500L

    fun developpement(contexte: Context): Boolean =
        (contexte.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /** Tiré au sort une fois, gardé tant que l'application reste installée. */
    @Synchronized
    fun installationId(contexte: Context): String {
        val preferences = contexte.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        preferences.getString(CLE_INSTALLATION, null)?.let { return it }
        val id = UUID.randomUUID().toString()
        preferences.edit().putString(CLE_INSTALLATION, id).commit()
        return id
    }

    private fun dossier(contexte: Context) = File(contexte.filesDir, "plantages")

    /** Appelée au moment du plantage : écrit le rapport, puis laisse un court délai à l'envoi. */
    fun capturer(contexte: Context, erreur: Throwable) {
        val paquet = contexte.packageManager.getPackageInfo(contexte.packageName, 0)
        val numero = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            paquet.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            paquet.versionCode.toLong()
        }
        val rapport = JSONObject()
            .put("installationId", installationId(contexte))
            .put("type", "NATIF")
            .put("message", erreur.toString())
            .put("pile", Log.getStackTraceString(erreur))
            .put("numeroVersion", numero)
            .put("nomVersion", paquet.versionName ?: "$numero")
            .put("modele", Build.MODEL)
            .put("versionAndroid", Build.VERSION.RELEASE)
        val rangement = dossier(contexte).apply { mkdirs() }
        val fichier = File(rangement, "${System.currentTimeMillis()}.json")
        fichier.writeText(rapport.toString())
        val envoi = Thread { envoyerFichier(fichier) }
        envoi.start()
        envoi.join(DELAI_ENVOI_MS)
    }

    /** Au lancement, en tâche séparée : les rapports restés sur le téléphone. */
    fun renvoyerEnAttente(contexte: Context) {
        val fichiers = dossier(contexte).listFiles()?.sortedByDescending { it.name } ?: return
        fichiers.drop(EN_ATTENTE_MAX).forEach { it.delete() }
        fichiers.take(EN_ATTENTE_MAX).forEach { envoyerFichier(it) }
    }

    /** Un rapport refusé par le serveur (4xx) ne repartira pas mieux : il est retiré aussi. */
    private fun envoyerFichier(fichier: File) {
        try {
            val connexion = URL("$API/appareils/plantages").openConnection() as HttpURLConnection
            try {
                connexion.requestMethod = "POST"
                connexion.connectTimeout = 2_000
                connexion.readTimeout = 2_000
                connexion.doOutput = true
                connexion.setRequestProperty("Content-Type", "application/json")
                connexion.outputStream.use { it.write(fichier.readBytes()) }
                if (connexion.responseCode in 200..499) fichier.delete()
            } finally {
                connexion.disconnect()
            }
        } catch (e: Exception) {
            Log.w("CETIC", "Rapport de plantage non envoyé : ${e.message}")
        }
    }
}
