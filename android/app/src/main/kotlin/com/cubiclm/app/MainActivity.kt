package com.cubiclm.app

import android.app.AlertDialog
import android.app.AlarmManager
import android.app.DownloadManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread
import kotlin.system.exitProcess
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private val importChannelName = "com.cubiclm.app/model_import"
    private val importRequestCode = 4207
    private val exportFolderRequestCode = 4208
    private val mainHandler = Handler(Looper.getMainLooper())

    private var importChannel: MethodChannel? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingExportFolderResult: MethodChannel.Result? = null
    private var pendingModelsDir: String? = null
    private var pendingSharedText: String? = null
    private val monitoredInAppDownloads = ConcurrentHashMap.newKeySet<Long>()

    /// Runtime root reported by Dart (RuntimeInstaller), e.g.
    /// <app-support>/runtime. Null until the installer initializes.
    @Volatile private var pendingRuntimeRoot: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    /// Stashes ACTION_SEND text/plain for Dart to pull via getSharedText.
    /// Called from configureFlutterEngine (cold start) and onNewIntent.
    private fun handleShareIntent(intent: Intent?) {
        try {
            if (intent?.action == Intent.ACTION_SEND &&
                intent.type?.startsWith("text/") == true) {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    ?: intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrBlank()) pendingSharedText = text
            }
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleShareIntent(intent)
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importChannelName)
        ModelDownloadService.emitter = { filename, copied, total, bps, status ->
            mainHandler.post {
                importChannel?.invokeMethod(
                    "importProgress",
                    mapOf(
                        "filename" to filename,
                        "copiedBytes" to copied,
                        "totalBytes" to total,
                        "bytesPerSecond" to bps,
                        "status" to status,
                    )
                )
            }
        }
        importChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndImportModel" -> {
                    if (pendingImportResult != null) {
                        result.error("IMPORT_BUSY", "Another model import is already running.", null)
                        return@setMethodCallHandler
                    }
                    val modelsDir = call.argument<String>("modelsDir")
                    if (modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DIR", "Models directory is missing.", null)
                        return@setMethodCallHandler
                    }
                    pendingModelsDir = modelsDir
                    pendingImportResult = result
                    openModelPicker()
                }
                "downloadToDownloads" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    if (url.isNullOrBlank() || filename.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "Model URL or filename is missing.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownloadToDownloads(url, filename)
                        result.success(mapOf("downloadId" to downloadId, "filename" to sanitizeFilename(filename)))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "cancelDownloadToDownloads" -> {
                    val downloadId = (call.argument<Any>("downloadId") as? Number)?.toLong()
                    if (downloadId != null) {
                        try {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.message ?: e.toString(), null)
                        }
                    } else {
                        result.error("INVALID_DOWNLOAD_ID", "Download ID is missing.", null)
                    }
                }
                "saveBytesToDownloads" -> {
                    val filename = call.argument<String>("filename")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val subfolder = sanitizeFilename(call.argument<String>("subfolder") ?: "CubicLM")
                        .ifBlank { "CubicLM" }
                    if (filename.isNullOrBlank() || bytes == null) {
                        result.error("INVALID_EXPORT", "Filename or bytes are missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "save-export") {
                        try {
                            val displayPath = saveBytesToDownloads(sanitizeFilename(filename), bytes, mimeType, subfolder)
                            mainHandler.post { result.success(displayPath) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SAVE_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }
                "pickExportFolder" -> {
                    if (pendingExportFolderResult != null) {
                        result.error("PICKER_BUSY", "A folder picker is already open.", null)
                        return@setMethodCallHandler
                    }
                    pendingExportFolderResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, exportFolderRequestCode)
                    } catch (e: Exception) {
                        pendingExportFolderResult = null
                        result.error("NO_FILE_MANAGER", e.message ?: e.toString(), null)
                    }
                }
                "checkTreeFolderAccess" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(treeUri)
                        val ok = contentResolver.persistedUriPermissions.any {
                            it.uri == uri && it.isWritePermission
                        }
                        result.success(ok)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "saveBytesToTreeFolder" -> {
                    val filename = call.argument<String>("filename")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val treeUri = call.argument<String>("treeUri")
                    if (filename.isNullOrBlank() || bytes == null || treeUri.isNullOrBlank()) {
                        result.error("INVALID_EXPORT", "Filename, bytes or folder are missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "save-export-tree") {
                        try {
                            val displayPath = saveBytesToTreeFolder(
                                sanitizeFilename(filename), bytes, mimeType, Uri.parse(treeUri))
                            mainHandler.post { result.success(displayPath) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SAVE_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }
                "listExportFiles" -> {
                    val subfolder = sanitizeFilename(call.argument<String>("subfolder") ?: "CubicLM")
                        .ifBlank { "CubicLM" }
                    thread(name = "list-exports") {
                        try {
                            val files = listExportFiles(subfolder)
                            mainHandler.post { result.success(files) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.success(emptyList<Map<String, Any?>>())
                            }
                        }
                    }
                }
                "listTreeFiles" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri.isNullOrBlank()) {
                        result.success(emptyList<Map<String, Any?>>())
                        return@setMethodCallHandler
                    }
                    thread(name = "list-exports-tree") {
                        try {
                            val files = listTreeFiles(Uri.parse(treeUri))
                            mainHandler.post { result.success(files) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.success(emptyList<Map<String, Any?>>())
                            }
                        }
                    }
                }
                "readExportFile" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("INVALID_READ", "File URI is missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "read-export") {
                        try {
                            val bytes = contentResolver
                                .openInputStream(Uri.parse(uri))
                                ?.use { it.readBytes() }
                            mainHandler.post {
                                if (bytes != null) {
                                    result.success(bytes)
                                } else {
                                    result.error(
                                        "READ_FAILED", "Could not open file.", null)
                                }
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "READ_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "deleteExportFile" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("INVALID_DELETE", "File URI is missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "delete-export") {
                        val rows = try {
                            contentResolver.delete(Uri.parse(uri), null, null)
                        } catch (_: Exception) {
                            0
                        }
                        mainHandler.post { result.success(rows > 0) }
                    }
                }
                "getDownloadsPath" -> {
                    try {
                        val dl = Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS)
                        result.success(dl.absolutePath)
                    } catch (_: Exception) {
                        result.success("")
                    }
                }
                "getTreeFolderPath" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri.isNullOrBlank()) {
                        result.success("")
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(treeDisplayName(Uri.parse(treeUri)))
                    } catch (_: Exception) {
                        result.success("")
                    }
                }
                "readVaultFile" -> {
                    val name = call.argument<String>("name")
                    val subfolder = sanitizeFilename(call.argument<String>("subfolder") ?: "DataSheet")
                        .ifBlank { "DataSheet" }
                    if (name.isNullOrBlank()) {
                        result.error("INVALID_VAULT", "Vault file name is missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "read-vault") {
                        try {
                            val bytes = readVaultFile(sanitizeFilename(name), subfolder)
                            mainHandler.post { result.success(bytes) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("READ_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }
                "writeVaultFile" -> {
                    val name = call.argument<String>("name")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/json"
                    val subfolder = sanitizeFilename(call.argument<String>("subfolder") ?: "DataSheet")
                        .ifBlank { "DataSheet" }
                    if (name.isNullOrBlank() || bytes == null) {
                        result.error("INVALID_VAULT", "Vault file name or bytes are missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "write-vault") {
                        try {
                            val displayPath = writeVaultFile(sanitizeFilename(name), bytes, mimeType, subfolder)
                            mainHandler.post { result.success(displayPath) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("WRITE_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }
                "downloadModelInApp" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    val modelsDir = call.argument<String>("modelsDir")
                    if (url.isNullOrBlank() || filename.isNullOrBlank() || modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "URL, filename, or modelsDir is missing.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownloadInApp(url, filename, modelsDir)
                        result.success(mapOf("downloadId" to downloadId, "filename" to sanitizeFilename(filename)))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "cancelDownloadInApp" -> {
                    val downloadId = (call.argument<Any>("downloadId") as? Number)?.toLong()
                    if (downloadId != null) {
                        try {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                            removeInAppDownload(downloadId)
                            val filename = call.argument<String>("filename")
                            if (!filename.isNullOrBlank()) {
                                val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), sanitizeFilename(filename))
                                if (destFile.exists()) destFile.delete()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.message ?: e.toString(), null)
                        }
                    } else {
                        result.error("INVALID_DOWNLOAD_ID", "Download ID is missing.", null)
                    }
                }
                "getActiveDownloads" -> {
                    thread(name = "download-inapp-reconcile") {
                        try {
                            val activeList = reconcileInAppDownloads()
                            mainHandler.post { result.success(activeList) }
                        } catch (e: java.lang.Exception) {
                            mainHandler.post {
                                result.error("QUERY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "startStreamDownload" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    val modelsDir = call.argument<String>("modelsDir")
                    if (url.isNullOrBlank() || filename.isNullOrBlank() || modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "URL, filename, or modelsDir is missing.", null)
                        return@setMethodCallHandler
                    }
                    val started = ModelDownloadService.startJob(this, url, filename, modelsDir)
                    if (started != null) {
                        result.success(mapOf("filename" to started))
                    } else {
                        result.error("DOWNLOAD_BUSY", "This model is already downloading.", null)
                    }
                }
                "pauseStreamDownload" -> {
                    val filename = call.argument<String>("filename")
                    if (!filename.isNullOrBlank()) {
                        ModelDownloadService.pauseJob(ModelDownloadService.sanitize(filename))
                        result.success(true)
                    } else {
                        result.error("INVALID_FILENAME", "Filename is missing.", null)
                    }
                }
                "cancelStreamDownload" -> {
                    val filename = call.argument<String>("filename")
                    if (!filename.isNullOrBlank()) {
                        ModelDownloadService.cancelJob(ModelDownloadService.sanitize(filename))
                        result.success(true)
                    } else {
                        result.error("INVALID_FILENAME", "Filename is missing.", null)
                    }
                }
                "getStreamDownloads" -> {
                    thread(name = "stream-download-snapshot") {
                        try {
                            val list = ModelDownloadService.persistedSnapshot(this)
                            mainHandler.post { result.success(list) }
                        } catch (e: java.lang.Exception) {
                            mainHandler.post {
                                result.error("QUERY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "restartApp" -> {
                    restartApp()
                    result.success(null)
                }
                "setSecureFlag" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setSecureFlag(enabled)
                    result.success(null)
                }
                "getSharedText" -> {
                    val text = pendingSharedText
                    pendingSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }

        // On-device APK installer (Dart: ApkInstallerService).
        // Channel "com.cubiclm.app/apkinstaller", method "installApk"
        // {path} -> {ok, error}. Uses a PackageInstaller session (no ADB);
        // falls back to a FileProvider ACTION_VIEW on MIUI-style ROMs.
        val apkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cubiclm.app/apkinstaller",
        )
        apkChannel.setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.success(mapOf("ok" to false, "error" to "APK path is missing."))
                return@setMethodCallHandler
            }
            thread(name = "apk-install") {
                try {
                    val outcome = installApkFile(path)
                    mainHandler.post { result.success(outcome) }
                } catch (e: Exception) {
                    mainHandler.post {
                        result.success(
                            mapOf("ok" to false, "error" to (e.message ?: e.toString())),
                        )
                    }
                }
            }
        }

        // Runtime toolchain keep-alive + progress (Dart: RuntimeInstaller).
        // Channel "com.cubiclm.app/runtime": setKeepAlive {active},
        // updateProgress {title, fraction, line}, setRuntimeRoot {path}.
        val runtimeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cubiclm.app/runtime",
        )
        runtimeChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepAlive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    RuntimeSetupService.setKeepAlive(this, active)
                    result.success(null)
                }
                "updateProgress" -> {
                    val title = call.argument<String>("title") ?: ""
                    val fraction =
                        (call.argument<Any>("fraction") as? Number)?.toDouble() ?: 0.0
                    val line = call.argument<String>("line") ?: ""
                    RuntimeSetupService.updateProgress(title, fraction, line)
                    result.success(null)
                }
                "setRuntimeRoot" -> {
                    pendingRuntimeRoot = call.argument<String>("path")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Battery reliability for long tasks (Dart: SetupChecklist).
        // Channel "com.cubiclm.app/power": isBatteryUnrestricted -> bool,
        // openBatterySettings -> bool (opened). Settings pages only — never
        // the direct exemption request (Play-policy friendly).
        val powerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cubiclm.app/power",
        )
        powerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryUnrestricted" -> {
                    val pm = getSystemService(POWER_SERVICE) as? PowerManager
                    result.success(
                        pm?.isIgnoringBatteryOptimizations(packageName) == true,
                    )
                }
                "openBatterySettings" -> {
                    result.success(openBatterySettingsPage())
                }
                "openDeveloperOptions" -> {
                    result.success(openDeveloperOptionsPage())
                }
                else -> result.notImplemented()
            }
        }

        // Isolated Ubuntu exec (Dart: ProotBackend via SandboxManager).
        // Channel "com.cubiclm.app/proot": ping -> bool,
        // exec {command, cwd, timeoutMs} -> {stdout, stderr, exitCode}.
        // Runs <runtimeRoot>/bin/proot over <runtimeRoot>/ubuntu once the
        // Core toolchain is installed; false/error until then (Dart falls
        // back to the screened host shell automatically).
        val prootChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cubiclm.app/proot",
        )
        prootChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> {
                    thread(name = "proot-ping") {
                        val ok = try {
                            isProotReady()
                        } catch (_: Exception) {
                            false
                        }
                        mainHandler.post { result.success(ok) }
                    }
                }
                "exec" -> {
                    val command = call.argument<String>("command") ?: ""
                    val cwd = call.argument<String>("cwd") ?: ""
                    val timeoutMs =
                        (call.argument<Any>("timeoutMs") as? Number)?.toLong()
                            ?: 30000L
                    thread(name = "proot-exec") {
                        try {
                            val outcome = runProotExec(command, cwd, timeoutMs)
                            mainHandler.post { result.success(outcome) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.success(
                                    mapOf(
                                        "stdout" to "",
                                        "stderr" to "PRoot exec failed: ${e.message ?: e}",
                                        "exitCode" to -1,
                                    ),
                                )
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

    }

    /// Hides app content from Recents screenshots / screen capture while
    /// App Lock is armed. Called from Dart via setSecureFlag.
    private fun setSecureFlag(enabled: Boolean) {
        try {
            if (enabled) {
                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
            }
        } catch (e: Exception) {
            Log.w("CubicLM", "setSecureFlag failed: ${e.message}")
        }
    }

    /// Installs the APK at [path] via a PackageInstaller session (no ADB).
    /// Returns `{ok, error}` for the apkinstaller channel. The user still
    /// confirms the install on-device; [ApkInstallReceiver] handles the
    /// system callback (confirm dialog, auto-launch, failure toast).
    private fun installApkFile(path: String): Map<String, Any?> {
        val file = File(path)
        if (!file.exists() || !file.isFile) {
            return mapOf("ok" to false, "error" to "APK not found: $path")
        }
        if (!path.lowercase().endsWith(".apk")) {
            return mapOf("ok" to false, "error" to "Not an APK file: $path")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            // Point the user at the unknown-apps permission, then report.
            try {
                val settings = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                startActivity(settings)
            } catch (_: Exception) {
            }
            return mapOf(
                "ok" to false,
                "error" to "Allow \"Install unknown apps\" for CubicLM, then retry.",
            )
        }
        try {
            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            )
            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            try {
                session.openWrite("apk", 0, -1).use { out ->
                    java.io.FileInputStream(file).use { input ->
                        input.copyTo(out)
                    }
                    session.fsync(out)
                }
                val statusIntent = Intent(
                    this,
                    ApkInstallReceiver::class.java,
                ).apply { action = ApkInstallReceiver.ACTION_INSTALL_STATUS }
                var flags = PendingIntent.FLAG_UPDATE_CURRENT
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    flags = flags or PendingIntent.FLAG_MUTABLE
                }
                val statusPi = PendingIntent.getBroadcast(
                    this, sessionId, statusIntent, flags,
                )
                session.commit(statusPi.intentSender)
            } finally {
                try {
                    session.close()
                } catch (_: Exception) {
                }
            }
            return mapOf("ok" to true, "error" to null)
        } catch (e: Exception) {
            Log.w("CubicLM", "PackageInstaller failed, trying fallback: ${e.message}")
            return installApkFallback(file)
        }
    }

    /// MIUI-style fallback: hand the APK to the system installer via a
    /// FileProvider content URI.
    private fun installApkFallback(file: File): Map<String, Any?> {
        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(view)
            mapOf("ok" to true, "error" to null)
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to (e.message ?: e.toString()))
        }
    }

    /// Open the system battery-optimization settings so the user can exempt
    /// CubicLM for reliable long downloads/tasks. Returns true when an
    /// activity was launched. Settings pages only (see power channel).
    private fun openBatterySettingsPage(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    /// Open Android Developer options (reference-app reliability parity):
    /// some devices gate child-process execution behind a developer
    /// toggle. Falls back to the main Settings page. Never throws.
    private fun openDeveloperOptionsPage(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    // ── Isolated Ubuntu runtime (PRoot) ──────────────────────────────

    private fun runtimeRoot(): File? {
        val root = pendingRuntimeRoot
        if (!root.isNullOrBlank()) return File(root)
        // Fallbacks if Dart has not reported the path yet.
        val candidates = listOf(
            File(filesDir, "runtime"),
            File(noBackupFilesDir, "runtime"),
            File(getExternalFilesDir(null), "runtime"),
        )
        return candidates.firstOrNull { it.isDirectory }
    }

    private fun prootBinary(): File? {
        val root = runtimeRoot() ?: return null
        val bin = File(root, "bin/proot")
        return if (bin.isFile && bin.canExecute()) bin else null
    }

    /// True when the Core toolchain can execute: rootfs bash + ready
    /// marker + executable proot binary + loader + bundled libs.
    private fun isProotReady(): Boolean {
        val root = runtimeRoot() ?: return false
        if (!File(root, ".ready-core").isFile) return false
        if (!File(root, "ubuntu/usr/bin/bash").isFile) return false
        if (!File(root, "libexec/proot/loader").isFile) return false
        return prootBinary() != null
    }

    /// Runs [command] inside the Ubuntu rootfs via proot. The host [cwd]
    /// must live under app-private storage (jail); it is bound at
    /// `/workspace` in the guest. Output streams are capped at 256 KB each.
    private fun runProotExec(
        command: String,
        cwd: String,
        timeoutMs: Long,
    ): Map<String, Any?> {
        if (command.isBlank()) {
            return mapOf("stdout" to "", "stderr" to "Empty command.", "exitCode" to -1)
        }
        val root = runtimeRoot()
            ?: return mapOf("stdout" to "", "stderr" to "Runtime not installed.", "exitCode" to -1)
        val proot = prootBinary()
            ?: return mapOf("stdout" to "", "stderr" to "PRoot binary missing.", "exitCode" to -1)
        val rootfs = File(root, "ubuntu")

        val hostDir = when {
            cwd.isBlank() -> filesDir
            else -> File(cwd)
        }
        if (!isAppPrivate(hostDir)) {
            return mapOf(
                "stdout" to "",
                "stderr" to "Working directory outside app storage is blocked.",
                "exitCode" to -1,
            )
        }
        if (!hostDir.isDirectory) hostDir.mkdirs()
        val tmpDir = File(cacheDir, "proot-tmp").apply { mkdirs() }
        // Device-verified on Redmi (PRoot 5.1.107.92): the loader is found
        // via PROOT_LOADER (never rely on Termux-prefix fallbacks), and the
        // bundled libtalloc/libandroid-shmem via LD_LIBRARY_PATH.
        val libDir = File(root, "lib")
        val loaderDir = File(root, "libexec/proot")

        val argv = listOf(
            proot.absolutePath,
            "--link2symlink",
            "-0",
            "-r", rootfs.absolutePath,
            "-b", "/dev",
            "-b", "/proc",
            "-b", "/sys",
            "-b", "${hostDir.absolutePath}:/workspace",
            "-w", "/workspace",
            "/bin/bash", "-c", command,
        )
        val env = mapOf(
            "HOME" to "/root",
            "PATH" to "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "LANG" to "C.UTF-8",
            "TERM" to "xterm-256color",
            "PROOT_NO_SECCOMP" to "1",
            "PROOT_TMP_DIR" to tmpDir.absolutePath,
            "PROOT_LOADER" to File(loaderDir, "loader").absolutePath,
            "PROOT_LOADER_32" to File(loaderDir, "loader32").absolutePath,
            "LD_LIBRARY_PATH" to libDir.absolutePath,
        )
        return try {
            val proc = ProcessBuilder(argv)
                .directory(hostDir)
                .apply {
                    environment().putAll(env)
                    environment().remove("LD_PRELOAD")
                }
                .start()
            proc.outputStream.close()
            val outCap = CappedReader(proc.inputStream)
            val errCap = CappedReader(proc.errorStream)
            val outThread = thread(name = "proot-stdout") { outCap.drain() }
            val errThread = thread(name = "proot-stderr") { errCap.drain() }
            val finished = proc.waitFor(
                timeoutMs.coerceIn(1000L, 300000L),
                java.util.concurrent.TimeUnit.MILLISECONDS,
            )
            if (!finished) {
                try {
                    proc.destroyForcibly()
                } catch (_: Exception) {
                }
                outThread.join(2000)
                errThread.join(2000)
                return mapOf(
                    "stdout" to outCap.text(),
                    "stderr" to (errCap.text() + "\n[timeout]").trim(),
                    "exitCode" to 124,
                )
            }
            outThread.join(5000)
            errThread.join(5000)
            mapOf(
                "stdout" to outCap.text(),
                "stderr" to errCap.text(),
                "exitCode" to proc.exitValue(),
            )
        } catch (e: Exception) {
            mapOf("stdout" to "", "stderr" to "PRoot exec failed: ${e.message ?: e}", "exitCode" to -1)
        }
    }

    /// App-private storage jail for proot binds (mirrors the Dart sandbox).
    private fun isAppPrivate(dir: File): Boolean {
        return try {
            val canon = dir.canonicalPath
            val roots = listOfNotNull(
                filesDir?.canonicalPath,
                cacheDir?.canonicalPath,
                noBackupFilesDir?.canonicalPath,
                getExternalFilesDir(null)?.canonicalPath,
                codeCacheDir?.canonicalPath,
            )
            roots.any { canon == it || canon.startsWith("$it/") }
        } catch (_: Exception) {
            false
        }
    }

    /// Stream reader capped at 256 KB so runaway output cannot OOM the app.
    private class CappedReader(
        private val stream: java.io.InputStream,
        private val cap: Int = 256 * 1024,
    ) {
        private val buf = java.io.ByteArrayOutputStream()
        private var truncated = false

        fun drain() {
            try {
                val tmp = ByteArray(8192)
                while (true) {
                    val n = stream.read(tmp)
                    if (n <= 0) break
                    if (buf.size() < cap) {
                        buf.write(tmp, 0, minOf(n, cap - buf.size()))
                    } else {
                        truncated = true
                    }
                }
            } catch (_: Exception) {
            } finally {
                try {
                    stream.close()
                } catch (_: Exception) {
                }
            }
        }

        fun text(): String {
            val s = buf.toString(Charsets.UTF_8.name())
            return if (truncated) "$s\n[…truncated]" else s
        }
    }

    /// Writes export bytes into Download/<subfolder> without any picker
    /// dialog (MediaStore on API 29+, direct write below). No storage
    /// permission needed on modern Android. Returns a display path.
    private fun saveBytesToDownloads(
        filename: String,
        bytes: ByteArray,
        mimeType: String,
        subfolder: String,
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/$subfolder"
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw Exception("MediaStore refused the file")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw Exception("Could not open output stream")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                ),
                subfolder
            )
            if (!dir.exists() && !dir.mkdirs()) {
                throw Exception("Could not create $subfolder")
            }
            File(dir, filename).writeBytes(bytes)
        }
        return "Download/$subfolder/$filename"
    }

    /// Writes export bytes into a user-picked Storage Access Framework
    /// folder (ACTION_OPEN_DOCUMENT_TREE + persistable permission). Works
    /// on every Android version with no storage permission. Returns a
    /// display path for the success snackbar.
    private fun saveBytesToTreeFolder(
        filename: String,
        bytes: ByteArray,
        mimeType: String,
        treeUri: android.net.Uri,
    ): String {
        val docUri = DocumentsContract.createDocument(
            contentResolver, treeUri, mimeType, filename
        ) ?: throw Exception("Could not create file in the picked folder")
        try {
            contentResolver.openOutputStream(docUri)?.use { it.write(bytes) }
                ?: throw Exception("Could not open output stream")
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(contentResolver, docUri)
            } catch (_: Exception) {
            }
            throw e
        }
        return "${treeDisplayName(treeUri)}/$filename"
    }

    /// Human name of a picked tree (e.g. "MyExports"), "Downloads" style
    /// fallback when the provider won't say.
    private fun treeDisplayName(treeUri: android.net.Uri): String {
        try {
            contentResolver.query(
                treeUri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val name = c.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (_: Exception) {
        }
        return treeUri.lastPathSegment
            ?.substringAfterLast(':')
            ?.substringAfterLast('/')
            ?.ifBlank { "Picked folder" }
            ?: "Picked folder"
    }

    /// Saved `.txt`/`.log` exports in Download/<subfolder> via MediaStore.
    /// Returns [{name, uri, size, modified}] with content URIs (direct
    /// file paths don't work under scoped storage) and millis timestamps.
    /// Newest first. Never throws (empty list on any failure).
    private fun listExportFiles(subfolder: String): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        try {
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Downloads.EXTERNAL_CONTENT_URI
            }
            val selection = "${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
            val args = arrayOf("%${Environment.DIRECTORY_DOWNLOADS}/$subfolder%")
            contentResolver.query(
                collection,
                arrayOf(
                    MediaStore.Downloads._ID,
                    MediaStore.Downloads.DISPLAY_NAME,
                    MediaStore.Downloads.SIZE,
                    MediaStore.Downloads.DATE_MODIFIED,
                    MediaStore.Downloads.MIME_TYPE,
                ),
                selection, args,
                "${MediaStore.Downloads.DATE_MODIFIED} DESC",
            )?.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                val nameCol = c.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                val sizeCol = c.getColumnIndex(MediaStore.Downloads.SIZE)
                val modCol = c.getColumnIndex(MediaStore.Downloads.DATE_MODIFIED)
                val mimeCol = c.getColumnIndex(MediaStore.Downloads.MIME_TYPE)
                while (c.moveToNext()) {
                    try {
                        val name = c.getString(nameCol) ?: continue
                        if (!name.endsWith(".txt", true) &&
                            !name.endsWith(".log", true)) continue
                        val id = c.getLong(idCol)
                        val uri = android.content.ContentUris.withAppendedId(
                            collection, id)
                        val size =
                            if (sizeCol >= 0 && !c.isNull(sizeCol)) c.getLong(sizeCol) else 0L
                        val modSec =
                            if (modCol >= 0 && !c.isNull(modCol)) c.getLong(modCol) else 0L
                        val mime = if (mimeCol >= 0) c.getString(mimeCol) else null
                        out.add(mapOf(
                            "name" to name,
                            "uri" to uri.toString(),
                            "size" to size,
                            "modified" to modSec * 1000L,
                            "mime" to mime,
                        ))
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
        return out
    }

    /// Same listing inside a user-picked Storage Access Framework folder
    /// (DocumentsContract child query — no extra dependency). Newest
    /// first. Never throws.
    private fun listTreeFiles(treeUri: android.net.Uri): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        try {
            val children = android.provider.DocumentsContract
                .buildChildDocumentsUriUsingTree(
                    treeUri,
                    android.provider.DocumentsContract.getTreeDocumentId(treeUri))
            contentResolver.query(
                children,
                arrayOf(
                    android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    android.provider.DocumentsContract.Document.COLUMN_SIZE,
                    android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                    android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null, null, null,
            )?.use { c ->
                val idCol = c.getColumnIndexOrThrow(
                    android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameCol = c.getColumnIndexOrThrow(
                    android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val sizeCol = c.getColumnIndex(
                    android.provider.DocumentsContract.Document.COLUMN_SIZE)
                val modCol = c.getColumnIndex(
                    android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                val mimeCol = c.getColumnIndex(
                    android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE)
                while (c.moveToNext()) {
                    try {
                        val name = c.getString(nameCol) ?: continue
                        if (!name.endsWith(".txt", true) &&
                            !name.endsWith(".log", true)) continue
                        val docId = c.getString(idCol) ?: continue
                        val uri = android.provider.DocumentsContract
                            .buildDocumentUriUsingTree(treeUri, docId)
                        val size =
                            if (sizeCol >= 0 && !c.isNull(sizeCol)) c.getLong(sizeCol) else 0L
                        val modMs =
                            if (modCol >= 0 && !c.isNull(modCol)) c.getLong(modCol) else 0L
                        val mime = if (mimeCol >= 0) c.getString(mimeCol) else null
                        out.add(mapOf(
                            "name" to name,
                            "uri" to uri.toString(),
                            "size" to size,
                            "modified" to modMs,
                            "mime" to mime,
                        ))
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
        out.sortByDescending {
            (it["modified"] as? Number)?.toLong() ?: 0L
        }
        return out
    }

    /// CubicDataSheet vault file in Download/<subfolder> (MediaStore).
    /// Reads update in place across reinstalls: entries created by this
    /// package stay writable after reinstall (same package + signature),
    /// so the vault survives app uninstall by design.
    private fun findVaultUri(name: String, subfolder: String): android.net.Uri? {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }
        val selection =
            "${MediaStore.Downloads.DISPLAY_NAME}=? AND ${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
        val args = arrayOf(name, "%${Environment.DIRECTORY_DOWNLOADS}/$subfolder%")
        contentResolver.query(
            collection,
            arrayOf(MediaStore.Downloads._ID),
            selection, args, null
        )?.use { c ->
            if (c.moveToFirst()) {
                val id = c.getLong(0)
                return android.net.Uri.withAppendedPath(collection, "$id")
            }
        }
        return null
    }

    private fun readVaultFile(name: String, subfolder: String): ByteArray? {
        val uri = findVaultUri(name, subfolder) ?: return null
        contentResolver.openInputStream(uri)?.use { return it.readBytes() }
        return null
    }

    private fun writeVaultFile(
        name: String,
        bytes: ByteArray,
        mimeType: String,
        subfolder: String,
    ): String {
        val existing = findVaultUri(name, subfolder)
        if (existing != null) {
            try {
                contentResolver.openOutputStream(existing, "wt")?.use {
                    it.write(bytes)
                } ?: throw Exception("Could not open vault for update")
                return "Download/$subfolder/$name"
            } catch (_: Exception) {
                try {
                    contentResolver.delete(existing, null, null)
                } catch (_: Exception) {
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/$subfolder"
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                values
            ) ?: throw Exception("MediaStore refused the vault file")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw Exception("Could not open output stream")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                ),
                subfolder
            )
            if (!dir.exists() && !dir.mkdirs()) {
                throw Exception("Could not create $subfolder")
            }
            File(dir, name).writeBytes(bytes)
        }
        return "Download/$subfolder/$name"
    }

    private fun restartApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            finishAffinity()
            return
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        val pendingIntent = PendingIntent.getActivity(
            this,
            9208,
            launchIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.RTC,
            System.currentTimeMillis() + 350L,
            pendingIntent
        )
        finishAffinity()
        exitProcess(0)
    }

    private fun enqueueDownloadToDownloads(url: String, filename: String): Long {
        val safeName = sanitizeFilename(filename)
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(safeName)
            setDescription("Downloading AI model")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeName)
            addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
            addRequestHeader("Accept", "*/*")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)

        thread(name = "download-monitor-$downloadId") {
            var isFinished = false
            var lastBytes = 0L
            var lastTime = System.currentTimeMillis()
            var lastReportedSpeed = 0.0

            while (!isFinished) {
                Thread.sleep(1000)
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val bytesDownloadedIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        val bytesTotalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)

                        if (statusIndex >= 0 && bytesDownloadedIndex >= 0 && bytesTotalIndex >= 0) {
                            val status = cursor.getInt(statusIndex)
                            val downloaded = cursor.getLong(bytesDownloadedIndex)
                            val total = cursor.getLong(bytesTotalIndex)

                            val now = System.currentTimeMillis()
                            val elapsedSeconds = (now - lastTime) / 1000.0
                            var bytesPerSecond = 0.0

                            if (downloaded > lastBytes) {
                                bytesPerSecond = if (elapsedSeconds > 0) ((downloaded - lastBytes) / elapsedSeconds) else 0.0
                                lastBytes = downloaded
                                lastTime = now
                                lastReportedSpeed = bytesPerSecond
                            } else {
                                if (elapsedSeconds > 3.0) {
                                    lastReportedSpeed = 0.0
                                }
                                bytesPerSecond = lastReportedSpeed
                            }

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                isFinished = true
                                emitProgress(safeName, total, total, 0.0, "Download complete")
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                isFinished = true
                                emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                            } else {
                                emitProgress(safeName, downloaded, total, bytesPerSecond, "Downloading to phone...")
                            }
                        }
                    } else {
                        isFinished = true
                        emitProgress(safeName, 0, 0, 0.0, "Download cancelled")
                    }
                } ?: run {
                    isFinished = true
                }
            }
        }
        return downloadId
    }

    private fun enqueueDownloadInApp(url: String, filename: String, modelsDir: String): Long {
        val safeName = sanitizeFilename(filename)
        val tempDownloadsDir = File(getExternalFilesDir(null), "temp_downloads")
        tempDownloadsDir.mkdirs()
        val destFile = File(tempDownloadsDir, safeName)
        if (destFile.exists()) destFile.delete()

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(safeName)
            setDescription("Downloading local AI model")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationUri(Uri.fromFile(destFile))
            addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
            addRequestHeader("Accept", "*/*")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)
        persistInAppDownload(downloadId, safeName, modelsDir)
        monitorInAppDownload(downloadId, safeName, modelsDir)
        return downloadId
    }

    private fun monitorInAppDownload(downloadId: Long, safeName: String, modelsDir: String) {
        if (!monitoredInAppDownloads.add(downloadId)) return
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), safeName)
        thread(name = "download-inapp-monitor-$downloadId") {
            var isFinished = false
            var lastBytes = 0L
            var lastTime = System.currentTimeMillis()
            var lastReportedSpeed = 0.0

            while (!isFinished) {
                Thread.sleep(1000)
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val bytesDownloadedIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        val bytesTotalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)

                        if (statusIndex >= 0 && bytesDownloadedIndex >= 0 && bytesTotalIndex >= 0) {
                            val status = cursor.getInt(statusIndex)
                            val downloaded = cursor.getLong(bytesDownloadedIndex)
                            val total = cursor.getLong(bytesTotalIndex)

                            val now = System.currentTimeMillis()
                            val elapsedSeconds = (now - lastTime) / 1000.0
                            var bytesPerSecond = 0.0

                            if (downloaded > lastBytes) {
                                bytesPerSecond = if (elapsedSeconds > 0) ((downloaded - lastBytes) / elapsedSeconds) else 0.0
                                lastBytes = downloaded
                                lastTime = now
                                lastReportedSpeed = bytesPerSecond
                            } else {
                                if (elapsedSeconds > 3.0) {
                                    lastReportedSpeed = 0.0
                                }
                                bytesPerSecond = lastReportedSpeed
                            }

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                isFinished = true
                                finalizeInAppDownload(downloadId, safeName, modelsDir, downloaded, total)
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                isFinished = true
                                removeInAppDownload(downloadId)
                                emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                            } else {
                                emitProgress(safeName, downloaded, total, bytesPerSecond, "Downloading...")
                            }
                        }
                    } else {
                        isFinished = true
                        removeInAppDownload(downloadId)
                        emitProgress(safeName, 0, 0, 0.0, "Download cancelled")
                    }
                } ?: run {
                    isFinished = true
                }
            }
            monitoredInAppDownloads.remove(downloadId)
        }
    }

    private fun finalizeInAppDownload(
        downloadId: Long,
        safeName: String,
        modelsDir: String,
        downloaded: Long,
        total: Long,
    ) {
        val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), safeName)
        try {
            emitProgress(safeName, downloaded, total, 0.0, "Importing to app storage...")
            val targetFile = File(modelsDir, safeName)
            targetFile.parentFile?.mkdirs()
            val partFile = File(targetFile.parentFile, "${targetFile.name}.part")
            if (partFile.exists()) partFile.delete()
            if (!destFile.exists()) {
                if (targetFile.exists() && targetFile.length() > 0L) {
                    removeInAppDownload(downloadId)
                    emitProgress(safeName, total, total, 0.0, "Download complete")
                    return
                }
                throw IllegalStateException("Downloaded temporary file is missing.")
            }
            destFile.copyTo(partFile, overwrite = true)
            if (targetFile.exists()) targetFile.delete()
            if (!partFile.renameTo(targetFile)) {
                throw IllegalStateException("Unable to finalize downloaded model.")
            }
            destFile.delete()
            removeInAppDownload(downloadId)
            emitProgress(safeName, total, total, 0.0, "Download complete")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to import downloaded model: ${e.message}", e)
            emitProgress(safeName, downloaded, total, 0.0, "Download failed: import error")
        }
    }

    private fun persistInAppDownload(downloadId: Long, filename: String, modelsDir: String) {
        val record = JSONObject()
            .put("filename", filename)
            .put("modelsDir", modelsDir)
        getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
            .edit()
            .putString(downloadId.toString(), record.toString())
            .apply()
    }

    private fun removeInAppDownload(downloadId: Long) {
        getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
            .edit()
            .remove(downloadId.toString())
            .apply()
    }

    private fun reconcileInAppDownloads(): List<Map<String, Any>> {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val preferences = getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
        val activeList = mutableListOf<Map<String, Any>>()
        for ((idText, rawRecord) in preferences.all) {
            val downloadId = idText.toLongOrNull() ?: continue
            val record = runCatching { JSONObject(rawRecord as String) }.getOrNull() ?: continue
            val safeName = record.optString("filename")
            val modelsDir = record.optString("modelsDir")
            if (safeName.isBlank() || modelsDir.isBlank()) {
                removeInAppDownload(downloadId)
                continue
            }
            manager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    removeInAppDownload(downloadId)
                    return@use
                }
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL ->
                        finalizeInAppDownload(downloadId, safeName, modelsDir, downloaded, total)
                    DownloadManager.STATUS_FAILED -> {
                        removeInAppDownload(downloadId)
                        emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                    }
                    else -> {
                        val statusText = when (status) {
                            DownloadManager.STATUS_PAUSED -> "Paused"
                            DownloadManager.STATUS_PENDING -> "Pending"
                            else -> "Downloading..."
                        }
                        activeList.add(mapOf(
                            "downloadId" to downloadId,
                            "filename" to safeName,
                            "downloaded" to downloaded,
                            "total" to total,
                            "status" to statusText,
                        ))
                        monitorInAppDownload(downloadId, safeName, modelsDir)
                    }
                }
            }
        }
        return activeList
    }

    private fun openModelPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, importRequestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == exportFolderRequestCode) {
            val pending = pendingExportFolderResult
            pendingExportFolderResult = null
            if (pending == null) return
            if (resultCode != RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            val treeUri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                pending.error("PERMISSION_DENIED", e.message ?: e.toString(), null)
                return
            }
            pending.success(mapOf(
                "uri" to treeUri.toString(),
                "name" to treeDisplayName(treeUri),
            ))
            return
        }
        if (requestCode != importRequestCode) return

        if (resultCode != RESULT_OK || data?.data == null) {
            finishImportSuccess(mapOf("cancelled" to true))
            return
        }

        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Some providers do not allow persistable grants; the one-shot grant is enough here.
        }

        val filename = displayNameFor(uri)
        val lower = filename.lowercase()
        if (!lower.endsWith(".gguf") && !lower.endsWith(".litertlm") && !lower.endsWith(".safetensors")) {
            finishImportError(
                "UNSUPPORTED_MODEL",
                "Only .gguf, .litertlm, and .safetensors files can be imported."
            )
            return
        }

        val size = sizeFor(uri)
        if (size <= 0L) {
            finishImportError("EMPTY_MODEL", "The selected file is empty or unreadable.")
            return
        }

        val modelsDir = pendingModelsDir
        if (modelsDir.isNullOrBlank()) {
            finishImportError("INVALID_DIR", "Models directory is missing.")
            return
        }

        val destination = File(modelsDir, sanitizeFilename(filename))
        if (destination.exists()) {
            AlertDialog.Builder(this)
                .setTitle("Model already imported")
                .setMessage("${destination.name} already exists in app storage. Replace it?")
                .setNegativeButton("Cancel") { _, _ ->
                    finishImportSuccess(mapOf("cancelled" to true))
                }
                .setPositiveButton("Replace") { _, _ ->
                    copyUriToModel(uri, destination, size, true)
                }
                .show()
        } else {
            copyUriToModel(uri, destination, size, false)
        }
    }

    private fun copyUriToModel(uri: Uri, destination: File, totalBytes: Long, replacing: Boolean) {
        emitProgress(destination.name, 0L, totalBytes, 0.0, "Copying to app storage...")
        thread(name = "model-import-${destination.name}") {
            val partFile = File(destination.parentFile, "${destination.name}.part")
            val startedAt = System.currentTimeMillis()
            var copied = 0L
            try {
                destination.parentFile?.mkdirs()
                if (partFile.exists()) partFile.delete()

                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Unable to open selected file.")
                    }
                    partFile.outputStream().use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            copied += read
                            val elapsedSeconds =
                                (System.currentTimeMillis() - startedAt).coerceAtLeast(1) / 1000.0
                            emitProgress(
                                destination.name,
                                copied,
                                totalBytes,
                                copied / elapsedSeconds,
                                "Copying to app storage..."
                            )
                        }
                    }
                }

                if (replacing && destination.exists()) destination.delete()
                if (!partFile.renameTo(destination)) {
                    throw IllegalStateException("Unable to finalize imported model.")
                }
                emitProgress(destination.name, totalBytes, totalBytes, 0.0, "Import complete")
                finishImportSuccess(
                    mapOf(
                        "cancelled" to false,
                        "filename" to destination.name,
                        "bytes" to totalBytes,
                        "replaced" to replacing
                    )
                )
            } catch (e: Exception) {
                if (partFile.exists()) partFile.delete()
                finishImportError("IMPORT_FAILED", e.message ?: e.toString())
            }
        }
    }

    private fun emitProgress(
        filename: String,
        copiedBytes: Long,
        totalBytes: Long,
        bytesPerSecond: Double,
        status: String,
    ) {
        mainHandler.post {
            importChannel?.invokeMethod(
                "importProgress",
                mapOf(
                    "filename" to filename,
                    "copiedBytes" to copiedBytes,
                    "totalBytes" to totalBytes,
                    "bytesPerSecond" to bytesPerSecond,
                    "status" to status
                )
            )
        }
    }

    private fun finishImportSuccess(payload: Map<String, Any?>) {
        mainHandler.post {
            pendingImportResult?.success(payload)
            pendingImportResult = null
            pendingModelsDir = null
        }
    }

    private fun finishImportError(code: String, message: String) {
        mainHandler.post {
            pendingImportResult?.error(code, message, null)
            pendingImportResult = null
            pendingModelsDir = null
        }
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val value = cursor.getString(index)
                        if (!value.isNullOrBlank()) return value
                    }
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "model.gguf"
    }

    private fun sizeFor(uri: Uri): Long {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0) return cursor.getLong(index)
                }
            }
        return -1L
    }

    private fun sanitizeFilename(filename: String): String {
        return filename.replace(Regex("""[\\/:*?"<>|]"""), "_")
    }
}
