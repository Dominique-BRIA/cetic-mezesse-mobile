package cm.cetic.mezesse.cetic_mezesse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log

/**
 * Résultat d'une installation lancée par MainActivity. Quand Android demande une confirmation
 * (première autorisation d'installer, ou version d'Android sans installation muette), son écran
 * « Mettre à jour » est affiché. En cas de réussite, Android remplace l'application : rien à faire.
 */
class ResultatInstallation : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val statut = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        Log.i("CETIC", "Installation de la mise à jour : statut $statut ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""}")
        if (statut != PackageInstaller.STATUS_PENDING_USER_ACTION) return
        val confirmation: Intent = (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            }
        ) ?: return
        confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(confirmation)
        } catch (e: Exception) {
            // Application en arrière-plan : Android peut refuser d'ouvrir l'écran. L'application
            // relance l'installation à son retour au premier plan.
            Log.w("CETIC", "Écran de confirmation non affiché : ${e.message}")
        }
    }
}
