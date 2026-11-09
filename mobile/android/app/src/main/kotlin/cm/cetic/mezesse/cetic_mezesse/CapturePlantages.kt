package cm.cetic.mezesse.cetic_mezesse

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.util.Log

/**
 * Capture les plantages natifs, y compris ceux du tout début du lancement : un ContentProvider démarre
 * avant l'application, et son initOrder élevé le place avant ceux des bibliothèques (AndroidManifest).
 * La version 1.1.3 s'est fermée à ce moment-là, avant le moindre écran.
 *
 * Rien ici ne doit pouvoir faire planter l'application : toute erreur est absorbée.
 */
class CapturePlantages : ContentProvider() {
    override fun onCreate(): Boolean {
        val contexte = context ?: return true
        try {
            if (Telemetrie.developpement(contexte)) return true
            val precedent = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { fil, erreur ->
                try {
                    Telemetrie.capturer(contexte, erreur)
                } catch (e: Throwable) {
                    Log.w("CETIC", "Plantage non capturé : ${e.message}")
                }
                precedent?.uncaughtException(fil, erreur)
            }
            Thread {
                try {
                    Telemetrie.renvoyerEnAttente(contexte)
                } catch (e: Throwable) {
                    Log.w("CETIC", "Rapports en attente non envoyés : ${e.message}")
                }
            }.start()
        } catch (e: Throwable) {
            Log.w("CETIC", "Capture des plantages inactive : ${e.message}")
        }
        return true
    }

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0
}
