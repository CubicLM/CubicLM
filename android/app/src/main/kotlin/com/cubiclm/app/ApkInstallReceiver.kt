package com.cubiclm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.widget.Toast

/// Receives PackageInstaller session status for APKs installed through
/// the `com.cubiclm.app/apkinstaller` channel (see MainActivity).
///
/// - PENDING_USER_ACTION: forwards the system confirmation dialog.
/// - SUCCESS: auto-launches the installed app when possible.
/// - Anything else: toasts the system-provided reason.
class ApkInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_INSTALL_STATUS) return
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                try {
                    val confirm =
                        intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (confirm != null) context.startActivity(confirm)
                } catch (_: Exception) {
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                try {
                    val packageName =
                        intent.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME)
                    if (!packageName.isNullOrBlank()) {
                        val launch = context.packageManager
                            .getLaunchIntentForPackage(packageName)
                        launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        if (launch != null) context.startActivity(launch)
                    }
                } catch (_: Exception) {
                }
            }
            else -> {
                val msg =
                    intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                try {
                    Toast.makeText(
                        context,
                        msg ?: "Install failed",
                        Toast.LENGTH_LONG,
                    ).show()
                } catch (_: Exception) {
                }
            }
        }
    }

    companion object {
        const val ACTION_INSTALL_STATUS = "com.cubiclm.app.APK_INSTALL_STATUS"
    }
}
