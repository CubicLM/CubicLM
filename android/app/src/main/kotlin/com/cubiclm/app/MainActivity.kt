package com.cubiclm.app

import android.app.ActivityManager
import android.app.AlertDialog
import android.app.AlarmManager
import android.app.DownloadManager
import android.app.PendingIntent
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.hardware.camera2.CameraCharacteristics as CamChars
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.BatteryManager
import android.os.PowerManager
import android.os.StatFs
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
    private val processExitChannelName = "com.cubiclm.app/process_exit"
    private val importRequestCode = 4207
    private val exportFolderRequestCode = 4208
    private val mainHandler = Handler(Looper.getMainLooper())

    private var importChannel: MethodChannel? = null
    private var crashHandlerInstalled = false
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

    /// getprop dump, parsed once per systemInfo call (fast, no root).
    private fun getPropAll(): Map<String, String> {
        return try {
            val out = HashMap<String, String>()
            val p = Runtime.getRuntime().exec("getprop")
            val r = p.inputStream.bufferedReader().readText()
            p.waitFor()
            val re = Regex("""\[(.+?)]: \[(.*?)]""")
            for (m in re.findAll(r)) {
                out[m.groupValues[1]] = m.groupValues[2]
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /// Full System-tab bundle for CubicDevice Info. Best effort throughout:
    /// unknowns come back as "—"/-1 and the UI renders them honestly.
    private fun collectSystemInfo(): Map<String, Any> {
        val props = getPropAll()
        fun prop(vararg keys: String): String {
            for (k in keys) {
                val v = props[k]
                if (!v.isNullOrEmpty()) return v
            }
            return "—"
        }

        // MIUI: "V125"-style build tag, empty on non-MIUI.
        val miui = props["ro.miui.ui.version.name"] ?: ""
        // Bootloader: Build field + verified-boot lock state.
        val vbs = props["ro.boot.verifiedbootstate"] ?: ""
        val lock = when (vbs) {
            "green" -> "Locked"
            "orange", "yellow" -> "Unlocked"
            "red" -> "Failed"
            else -> "Unknown"
        }
        val bootloader = try {
            "${android.os.Build.BOOTLOADER} ($lock)"
        } catch (_: Exception) {
            "($lock)"
        }
        // Baseband radio version.
        val baseband = try {
            android.os.Build.getRadioVersion() ?: "—"
        } catch (_: Exception) {
            "—"
        }
        // ART version.
        val javaVm = try {
            System.getProperty("java.vm.version") ?: "—"
        } catch (_: Exception) {
            "—"
        }
        // OpenGL ES via ActivityManager (no permission needed).
        val gles = try {
            val am = getSystemService(ACTIVITY_SERVICE)
                as? android.app.ActivityManager
            val v = am?.deviceConfigurationInfo
                ?.reqGlEsVersion ?: 0
            if (v == 0) "—"
            else "${v shr 16}.${v and 0xFFFF}"
        } catch (_: Exception) {
            "—"
        }
        // Root: su binaries + known manager packages ("No Apps Detected").
        val suPaths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/su/bin/su", "/system/app/Superuser.apk",
        )
        val suFound = suPaths.any {
            try {
                java.io.File(it).exists()
            } catch (_: Exception) {
                false
            }
        }
        val rootPkgs = listOf(
            "com.topjohnwu.magisk" to "Magisk",
            "eu.chainfire.supersu" to "SuperSU",
            "com.koushikdutta.superuser" to "Superuser",
            "com.kingroot.kinguser" to "KingRoot",
        )
        val foundPkgs = rootPkgs.mapNotNull { (pkg, label) ->
            try {
                packageManager.getPackageInfo(pkg, 0)
                label
            } catch (_: Exception) {
                null
            }
        }
        val rootApps = buildList {
            if (suFound) add("su binary")
            addAll(foundPkgs)
        }.distinct().joinToString(", ").ifEmpty {
            "No Apps Detected"
        }
        // SELinux enforcing state.
        val selinux = try {
            when (
                java.io.File("/sys/fs/selinux/enforce")
                    .readText().trim()
            ) {
                "1" -> "Enforcing"
                "0" -> "Permissive"
                else -> "Unable to determine"
            }
        } catch (_: Exception) {
            "Unable to determine"
        }
        // Google Play Services version.
        val gms = try {
            val pi = packageManager.getPackageInfo(
                "com.google.android.gms", 0,
            )
            val code = if (android.os.Build.VERSION.SDK_INT >= 28) {
                pi.longVersionCode.toString()
            } else {
                @Suppress("DEPRECATION")
                pi.versionCode.toString()
            }
            "${pi.versionName} ($code)"
        } catch (_: Exception) {
            "—"
        }
        // Vulkan support + version from system features.
        var vulkan = "Not Supported"
        try {
            val feats = packageManager.systemAvailableFeatures
            for (f in feats) {
                if (f?.name ==
                    android.content.pm.PackageManager
                        .FEATURE_VULKAN_HARDWARE_VERSION
                ) {
                    val v = f.version
                    val major = (v shr 22) and 0x3FF
                    val minor = (v shr 12) and 0x3FF
                    vulkan = "Supported ($major.$minor)"
                    break
                }
            }
        } catch (_: Exception) {
        }
        fun onOff(v: String?) =
            if (v == "true") "Supported" else "Not Supported"
        // Widevine DRM via MediaDrm (no permission needed).
        var drmVendor = "—"
        var drmDesc = "—"
        var drmVersion = "—"
        var drmAlgos = "—"
        var drmSec = "—"
        var drmHdcp = "—"
        try {
            val uuid = java.util.UUID.fromString(
                "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
            )
            val drm = android.media.MediaDrm(uuid)
            try {
                drmVendor = drm.getPropertyString("vendor")
                drmDesc = drm.getPropertyString("description")
                drmVersion = drm.getPropertyString("version")
                drmAlgos = drm.getPropertyString("algorithms")
                drmSec = drm.getPropertyString("securityLevel")
                // getMaxHDCPSupported() via reflection: direct symbol
                // access fails to resolve on this toolchain; the
                // method itself is public API since 28.
                val hdcpRaw: Int = try {
                    val m = android.media.MediaDrm::class.java
                        .getMethod("getMaxHDCPSupported")
                    (m.invoke(drm) as? Int) ?: -1
                } catch (_: Exception) {
                    -1
                }
                drmHdcp = when (hdcpRaw) {
                    5 -> "2.3"
                    4 -> "2.2"
                    3 -> "2.1"
                    2 -> "2.0"
                    1 -> "1.x"
                    else -> "—"
                }
            } finally {
                try {
                    drm.release()
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        // SDK extension versions (API 30+).
        var sdkExt = -1
        try {
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                sdkExt = android.os.ext.SdkExtensions
                    .getExtensionVersion(
                        android.os.Build.VERSION_CODES.R,
                    )
            }
        } catch (_: Exception) {
        }
        // Timezone id + display name.
        val tz = try {
            java.util.TimeZone.getDefault()
        } catch (_: Exception) {
            null
        }
        return mapOf(
            "miui" to miui,
            "bootloader" to bootloader,
            "baseband" to baseband,
            "javaVm" to javaVm,
            "gles" to gles,
            "rootApps" to rootApps,
            "selinux" to selinux,
            "gms" to gms,
            "vulkan" to vulkan,
            "treble" to onOff(props["ro.treble.enabled"]),
            "seamless" to onOff(props["ro.build.ab_update"]),
            "dynamic" to onOff(props["ro.boot.dynamic_partitions"]),
            "sdkExt" to sdkExt,
            "tzId" to (tz?.id ?: "—"),
            "tzName" to try {
                tz?.getDisplayName() ?: "—"
            } catch (_: Exception) {
                "—"
            },
            "drmVendor" to drmVendor,
            "drmDesc" to drmDesc,
            "drmVersion" to drmVersion,
            "drmAlgos" to drmAlgos,
            "drmSec" to drmSec,
            "drmHdcp" to drmHdcp,
        )
    }

    /// Live battery snapshot: current, status, plug, counters.
    /// currentUa is SIGNED micro-amps (negative = discharging).
    private fun collectBattLive(): Map<String, Any> {
        var currentUa = -1L
        var counterMah = -1
        var plugged = "Battery"
        var status = "Discharging"
        var level = -1
        var charging = false
        var voltageMv = -1
        var tempC = -1.0
        try {
            val bm = getSystemService(BATTERY_SERVICE)
                as? android.os.BatteryManager
            try {
                currentUa = bm?.getIntProperty(
                    android.os.BatteryManager
                        .BATTERY_PROPERTY_CURRENT_NOW,
                )?.toLong() ?: -1L
            } catch (_: Exception) {
            }
            try {
                val cc = bm?.getIntProperty(
                    android.os.BatteryManager
                        .BATTERY_PROPERTY_CHARGE_COUNTER,
                ) ?: -1
                if (cc > 0) counterMah = cc / 1000
            } catch (_: Exception) {
            }
            val st = registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
            if (st != null) {
                val s = st.getIntExtra(
                    android.os.BatteryManager.EXTRA_STATUS, -1,
                )
                status = when (s) {
                    android.os.BatteryManager.BATTERY_STATUS_CHARGING ->
                        "Charging"
                    android.os.BatteryManager.BATTERY_STATUS_FULL ->
                        "Charged"
                    android.os.BatteryManager.BATTERY_STATUS_NOT_CHARGING ->
                        "Not charging"
                    else -> "Discharging"
                }
                charging = s == android.os.BatteryManager
                    .BATTERY_STATUS_CHARGING ||
                    s == android.os.BatteryManager
                        .BATTERY_STATUS_FULL
                level = (st.getIntExtra(
                    android.os.BatteryManager.EXTRA_LEVEL, -1,
                ))
                plugged = when (
                    st.getIntExtra(
                        android.os.BatteryManager.EXTRA_PLUGGED, -1,
                    )
                ) {
                    android.os.BatteryManager
                        .BATTERY_PLUGGED_AC -> "AC"
                    android.os.BatteryManager
                        .BATTERY_PLUGGED_USB -> "USB"
                    android.os.BatteryManager
                        .BATTERY_PLUGGED_WIRELESS -> "Wireless"
                    else -> "Battery"
                }
                voltageMv = st.getIntExtra(
                    android.os.BatteryManager.EXTRA_VOLTAGE, -1,
                )
                tempC = st.getIntExtra(
                    android.os.BatteryManager.EXTRA_TEMPERATURE, -1,
                ) / 10.0
            }
        } catch (_: Exception) {
        }
        // Design + current full-charge capacities (sysfs, no root).
        var designMah = -1
        var fullMah = -1
        try {
            designMah = java.io.File(
                "/sys/class/power_supply/battery/charge_full_design",
            ).readText().trim().toLong().div(1000).toInt()
        } catch (_: Exception) {
        }
        try {
            fullMah = java.io.File(
                "/sys/class/power_supply/battery/charge_full",
            ).readText().trim().toLong().div(1000).toInt()
        } catch (_: Exception) {
        }
        return mapOf(
            "currentUa" to currentUa,
            "counterMah" to counterMah,
            "plugged" to plugged,
            "status" to status,
            "level" to level,
            "charging" to charging,
            "voltageMv" to voltageMv,
            "tempC" to tempC,
            "designMah" to designMah,
            "fullMah" to fullMah,
        )
    }

    /// Validated-internet + metered flags for the Connectivity tab.
    private fun collectNetExtra(): Map<String, Any> {
        var validated = false
        var metered = false
        var captive = false
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE)
                as? android.net.ConnectivityManager
            val net = cm?.activeNetwork
            val caps = if (net != null) {
                cm.getNetworkCapabilities(net)
            } else {
                null
            }
            if (caps != null) {
                validated = caps.hasCapability(
                    android.net.NetworkCapabilities
                        .NET_CAPABILITY_VALIDATED,
                )
                captive = caps.hasCapability(
                    android.net.NetworkCapabilities
                        .NET_CAPABILITY_CAPTIVE_PORTAL,
                )
            }
            try {
                metered = cm?.isActiveNetworkMetered() ?: false
            } catch (_: Exception) {
            }
        } catch (_: Exception) {
        }
        return mapOf(
            "validated" to validated,
            "metered" to metered,
            "captive" to captive,
        )
    }

    /// Display tab bundle. Everything here is permission-free
    /// (Display APIs + Settings.System reads).
    private fun collectDisplayInfo(): Map<String, Any?> {
        var wPx = -1
        var hPx = -1
        var densityDpi = -1
        var fontScale = -1.0f
        var xdpi = -1f
        var ydpi = -1f
        var refreshNow = -1f
        val refreshAll = ArrayList<Double>()
        var hdr = false
        val hdrCaps = ArrayList<String>()
        var wideGamut = false
        var builtIn = true
        try {
            val disp = if (
                android.os.Build.VERSION.SDK_INT >= 30
            ) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            if (disp != null) {
                try {
                    val pt = android.graphics.Point()
                    @Suppress("DEPRECATION")
                    disp.getRealSize(pt)
                    wPx = pt.x
                    hPx = pt.y
                } catch (_: Exception) {
                }
                try {
                    refreshNow = disp.refreshRate
                } catch (_: Exception) {
                }
                try {
                    for (m in disp.supportedModes) {
                        refreshAll.add(
                            m.refreshRate.toDouble(),
                        )
                    }
                } catch (_: Exception) {
                }
                try {
                    hdr = disp.isHdr
                } catch (_: Exception) {
                }
                try {
                    val hc = disp.hdrCapabilities
                    if (hc != null) {
                        for (t in hc.supportedHdrTypes) {
                            when (t) {
                                android.view.Display.HdrCapabilities
                                    .HDR_TYPE_DOLBY_VISION ->
                                    hdrCaps.add("Dolby Vision")
                                android.view.Display.HdrCapabilities
                                    .HDR_TYPE_HDR10 ->
                                    hdrCaps.add("HDR10")
                                android.view.Display.HdrCapabilities
                                    .HDR_TYPE_HLG ->
                                    hdrCaps.add("HLG")
                                android.view.Display.HdrCapabilities
                                    .HDR_TYPE_HDR10_PLUS ->
                                    hdrCaps.add("HDR10+")
                            }
                        }
                    }
                } catch (_: Exception) {
                }
                try {
                    wideGamut = disp.isWideColorGamut
                } catch (_: Exception) {
                }
                try {
                    // No getType() API exists: display 0 is the
                    // built-in panel on phones.
                    builtIn = disp.displayId ==
                        android.view.Display.DEFAULT_DISPLAY
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        try {
            val dm = resources.displayMetrics
            densityDpi = dm.densityDpi
            xdpi = dm.xdpi
            ydpi = dm.ydpi
            fontScale = resources.configuration.fontScale
        } catch (_: Exception) {
        }
        var bright = -1
        var brightMode: String? = null
        var timeoutMs = -1L
        try {
            val cr = contentResolver
            bright = android.provider.Settings.System.getInt(
                cr,
                android.provider.Settings.System.SCREEN_BRIGHTNESS,
                -1,
            )
            val mode = android.provider.Settings.System.getInt(
                cr,
                android.provider.Settings.System
                    .SCREEN_BRIGHTNESS_MODE,
                -1,
            )
            brightMode = when (mode) {
                android.provider.Settings.System
                    .SCREEN_BRIGHTNESS_MODE_AUTOMATIC ->
                    "Automatic"
                android.provider.Settings.System
                    .SCREEN_BRIGHTNESS_MODE_MANUAL ->
                    "Manual"
                else -> null
            }
            timeoutMs = android.provider.Settings.System.getLong(
                cr,
                android.provider.Settings.System.SCREEN_OFF_TIMEOUT,
                -1L,
            )
        } catch (_: Exception) {
        }
        var orient = "—"
        try {
            orient = when (
                resources.configuration.orientation
            ) {
                android.content.res.Configuration
                    .ORIENTATION_PORTRAIT -> "Portrait"
                android.content.res.Configuration
                    .ORIENTATION_LANDSCAPE -> "Landscape"
                android.content.res.Configuration
                    .ORIENTATION_SQUARE -> "Square"
                else -> "—"
            }
        } catch (_: Exception) {
        }
        return mapOf(
            "wPx" to wPx,
            "hPx" to hPx,
            "densityDpi" to densityDpi,
            "fontScale" to fontScale.toDouble(),
            "xdpi" to xdpi.toDouble(),
            "ydpi" to ydpi.toDouble(),
            "refreshNow" to refreshNow.toDouble(),
            "refreshAll" to refreshAll.distinct().sorted(),
            "hdr" to hdr,
            "hdrCaps" to hdrCaps,
            "wideGamut" to wideGamut,
            "builtIn" to builtIn,
            "brightness" to bright,
            "brightnessMode" to brightMode,
            "timeoutMs" to timeoutMs,
            "orientation" to orient,
        )
    }

    /// Thermal zones 0..199 (stops after 8 consecutive missing) +
    /// PowerManager thermal status (API 29+). Millidegrees → °C.
    private fun collectThermalInfo(): Map<String, Any> {
        val sensors = ArrayList<Map<String, Any>>()
        var missing = 0
        for (i in 0 until 200) {
            val base = "/sys/class/thermal/thermal_zone$i"
            try {
                val type = java.io.File("$base/type")
                    .readText().trim()
                val raw = java.io.File("$base/temp")
                    .readText().trim().toLong()
                if (type.isEmpty()) {
                    missing++
                } else {
                    missing = 0
                    val row = HashMap<String, Any>()
                    row["name"] = type
                    row["tempC"] = raw / 1000.0
                    sensors.add(row)
                }
            } catch (_: Exception) {
                missing++
            }
            if (missing >= 8) break
        }
        var status = -1
        try {
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                val pm = getSystemService(POWER_SERVICE)
                    as? android.os.PowerManager
                status = pm?.currentThermalStatus
                    ?: -1
            }
        } catch (_: Exception) {
        }
        return mapOf("status" to status, "sensors" to sensors)
    }

    /// Manifest components of one visible package for the Apps
    /// detail sheet (permissions/activities/services/receivers/
    /// providers as plain string lists).
    private fun collectAppDetail(pkg: String): Map<String, Any> {
        val pm = packageManager
        @Suppress("DEPRECATION")
        val pi = pm.getPackageInfo(
            pkg,
            android.content.pm.PackageManager.GET_ACTIVITIES or
                android.content.pm.PackageManager.GET_SERVICES or
                android.content.pm.PackageManager.GET_RECEIVERS or
                android.content.pm.PackageManager.GET_PROVIDERS or
                android.content.pm.PackageManager.GET_PERMISSIONS,
        )
        fun strs(arr: Array<out String>?): List<String> {
            return arr?.toList() ?: emptyList()
        }
        return mapOf(
            "permissions" to strs(pi.requestedPermissions),
            "activities" to
                (pi.activities?.map { it.name } ?: emptyList()),
            "services" to
                (pi.services?.map { it.name } ?: emptyList()),
            "receivers" to
                (pi.receivers?.map { it.name } ?: emptyList()),
            "providers" to
                (pi.providers?.map { it.authority } ?: emptyList()),
        )
    }

    private fun openAppSettings(pkg: String): Boolean {
        return try {
            val intent = android.content.Intent(
                android.provider.Settings
                    .ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:$pkg"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun launchApp(pkg: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(pkg)
                ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /// Copies base.apk (+splits) to external-files/ExtractedAPKs for
    /// sharing. Returns the absolute path of the main copy.
    private fun extractApk(pkg: String): String {
        val pi = packageManager.getPackageInfo(pkg, 0)
        val ai = pi.applicationInfo ?: throw IllegalStateException(
            "no app info",
        )
        val outDir = java.io.File(
            getExternalFilesDir(null), "ExtractedAPKs",
        )
        if (!outDir.exists()) outDir.mkdirs()
        val safeLabel = (packageManager.getApplicationLabel(ai)
            ?.toString() ?: pkg)
            .replace(Regex("[^A-Za-z0-9._-]+"), "_")
            .take(48)
        fun copyApk(src: String?, name: String): java.io.File? {
            if (src.isNullOrEmpty()) return null
            val f = java.io.File(src)
            if (!f.exists()) return null
            val dst = java.io.File(outDir, name)
            f.inputStream().use { inp ->
                dst.outputStream().use { out ->
                    inp.copyTo(out)
                }
            }
            return dst
        }
        val main = copyApk(ai.sourceDir, "$safeLabel.apk")
            ?: throw IllegalStateException("base APK missing")
        try {
            val splits = ai.splitSourceDirs
            if (splits != null) {
                for ((i, s) in splits.withIndex()) {
                    copyApk(s, "${safeLabel}_split$i.apk")
                }
            }
        } catch (_: Exception) {
        }
        return main.absolutePath
    }

    /// Visible installed packages with icons, versions, SDK levels,
    /// timestamps and APK bytes. Sorted by label.
    private fun collectAppList(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            val pm = packageManager
            val pkgs = pm.getInstalledPackages(0)
            for (pi in pkgs) {
                try {
                    val pkg = pi.packageName ?: continue
                    val ai = pi.applicationInfo ?: continue
                    val label = try {
                        pm.getApplicationLabel(ai)?.toString()
                            ?: pkg
                    } catch (_: Exception) {
                        pkg
                    }
                    val version = try {
                        pi.versionName ?: "—"
                    } catch (_: Exception) {
                        "—"
                    }
                    val vcode: Long = try {
                        if (android.os.Build.VERSION.SDK_INT >= 28) {
                            pi.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pi.versionCode.toLong()
                        }
                    } catch (_: Exception) {
                        -1L
                    }
                    val targetSdk = try {
                        ai.targetSdkVersion
                    } catch (_: Exception) {
                        0
                    }
                    val minSdk = try {
                        if (android.os.Build.VERSION.SDK_INT >= 24) {
                            ai.minSdkVersion
                        } else {
                            0
                        }
                    } catch (_: Exception) {
                        0
                    }
                    val isSystem = (ai.flags and
                        android.content.pm.ApplicationInfo
                            .FLAG_SYSTEM) != 0
                    var apkBytes = 0L
                    try {
                        apkBytes += java.io.File(ai.sourceDir).length()
                        val splits = ai.splitSourceDirs
                        if (splits != null) {
                            for (s in splits) {
                                try {
                                    apkBytes +=
                                        java.io.File(s).length()
                                } catch (_: Exception) {
                                }
                            }
                        }
                    } catch (_: Exception) {
                    }
                    val installer = try {
                        @Suppress("DEPRECATION")
                        pm.getInstallerPackageName(pkg)
                    } catch (_: Exception) {
                        null
                    }
                    var icon: ByteArray? = null
                    try {
                        val dr = pm.getApplicationIcon(ai)
                        val bmp = android.graphics.Bitmap
                            .createBitmap(
                                96, 96,
                                android.graphics.Bitmap.Config
                                    .ARGB_8888,
                            )
                        val cv = android.graphics.Canvas(bmp)
                        dr.setBounds(0, 0, 96, 96)
                        dr.draw(cv)
                        val bos =
                            java.io.ByteArrayOutputStream()
                        bmp.compress(
                            android.graphics.Bitmap.CompressFormat
                                .PNG,
                            100, bos,
                        )
                        icon = bos.toByteArray()
                        bmp.recycle()
                    } catch (_: Exception) {
                    }
                    val row = HashMap<String, Any?>()
                    row["package"] = pkg
                    row["label"] = label
                    row["version"] = version
                    row["versionCode"] = vcode
                    row["targetSdk"] = targetSdk
                    row["minSdk"] = minSdk
                    row["firstInstall"] = try {
                        pi.firstInstallTime
                    } catch (_: Exception) {
                        0L
                    }
                    row["lastUpdate"] = try {
                        pi.lastUpdateTime
                    } catch (_: Exception) {
                        0L
                    }
                    row["installer"] = installer
                    row["isSystem"] = isSystem
                    row["apkBytes"] = apkBytes
                    if (icon != null) row["icon"] = icon!!
                    out.add(row)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        out.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return out
    }

    private fun <T> camChar(
        c: CamChars,
        key: CamChars.Key<T>,
    ): T? {
        return try {
            c.get(key)
        } catch (_: Exception) {
            null
        }
    }

    /// Camera2 characteristics per camera id for the Camera tab.
    private fun collectCameraInfo(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            val cm = getSystemService(CAMERA_SERVICE)
                as? android.hardware.camera2.CameraManager
                ?: return out
            for (id in cm.cameraIdList) {
                try {
                    val c = cm.getCameraCharacteristics(id)
                                        fun ints(
                        key: android.hardware.camera2.CameraCharacteristics
                            .Key<IntArray>,
                    ): List<Int> {
                        return camChar(c, key)?.toList()
                            ?: emptyList()
                    }
                    val facing = camChar(c, CamChars.LENS_FACING) ?: -1
                    // JPEG output sizes, largest first.
                    var sizes = emptyList<String>()
                    var maxW = 0
                    var maxH = 0
                    try {
                        val map = camChar(
                            c,
                            CamChars.SCALER_STREAM_CONFIGURATION_MAP,
                        )
                        val arr = map?.getOutputSizes(
                            android.graphics.ImageFormat.JPEG,
                        )
                        if (arr != null) {
                            val sorted = arr.sortedByDescending {
                                it.width * it.height
                            }
                            sizes = sorted.map {
                                "${it.width} x ${it.height}"
                            }
                            if (sorted.isNotEmpty()) {
                                maxW = sorted[0].width
                                maxH = sorted[0].height
                            }
                        }
                    } catch (_: Exception) {
                    }
                    val mp = if (maxW > 0 && maxH > 0) {
                        (maxW * maxH / 1000000.0)
                    } else {
                        -1.0
                    }
                    // Physical sensor size mm.
                    var sensorSize = ""
                    try {
                        val s = camChar(
                            c, CamChars.SENSOR_INFO_PHYSICAL_SIZE,
                        )
                        if (s != null) {
                            sensorSize =
                                "${"%.2f".format(s.width)} x " +
                                "${"%.2f".format(s.height)}"
                        }
                    } catch (_: Exception) {
                    }
                    var pixelArray = ""
                    try {
                        val s = camChar(
                            c, CamChars.SENSOR_INFO_PIXEL_ARRAY_SIZE,
                        )
                        if (s != null) {
                            pixelArray = "${s.width} x ${s.height}"
                        }
                    } catch (_: Exception) {
                    }
                    fun f1(
                        key: android.hardware.camera2.CameraCharacteristics
                            .Key<FloatArray>,
                    ): List<Double> {
                        return try {
                            camChar(c, key)?.map { it.toDouble() }
                                ?: emptyList()
                        } catch (_: Exception) {
                            emptyList()
                        }
                    }
                    val focals = f1(CamChars.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                    val apertures = f1(CamChars.LENS_INFO_AVAILABLE_APERTURES)
                    val ndDens = f1(
                        CamChars.LENS_INFO_AVAILABLE_FILTER_DENSITIES,
                    )
                    var thumbs = emptyList<String>()
                    try {
                        val arr = camChar(
                            c, CamChars.JPEG_AVAILABLE_THUMBNAIL_SIZES,
                        )
                        if (arr != null) {
                            thumbs = arr.map {
                                "${it.width} x ${it.height}"
                            }
                        }
                    } catch (_: Exception) {
                    }
                    val flash = try {
                        camChar(c, CamChars.FLASH_INFO_AVAILABLE) ?: false
                    } catch (_: Exception) {
                        false
                    }
                    // Three separate Integer keys (processed, raw,
                    // stalling) — kept in the Dart-expected order.
                    var streams = emptyList<Int>()
                    try {
                        val proc = camChar(
                            c,
                            CamChars.REQUEST_MAX_NUM_OUTPUT_PROC,
                        ) ?: -1
                        val raw = camChar(
                            c,
                            CamChars.REQUEST_MAX_NUM_OUTPUT_RAW,
                        ) ?: -1
                        val stall = camChar(
                            c,
                            CamChars
                                .REQUEST_MAX_NUM_OUTPUT_PROC_STALLING,
                        ) ?: -1
                        streams = listOf(proc, raw, stall)
                    } catch (_: Exception) {
                    }
                    val m = HashMap<String, Any?>()
                    m["id"] = id
                    m["facing"] = facing // 0 back, 1 front, 2 external
                    m["maxW"] = maxW
                    m["maxH"] = maxH
                    m["mp"] = mp
                    m["sizes"] = sizes
                    m["sensorSize"] = sensorSize
                    m["pixelArray"] = pixelArray
                    m["focals"] = focals
                    m["apertures"] = apertures
                    m["ndDensities"] = ndDens
                    m["thumbs"] = thumbs
                    m["flash"] = flash
                    m["hwLevel"] = camChar(c, CamChars.INFO_SUPPORTED_HARDWARE_LEVEL)
                    m["aeModes"] = ints(CamChars.CONTROL_AE_AVAILABLE_MODES)
                    m["afModes"] = ints(CamChars.CONTROL_AF_AVAILABLE_MODES)
                    m["awbModes"] = ints(CamChars.CONTROL_AWB_AVAILABLE_MODES)
                    m["aeRegions"] =
                        camChar(c, CamChars.CONTROL_MAX_REGIONS_AE)
                    m["afRegions"] =
                        camChar(c, CamChars.CONTROL_MAX_REGIONS_AF)
                    m["awbRegions"] =
                        camChar(c, CamChars.CONTROL_MAX_REGIONS_AWB)
                    m["edgeModes"] = ints(CamChars.EDGE_AVAILABLE_EDGE_MODES)
                    m["noiseModes"] = ints(
                        CamChars.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES,
                    )
                    m["hotPixelModes"] = ints(
                        CamChars.HOT_PIXEL_AVAILABLE_HOT_PIXEL_MODES,
                    )
                    m["aberrModes"] = ints(
                        CamChars.COLOR_CORRECTION_AVAILABLE_ABERRATION_MODES,
                    )
                    m["effects"] = ints(CamChars.CONTROL_AVAILABLE_EFFECTS)
                    m["scenes"] = ints(CamChars.CONTROL_AVAILABLE_SCENE_MODES)
                    m["stabModes"] = ints(
                        CamChars.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
                    )
                    m["faceModes"] = ints(
                        CamChars.STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES,
                    )
                    m["testPatterns"] = ints(
                        CamChars.SENSOR_AVAILABLE_TEST_PATTERN_MODES,
                    )
                    m["cfa"] = camChar(
                        c, CamChars.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT,
                    )
                    m["timestampSrc"] = camChar(
                        c, CamChars.SENSOR_INFO_TIMESTAMP_SOURCE,
                    )
                    m["orientation"] =
                        camChar(c, CamChars.SENSOR_ORIENTATION)
                    m["focusCalib"] = camChar(
                        c, CamChars.LENS_INFO_FOCUS_DISTANCE_CALIBRATION,
                    )
                    m["ois"] = try {
                        camChar(
                            c,
                            CamChars.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION,
                        )?.toList()
                    } catch (_: Exception) {
                        null
                    }
                    m["caps"] = ints(CamChars.REQUEST_AVAILABLE_CAPABILITIES)
                    m["partialResults"] = camChar(
                        c, CamChars.REQUEST_PARTIAL_RESULT_COUNT,
                    )
                    m["maxZoom"] = try {
                        camChar(
                            c, CamChars.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM,
                        )?.toDouble()
                    } catch (_: Exception) {
                        null
                    }
                    m["cropType"] = camChar(
                        c, CamChars.SCALER_CROPPING_TYPE,
                    )
                    // AE compensation step numerator/denominator.
                    try {
                        val r = camChar(
                            c, CamChars.CONTROL_AE_COMPENSATION_STEP,
                        )
                        m["aeStep"] = if (r != null) {
                            "${r.numerator}/${r.denominator}"
                        } else {
                            null
                        }
                    } catch (_: Exception) {
                        m["aeStep"] = null
                    }
                    out.add(m)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        return out
    }

    /// Full sensor list (name/vendor/type/version/range/power).
    private fun collectSensorList(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            val sm = getSystemService(SENSOR_SERVICE)
                as? android.hardware.SensorManager
                ?: return out
            val list = sm.getSensorList(
                android.hardware.Sensor.TYPE_ALL,
            ) ?: return out
            for (s in list.sortedBy { it.name.lowercase() }) {
                val m = HashMap<String, Any?>()
                m["name"] = try {
                    s.name ?: "—"
                } catch (_: Exception) {
                    "—"
                }
                m["vendor"] = try {
                    s.vendor ?: "—"
                } catch (_: Exception) {
                    "—"
                }
                m["type"] = try {
                    s.stringType ?: "—"
                } catch (_: Exception) {
                    "—"
                }
                m["version"] = try {
                    s.version
                } catch (_: Exception) {
                    -1
                }
                m["range"] = try {
                    s.maximumRange.toDouble()
                } catch (_: Exception) {
                    -1.0
                }
                m["resolution"] = try {
                    s.resolution.toDouble()
                } catch (_: Exception) {
                    -1.0
                }
                m["power"] = try {
                    s.power.toDouble()
                } catch (_: Exception) {
                    -1.0
                }
                m["wakeup"] = try {
                    s.isWakeUpSensor
                } catch (_: Exception) {
                    false
                }
                m["minDelayUs"] = try {
                    s.minDelay
                } catch (_: Exception) {
                    -1
                }
                m["maxDelayUs"] = try {
                    s.maxDelay
                } catch (_: Exception) {
                    -1
                }
                m["fifoMax"] = try {
                    s.fifoMaxEventCount
                } catch (_: Exception) {
                    0
                }
                m["fifoReserved"] = try {
                    s.fifoReservedEventCount
                } catch (_: Exception) {
                    0
                }
                m["reportingMode"] = try {
                    s.reportingMode
                } catch (_: Exception) {
                    -1
                }
                out.add(m)
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun openBtSettings(): Boolean {
        return try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_BLUETOOTH_SETTINGS,
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /// Radio capability bundle for the Connectivity tab. Every lookup
    /// is guarded — null means "could not determine" (often a missing
    /// runtime permission the app deliberately does not request).
    private fun collectConnInfo(): Map<String, Any?> {
        val pm = packageManager
        fun feat(name: String): Boolean {
            return try {
                pm.hasSystemFeature(name)
            } catch (_: Exception) {
                false
            }
        }
        // Wi-Fi device generation (best supported standard).
        var wifiGen: String? = null
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE)
                as? android.net.wifi.WifiManager
            if (wm != null &&
                android.os.Build.VERSION.SDK_INT >= 30
            ) {
                val order = listOf(
                    8 to "Wi-Fi 7",
                    7 to "Wi-Fi 6",
                    5 to "Wi-Fi 5",
                    4 to "Wi-Fi 4",
                )
                for ((std, label) in order) {
                    try {
                        if (wm.isWifiStandardSupported(std)) {
                            wifiGen = label
                            break
                        }
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
        val wifiDirect =
            feat(android.content.pm.PackageManager.FEATURE_WIFI_DIRECT)
        // Bands from the radio itself (WifiManager), not the feature
        // strings — hasSystemFeature(band.5ghz) lies on some MIUI
        // builds. Falls back to feature strings when unavailable.
        var band5: Boolean? = null
        var band6: Boolean? = null
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE)
                as? android.net.wifi.WifiManager
            if (wm != null &&
                android.os.Build.VERSION.SDK_INT >= 29
            ) {
                try {
                    band5 = wm.is5GHzBandSupported
                } catch (_: Exception) {
                }
                try {
                    band6 = wm.is6GHzBandSupported
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        if (band5 == null) {
            band5 = feat("android.hardware.wifi.band.5ghz")
        }
        if (band6 == null) {
            band6 = feat("android.hardware.wifi.band.6ghz")
        }
        // Bluetooth presence + state + LE capabilities.
        val btPresent = feat(
            android.content.pm.PackageManager.FEATURE_BLUETOOTH,
        )
        val btLe = feat(
            android.content.pm.PackageManager.FEATURE_BLUETOOTH_LE,
        )
        var btOn: Boolean? = null
        var multiAdv: Boolean? = null
        var offFilt: Boolean? = null
        var offBatch: Boolean? = null
        var le2m: Boolean? = null
        var leCoded: Boolean? = null
        var leExtAdv: Boolean? = null
        var lePeriodAdv: Boolean? = null
        try {
            @Suppress("DEPRECATION")
            val adapter = android.bluetooth.BluetoothAdapter
                .getDefaultAdapter()
            if (adapter != null) {
                try {
                    btOn = adapter.isEnabled
                } catch (_: Exception) {
                }
                try {
                    multiAdv = adapter.isMultipleAdvertisementSupported
                } catch (_: Exception) {
                }
                try {
                    offFilt = adapter.isOffloadedFilteringSupported
                } catch (_: Exception) {
                }
                try {
                    offBatch =
                        adapter.isOffloadedScanBatchingSupported
                } catch (_: Exception) {
                }
                try {
                    le2m = adapter.isLe2MPhySupported
                } catch (_: Exception) {
                }
                try {
                    leCoded = adapter.isLeCodedPhySupported
                } catch (_: Exception) {
                }
                try {
                    leExtAdv =
                        adapter.isLeExtendedAdvertisingSupported
                } catch (_: Exception) {
                }
                try {
                    lePeriodAdv =
                        adapter.isLePeriodicAdvertisingSupported
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        // NFC presence + state.
        val nfcPresent = feat(
            android.content.pm.PackageManager.FEATURE_NFC,
        )
        var nfcOn: Boolean? = null
        if (nfcPresent) {
            try {
                nfcOn = android.nfc.NfcAdapter.getDefaultAdapter(this)
                    ?.isEnabled
            } catch (_: Exception) {
            }
        }
        val uwb = feat("android.hardware.uwb")
        val usbHost = feat(
            android.content.pm.PackageManager.FEATURE_USB_HOST,
        )
        val usbAcc = feat(
            android.content.pm.PackageManager.FEATURE_USB_ACCESSORY,
        )
        var adbOn: Boolean? = null
        try {
            adbOn = android.provider.Settings.Global.getInt(
                contentResolver,
                android.provider.Settings.Global.ADB_ENABLED, 0,
            ) == 1
        } catch (_: Exception) {
        }
        return mapOf(
            "wifiGen" to wifiGen,
            "wifiDirect" to wifiDirect,
            "band5" to band5,
            "band6" to band6,
            "btPresent" to btPresent,
            "btLe" to btLe,
            "btOn" to btOn,
            "multiAdv" to multiAdv,
            "offFilt" to offFilt,
            "offBatch" to offBatch,
            "le2m" to le2m,
            "leCoded" to leCoded,
            "leExtAdv" to leExtAdv,
            "lePeriodAdv" to lePeriodAdv,
            "nfcPresent" to nfcPresent,
            "nfcOn" to nfcOn,
            "uwb" to uwb,
            "usbHost" to usbHost,
            "usbAcc" to usbAcc,
            "adbOn" to adbOn,
        )
    }

    /// Opens the system Data Usage screen (Usage button), trying the
    /// data-usage entry first, then operator and wireless settings.
    /// String action: no such Settings constant exists to link against.
    private fun openDataUsageSettings(): Boolean {
        val actions = listOf(
            "android.settings.DATA_USAGE_SETTINGS",
            android.provider.Settings.ACTION_NETWORK_OPERATOR_SETTINGS,
            android.provider.Settings.ACTION_WIRELESS_SETTINGS,
        )
        for (a in actions) {
            try {
                val intent = android.content.Intent(a)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun intToIp(v: Int): String {
        return "${v and 0xFF}.${(v shr 8) and 0xFF}" +
            ".${(v shr 16) and 0xFF}.${(v shr 24) and 0xFF}"
    }

    /// Wi-Fi details for the Network tab. SSID/BSSID are deliberately
    /// NOT read (they need location permission). Connection state comes
    /// from the active transport (never from WifiInfo.networkId, which
    /// throws SecurityException on some ROMs and blanked the whole
    /// tab), and every WifiManager getter is individually guarded so
    /// one throwing getter can't wipe the rest. IPv4/gateway fall back
    /// to LinkProperties when WifiManager is gated.
    private fun collectWifiInfo(): Map<String, Any> {
        var transport = "NONE"
        try {
            transport = activeNetworkType()
        } catch (_: Exception) {
        }
        val wifiUp = transport == "WIFI"
        var ip = "—"
        var ipv6 = "—"
        var gateway = "—"
        var mask = "—"
        var prefix = -1
        var dns = "—"
        var lease = "—"
        var iface = "—"
        var linkMbps = -1
        var freqMhz = -1
        var standard = -1 // WifiInfo.WIFI_STANDARD_*
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE)
                as? android.net.wifi.WifiManager
            val info = try {
                wm?.connectionInfo
            } catch (_: Exception) {
                null
            }
            if (info != null) {
                try {
                    val rawIp = info.ipAddress
                    if (rawIp != 0) ip = intToIp(rawIp)
                } catch (_: Exception) {
                }
                try {
                    linkMbps = info.linkSpeed
                } catch (_: Exception) {
                }
                try {
                    freqMhz = info.frequency
                } catch (_: Exception) {
                }
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    try {
                        standard = info.wifiStandard
                    } catch (_: Exception) {
                    }
                }
                if (wifiUp) {
                    val dhcp = try {
                        wm?.dhcpInfo
                    } catch (_: Exception) {
                        null
                    }
                    if (dhcp != null) {
                        try {
                            if (dhcp.gateway != 0) {
                                gateway = intToIp(dhcp.gateway)
                            }
                        } catch (_: Exception) {
                        }
                        try {
                            if (dhcp.netmask != 0) {
                                mask = intToIp(dhcp.netmask)
                            }
                        } catch (_: Exception) {
                        }
                        try {
                            if (dhcp.dns1 != 0) {
                                dns = intToIp(dhcp.dns1)
                            }
                        } catch (_: Exception) {
                        }
                        try {
                            if (dhcp.leaseDuration != 0) {
                                lease =
                                    dhcp.leaseDuration.toString()
                            }
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }
        var ip4 = ""
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE)
                as? android.net.ConnectivityManager
            val props = cm?.getLinkProperties(cm.activeNetwork)
            if (props != null) {
                iface = props.interfaceName ?: "—"
                for (la in props.linkAddresses) {
                    val addr = la.address.hostAddress ?: continue
                    if (addr.contains(":")) {
                        if (ipv6 == "—") {
                            val pct = addr.indexOf('%')
                            ipv6 = if (pct > 0) {
                                addr.substring(0, pct)
                            } else {
                                addr
                            }
                        }
                    } else if (ip4.isEmpty() &&
                        !addr.startsWith("127.")
                    ) {
                        ip4 = addr
                        if (prefix < 0) prefix = la.prefixLength
                    }
                }
                if (dns == "—") {
                    val d = props.dnsServers.firstOrNull()
                        ?.hostAddress
                    if (!d.isNullOrEmpty()) dns = d
                }
                if (mask == "—" && prefix > 0 && prefix <= 32) {
                    val bits = (0xFFFFFFFFL shl (32 - prefix)) and
                        0xFFFFFFFFL
                    mask = intToIp(bits.toInt())
                }
            }
        } catch (_: Exception) {
        }
        if (ip == "—" && ip4.isNotEmpty()) ip = ip4
        return mapOf(
            "connected" to wifiUp,
            "ip" to ip,
            "ipv6" to ipv6,
            "gateway" to gateway,
            "mask" to mask,
            "prefix" to prefix,
            "dns" to dns,
            "leaseSec" to lease,
            "iface" to iface,
            "linkMbps" to linkMbps,
            "freqMhz" to freqMhz,
            "standard" to standard,
        )
    }

    private fun hasUsageAccess(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE)
                as? android.app.ActivityManager
                ?: return false
            val mode = if (android.os.Build.VERSION.SDK_INT >= 29) {
                (getSystemService(Context.APP_OPS_SERVICE)
                    as? android.app.AppOpsManager)
                    ?.unsafeCheckOpNoThrow(
                        android.app.AppOpsManager
                            .OPSTR_GET_USAGE_STATS,
                        android.os.Process.myUid(),
                        packageName,
                    )
            } else {
                @Suppress("DEPRECATION")
                (getSystemService(Context.APP_OPS_SERVICE)
                    as? android.app.AppOpsManager)
                    ?.checkOpNoThrow(
                        android.app.AppOpsManager
                            .OPSTR_GET_USAGE_STATS,
                        android.os.Process.myUid(),
                        packageName,
                    )
            }
            mode ==
                android.app.AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    private fun openUsageAccessSettings(): Boolean {
        return try {
            val intent = android.content.Intent(
                android.provider.Settings
                    .ACTION_USAGE_ACCESS_SETTINGS,
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun trafficManager()
            : android.app.usage.NetworkStatsManager? {
        return try {
            getSystemService(Context.NETWORK_STATS_SERVICE)
                as? android.app.usage.NetworkStatsManager
        } catch (_: Exception) {
            null
        }
    }

    /// Device totals in [startMs, endMs], split by transport.
    /// Uses the int-based overloads (android.net.NetworkTemplate no
    /// longer exists in current compile SDKs).
    private fun collectTrafficSummary(
        startMs: Long,
        endMs: Long,
    ): Map<String, Any> {
        val nsm = trafficManager()
            ?: throw IllegalStateException("no NetworkStatsManager")
        val wifi = nsm.querySummaryForDevice(
            android.net.ConnectivityManager.TYPE_WIFI,
            null, startMs, endMs,
        )
        val mob = nsm.querySummaryForDevice(
            android.net.ConnectivityManager.TYPE_MOBILE,
            null, startMs, endMs,
        )
        val wifiRx = wifi.rxBytes
        val wifiTx = wifi.txBytes
        val mobileRx = mob.rxBytes
        val mobileTx = mob.txBytes
        val rx = wifiRx + mobileRx
        val tx = wifiTx + mobileTx
        return mapOf(
            "rx" to rx,
            "tx" to tx,
            "wifiRx" to wifiRx,
            "wifiTx" to wifiTx,
            "mobileRx" to mobileRx,
            "mobileTx" to mobileTx,
        )
    }

    /// Per launcher-app totals in [startMs, endMs] with icons.
    /// One querySummary per transport gives per-UID buckets; UIDs map
    /// back to packages, launcher-visible ones resolve label + icon.
    /// No QUERY_ALL_PACKAGES. Icons are 96px PNG bytes.
    private fun collectTrafficApps(
        startMs: Long,
        endMs: Long,
    ): List<Map<String, Any>> {
        val nsm = trafficManager()
            ?: throw IllegalStateException("no NetworkStatsManager")
        val pm = packageManager
        data class Quad(var wrx: Long, var wtx: Long,
            var mrx: Long, var mtx: Long)
        val byUid = HashMap<Int, Quad>()
        val wifiT = android.net.ConnectivityManager.TYPE_WIFI
        val mobT = android.net.ConnectivityManager.TYPE_MOBILE
        var s = nsm.querySummary(wifiT, null, startMs, endMs)
        try {
            while (s.hasNextBucket()) {
                val b = android.app.usage.NetworkStats.Bucket()
                s.getNextBucket(b)
                val q = byUid.getOrPut(b.uid) {
                    Quad(0, 0, 0, 0)
                }
                q.wrx += b.rxBytes
                q.wtx += b.txBytes
            }
        } finally {
            try {
                s.close()
            } catch (_: Exception) {
            }
        }
        s = nsm.querySummary(mobT, null, startMs, endMs)
        try {
            while (s.hasNextBucket()) {
                val b = android.app.usage.NetworkStats.Bucket()
                s.getNextBucket(b)
                val q = byUid.getOrPut(b.uid) {
                    Quad(0, 0, 0, 0)
                }
                q.mrx += b.rxBytes
                q.mtx += b.txBytes
            }
        } finally {
            try {
                s.close()
            } catch (_: Exception) {
            }
        }
        val out = ArrayList<Map<String, Any>>(byUid.size)
        for ((uid, q) in byUid) {
            if (uid < 10000) continue // system uids, not apps
            if (q.wrx + q.wtx + q.mrx + q.mtx <= 0) continue
            val pkgs = try {
                pm.getPackagesForUid(uid)
            } catch (_: Exception) {
                null
            } ?: continue
            // First launcher-visible package wins.
            var pkg: String? = null
            for (p in pkgs) {
                try {
                    if (pm.getLaunchIntentForPackage(p) != null) {
                        pkg = p
                        break
                    }
                } catch (_: Exception) {
                }
            }
            val name = pkg ?: continue
            val label = try {
                val ai = pm.getApplicationInfo(name, 0)
                pm.getApplicationLabel(ai)?.toString() ?: name
            } catch (_: Exception) {
                name
            }
            var icon: ByteArray? = null
            try {
                val ai = pm.getApplicationInfo(name, 0)
                val dr = pm.getApplicationIcon(ai)
                val bmp = android.graphics.Bitmap.createBitmap(
                    96, 96,
                    android.graphics.Bitmap.Config.ARGB_8888,
                )
                val cv = android.graphics.Canvas(bmp)
                dr.setBounds(0, 0, 96, 96)
                dr.draw(cv)
                val bos = java.io.ByteArrayOutputStream()
                bmp.compress(
                    android.graphics.Bitmap.CompressFormat.PNG,
                    100, bos,
                )
                icon = bos.toByteArray()
                bmp.recycle()
            } catch (_: Exception) {
            }
            val row = HashMap<String, Any>()
            row["package"] = name
            row["label"] = label
            if (icon != null) row["icon"] = icon!!
            row["rx"] = q.wrx + q.mrx
            row["tx"] = q.wtx + q.mtx
            row["wifiRx"] = q.wrx
            row["wifiTx"] = q.wtx
            row["mobileRx"] = q.mrx
            row["mobileTx"] = q.mtx
            out.add(row)
        }
        out.sortByDescending {
            ((it["rx"] as Long) + (it["tx"] as Long))
        }
        return out
    }

    /// Since-boot totals, no permission needed (fallback page state).
    /// TrafficStats needs no permission; explicit call syntax is used
    /// (property syntax fails to resolve on this toolchain).
    private fun collectTrafficBoot(): Map<String, Any> {
        fun nz(v: Long): Long {
            return try {
                if (v ==
                    android.net.TrafficStats.UNSUPPORTED.toLong()
                ) {
                    0L
                } else {
                    v
                }
            } catch (_: Exception) {
                0L
            }
        }
        return try {
            val rx = nz(android.net.TrafficStats.getTotalRxBytes())
            val tx = nz(android.net.TrafficStats.getTotalTxBytes())
            val mrx = nz(android.net.TrafficStats.getMobileRxBytes())
            val mtx = nz(android.net.TrafficStats.getMobileTxBytes())
            mapOf(
                "rx" to rx,
                "tx" to tx,
                "wifiRx" to (rx - mrx).coerceAtLeast(0L),
                "wifiTx" to (tx - mtx).coerceAtLeast(0L),
                "mobileRx" to mrx,
                "mobileTx" to mtx,
            )
        } catch (_: Exception) {
            mapOf(
                "rx" to 0L, "tx" to 0L,
                "wifiRx" to 0L, "wifiTx" to 0L,
                "mobileRx" to 0L, "mobileTx" to 0L,
            )
        }
    }

    private fun readKhz(path: String): Int {
        return try {
            (java.io.File(path).readText().trim().toLong() / 1000L)
                .toInt()
        } catch (_: Exception) {
            -1
        }
    }

    /// CPU tab bundle: per-core min/max MHz, scaling governor, and an
    /// EGL pbuffer probe for renderer/vendor/version strings.
    private fun collectCpuInfo(): Map<String, Any> {
        val cores = try {
            Runtime.getRuntime().availableProcessors()
        } catch (_: Exception) {
            0
        }
        val maxF = ArrayList<Int>(cores)
        val minF = ArrayList<Int>(cores)
        for (i in 0 until cores) {
            maxF.add(
                readKhz(
                    "/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq",
                ),
            )
            minF.add(
                readKhz(
                    "/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_min_freq",
                ),
            )
        }
        var governor = "—"
        try {
            governor = java.io.File(
                "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
            ).readText().trim().ifEmpty { "—" }
        } catch (_: Exception) {
        }
        var eglRenderer = "—"
        var eglVendor = "—"
        var eglVersion = "—"
        try {
            val dpy = android.opengl.EGL14.eglGetDisplay(
                android.opengl.EGL14.EGL_DEFAULT_DISPLAY,
            )
            val ver = IntArray(2)
            if (android.opengl.EGL14.eglInitialize(dpy, ver, 0, ver, 1)) {
                val cfgAttr = intArrayOf(
                    android.opengl.EGL14.EGL_RENDERABLE_TYPE,
                    android.opengl.EGL14.EGL_OPENGL_ES2_BIT,
                    android.opengl.EGL14.EGL_SURFACE_TYPE,
                    android.opengl.EGL14.EGL_PBUFFER_BIT,
                    android.opengl.EGL14.EGL_RED_SIZE, 8,
                    android.opengl.EGL14.EGL_GREEN_SIZE, 8,
                    android.opengl.EGL14.EGL_BLUE_SIZE, 8,
                    android.opengl.EGL14.EGL_NONE,
                )
                val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
                val n = IntArray(1)
                android.opengl.EGL14.eglChooseConfig(
                    dpy, cfgAttr, 0, configs, 0, 1, n, 0,
                )
                if (n[0] > 0 && configs[0] != null) {
                    val surfAttr = intArrayOf(
                        android.opengl.EGL14.EGL_WIDTH, 64,
                        android.opengl.EGL14.EGL_HEIGHT, 64,
                        android.opengl.EGL14.EGL_NONE,
                    )
                    val surf = android.opengl.EGL14
                        .eglCreatePbufferSurface(
                            dpy, configs[0], surfAttr, 0,
                        )
                    val ctxAttr = intArrayOf(
                        android.opengl.EGL14.EGL_CONTEXT_CLIENT_VERSION,
                        2,
                        android.opengl.EGL14.EGL_NONE,
                    )
                    val ctx = android.opengl.EGL14.eglCreateContext(
                        dpy, configs[0],
                        android.opengl.EGL14.EGL_NO_CONTEXT,
                        ctxAttr, 0,
                    )
                    if (android.opengl.EGL14.eglMakeCurrent(
                            dpy, surf, surf, ctx,
                        )
                    ) {
                        eglRenderer = android.opengl.GLES20
                            .glGetString(
                                android.opengl.GLES20.GL_RENDERER,
                            ) ?: "—"
                        eglVendor = android.opengl.GLES20
                            .glGetString(
                                android.opengl.GLES20.GL_VENDOR,
                            ) ?: "—"
                        eglVersion = android.opengl.GLES20
                            .glGetString(
                                android.opengl.GLES20.GL_VERSION,
                            ) ?: "—"
                    }
                    android.opengl.EGL14.eglMakeCurrent(
                        dpy,
                        android.opengl.EGL14.EGL_NO_SURFACE,
                        android.opengl.EGL14.EGL_NO_SURFACE,
                        android.opengl.EGL14.EGL_NO_CONTEXT,
                    )
                    android.opengl.EGL14
                        .eglDestroySurface(dpy, surf)
                    android.opengl.EGL14
                        .eglDestroyContext(dpy, ctx)
                }
                android.opengl.EGL14.eglTerminate(dpy)
            }
        } catch (_: Exception) {
        }
        return mapOf(
            "maxFreqs" to maxF,
            "minFreqs" to minF,
            "governor" to governor,
            "eglRenderer" to eglRenderer,
            "eglVendor" to eglVendor,
            "eglVersion" to eglVersion,
        )
    }

    /// Active network transport for CubicDevice Info (WIFI/CELLULAR/
    /// ETHERNET/CONNECTED/NONE). Best effort, never throws.
    private fun activeNetworkType(): String {
        return try {
            val cm = getSystemService(CONNECTIVITY_SERVICE)
                as? android.net.ConnectivityManager
                ?: return "NONE"
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                ?: return "NONE"
            when {
                caps.hasTransport(
                    android.net.NetworkCapabilities.TRANSPORT_WIFI,
                ) -> "WIFI"
                caps.hasTransport(
                    android.net.NetworkCapabilities.TRANSPORT_CELLULAR,
                ) -> "CELLULAR"
                caps.hasTransport(
                    android.net.NetworkCapabilities.TRANSPORT_ETHERNET,
                ) -> "ETHERNET"
                else -> "CONNECTED"
            }
        } catch (_: Exception) {
            "NONE"
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleShareIntent(intent)
        installCrashFileHandler()
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importChannelName)
        // Process-exit forensics for System Logs: ApplicationExitInfo reports
        // HOW the previous process died (native crash signal, LMK kill, ANR)
        // with no logcat permission needed (own crashes only, API 30+).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, processExitChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getRecentExitReasons") {
                    result.success(recentExitReasons())
                } else if (call.method == "forensicsReady") {
                    // True when this APK contains the JVM crash-file handler
                    // (lets System Logs prove the build can capture stacks).
                    result.success(crashHandlerInstalled)
                } else {
                    result.notImplemented()
                }
            }
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
                    val subfolder = sanitizeSubfolder(call.argument<String>("subfolder") ?: "CubicLM")
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
                    val subfolder = sanitizeSubfolder(call.argument<String>("subfolder") ?: "CubicLM")
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
                "batteryLevel" -> {
                    try {
                        val bm = getSystemService(BATTERY_SERVICE) as? BatteryManager
                        result.success(bm?.getIntProperty(
                            BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1)
                    } catch (e: Exception) {
                        result.error("BATTERY_FAILED", e.message, null)
                    }
                }
                "batteryCharging" -> {
                    try {
                        val st = registerReceiver(
                            null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val s = st?.getIntExtra(
                            BatteryManager.EXTRA_STATUS, -1) ?: -1
                        result.success(s == BatteryManager.BATTERY_STATUS_CHARGING ||
                            s == BatteryManager.BATTERY_STATUS_FULL)
                    } catch (e: Exception) {
                        result.error("BATTERY_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Internal storage stats (Dart: StorageStatusBar on Explore → Local).
        // Channel "com.cubiclm.app/storage": getStorageStats -> {totalBytes, freeBytes}.
        val storageChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cubiclm.app/storage",
        )
        storageChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageStats" -> {
                    try {
                        val stat = StatFs(filesDir.path)
                        val total = stat.blockCountLong * stat.blockSizeLong
                        val free = stat.availableBlocksLong * stat.blockSizeLong
                        result.success(mapOf("totalBytes" to total, "freeBytes" to free))
                    } catch (e: Exception) {
                        result.error("STATFS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Device telemetry for CubicDevice Info (Dart: DeviceExtraService).
        // Channel "com.cubiclm.app/device": cpuFreqsMHz -> [Int] (-1
        // unknown), sensorCount -> Int, appCount -> Int (best effort on
        // API 30+ without QUERY_ALL_PACKAGES), battVoltageMv -> Int,
        // battTempC -> Double, battHealth/battTech -> String,
        // uptimeMs -> Long, kernelVersion -> String, networkType ->
        // WIFI|CELLULAR|ETHERNET|NONE.
        val deviceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cubiclm.app/device",
        )
        deviceChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "cpuFreqsMHz" -> {
                        val cores = Runtime.getRuntime().availableProcessors()
                        val out = ArrayList<Int>(cores)
                        for (i in 0 until cores) {
                            val mhz = try {
                                java.io.File(
                                    "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq",
                                ).readText().trim().toLong() / 1000L
                            } catch (_: Exception) {
                                -1L
                            }
                            out.add(mhz.toInt())
                        }
                        result.success(out)
                    }
                    "sensorCount" -> {
                        val sm = getSystemService(SENSOR_SERVICE)
                            as? android.hardware.SensorManager
                        result.success(
                            sm?.getSensorList(
                                android.hardware.Sensor.TYPE_ALL,
                            )?.size ?: -1,
                        )
                    }
                    "appCount" -> {
                        result.success(
                            packageManager.getInstalledApplications(0).size,
                        )
                    }
                    "battVoltageMv", "battTempC", "battHealth", "battTech" -> {
                        val st = registerReceiver(
                            null,
                            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
                        )
                        when (call.method) {
                            "battVoltageMv" -> result.success(
                                st?.getIntExtra(
                                    BatteryManager.EXTRA_VOLTAGE, -1,
                                ) ?: -1,
                            )
                            "battTempC" -> result.success(
                                (st?.getIntExtra(
                                    BatteryManager.EXTRA_TEMPERATURE, -1,
                                ) ?: -1) / 10.0,
                            )
                            "battHealth" -> {
                                val h = st?.getIntExtra(
                                    BatteryManager.EXTRA_HEALTH, -1,
                                ) ?: -1
                                result.success(
                                    when (h) {
                                        BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
                                        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheat"
                                        BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
                                        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over voltage"
                                        BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
                                        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Failure"
                                        else -> "Unknown"
                                    },
                                )
                            }
                            else -> result.success(
                                st?.getStringExtra(
                                    BatteryManager.EXTRA_TECHNOLOGY,
                                ) ?: "—",
                            )
                        }
                    }
                    "uptimeMs" -> result.success(
                        android.os.SystemClock.elapsedRealtime(),
                    )
                    "kernelVersion" -> {
                        result.success(
                            try {
                                java.io.File("/proc/version").readText()
                                    .substringBefore("\n").trim()
                            } catch (_: Exception) {
                                "—"
                            },
                        )
                    }
                    "networkType" -> {
                        result.success(activeNetworkType())
                    }
                    // Connectivity tab: validated internet + metered flag.
                    "netExtra" -> {
                        result.success(collectNetExtra())
                    }
                    // Connectivity sections: Wi-Fi caps, Bluetooth caps,
                    // NFC, UWB, USB, ADB. No location/Bluetooth runtime
                    // permission needed — unknowns come back null and
                    // the UI renders them honestly.
                    "connInfo" -> {
                        result.success(collectConnInfo())
                    }
                    // Display tab bundle (all Settings.System reads are
                    // permission-free).
                    "displayInfo" -> {
                        result.success(collectDisplayInfo())
                    }
                    // Camera tab: Camera2 characteristics per camera id.
                    // No CAMERA permission needed (characteristics only,
                    // never opened). Multi-lens phones report each id.
                    "cameraInfo" -> {
                        result.success(collectCameraInfo())
                    }
                    // Thermal tab: every thermal_zone type + temp +
                    // PowerManager status. Sysfs reads, no permission.
                    "thermalInfo" -> {
                        result.success(collectThermalInfo())
                    }
                    // Full sensor list (beyond the count): name, vendor,
                    // type string, version, range, resolution, power.
                    "sensorList" -> {
                        result.success(collectSensorList())
                    }
                    // Apps tab: visible installed packages with icons,
                    // versions, SDK levels, timestamps, APK bytes.
                    // No QUERY_ALL_PACKAGES: only packages visible to
                    // the app (launcher + declared queries) are listed.
                    "appList" -> {
                        result.success(collectAppList())
                    }
                    "launchApp" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        result.success(launchApp(pkg))
                    }
                    // Apps tab detail sheet: manifest components.
                    "appDetail" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        try {
                            result.success(collectAppDetail(pkg))
                        } catch (e: Exception) {
                            result.error(
                                "DETAIL_FAILED", e.message, null,
                            )
                        }
                    }
                    "extractApk" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        try {
                            result.success(extractApk(pkg))
                        } catch (e: Exception) {
                            result.error(
                                "EXTRACT_FAILED", e.message, null,
                            )
                        }
                    }
                    "openAppSettings" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        result.success(openAppSettings(pkg))
                    }
                    // Memory tab: system/vendor partition sizes so the
                    // Internal Storage card can split "system reserved".
                    "sysParts" -> {
                        fun sz(p: String): Long {
                            return try {
                                val s = StatFs(p)
                                s.blockCountLong * s.blockSizeLong
                            } catch (_: Exception) {
                                0L
                            }
                        }
                        result.success(mapOf(
                            "systemBytes" to sz("/system"),
                            "vendorBytes" to sz("/vendor"),
                        ))
                    }
                    "openBtSettings" -> {
                        result.success(openBtSettings())
                    }
                    // System tab bundle for CubicDevice Info (one round-trip).
                    "systemInfo" -> {
                        result.success(collectSystemInfo())
                    }
                    // CPU tab bundle: per-core min/max kHz, governor,
                    // EGL renderer/vendor/version (no permission needed).
                    "cpuInfo" -> {
                        result.success(collectCpuInfo())
                    }
                    // Battery live snapshot for the graph + capacities.
                    "battLive" -> {
                        result.success(collectBattLive())
                    }
                    // Wi-Fi details for the Network tab (no location
                    // permission needed — SSID/MAC are NOT read).
                    "wifiInfo" -> {
                        result.success(collectWifiInfo())
                    }
                    // In-app Data Usage page (NetworkStatsManager).
                    // Needs Usage Access (PACKAGE_USAGE_STATS):
                    // trafficPerm -> Bool, openUsageAccess -> Bool,
                    // trafficSummary{startMs,endMs} -> {rx,tx,wifiRx,
                    //   wifiTx,mobileRx,mobileTx}, trafficApps{...} ->
                    //   [{package,label,icon,rx,tx,wifiRx,wifiTx}],
                    // trafficBoot -> since-boot totals (no permission).
                    "trafficPerm" -> {
                        result.success(hasUsageAccess())
                    }
                    "openUsageAccess" -> {
                        result.success(openUsageAccessSettings())
                    }
                    "trafficSummary" -> {
                        val s = (call.argument<Any>("startMs")
                            as? Number)?.toLong() ?: 0L
                        val e = (call.argument<Any>("endMs")
                            as? Number)?.toLong()
                            ?: System.currentTimeMillis()
                        try {
                            result.success(collectTrafficSummary(s, e))
                        } catch (se: SecurityException) {
                            result.error(
                                "NEEDS_PERMISSION",
                                "Usage access not granted",
                                null,
                            )
                        } catch (ex: Exception) {
                            result.error(
                                "TRAFFIC_FAILED", ex.message, null,
                            )
                        }
                    }
                    "trafficApps" -> {
                        val s = (call.argument<Any>("startMs")
                            as? Number)?.toLong() ?: 0L
                        val e = (call.argument<Any>("endMs")
                            as? Number)?.toLong()
                            ?: System.currentTimeMillis()
                        try {
                            result.success(collectTrafficApps(s, e))
                        } catch (se: SecurityException) {
                            result.error(
                                "NEEDS_PERMISSION",
                                "Usage access not granted",
                                null,
                            )
                        } catch (ex: Exception) {
                            result.error(
                                "TRAFFIC_FAILED", ex.message, null,
                            )
                        }
                    }
                    "trafficBoot" -> {
                        result.success(collectTrafficBoot())
                    }
                    // Open Android's Data Usage settings page.
                    "openDataUsage" -> {
                        result.success(openDataUsageSettings())
                    }
                    // Device tab fields for CubicDevice Info. The three
                    // telephony lookups need READ_PHONE_STATE — on
                    // SecurityException they return "PERMISSION" and the
                    // UI shows a Grant Permission button instead.
                    "deviceName" -> {
                        result.success(
                            try {
                                android.provider.Settings.Global.getString(
                                    contentResolver,
                                    android.provider.Settings.Global
                                        .DEVICE_NAME,
                                ) ?: android.os.Build.MODEL
                            } catch (_: Exception) {
                                android.os.Build.MODEL
                            },
                        )
                    }
                    "androidId" -> {
                        result.success(
                            try {
                                android.provider.Settings.Secure.getString(
                                    contentResolver,
                                    android.provider.Settings.Secure
                                        .ANDROID_ID,
                                ) ?: "—"
                            } catch (_: Exception) {
                                "—"
                            },
                        )
                    }
                    "phoneType", "mobileNet" -> {
                        try {
                            val tm = getSystemService(
                                TELEPHONY_SERVICE,
                            ) as? android.telephony.TelephonyManager
                            if (call.method == "phoneType") {
                                result.success(
                                    when (tm?.phoneType) {
                                        android.telephony.TelephonyManager
                                            .PHONE_TYPE_GSM ->
                                            "Smartphone · GSM"
                                        android.telephony.TelephonyManager
                                            .PHONE_TYPE_CDMA ->
                                            "Smartphone · CDMA"
                                        android.telephony.TelephonyManager
                                            .PHONE_TYPE_SIP ->
                                            "SIP phone"
                                        android.telephony.TelephonyManager
                                            .PHONE_TYPE_NONE ->
                                            "No voice radio"
                                        else -> "Unknown"
                                    },
                                )
                            } else {
                                val nt = tm?.dataNetworkType
                                    ?: android.telephony.TelephonyManager
                                        .NETWORK_TYPE_UNKNOWN
                                result.success(
                                    when (nt) {
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_NR -> "5G"
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_LTE -> "LTE (4G)"
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_HSPAP,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_HSPA,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_HSDPA,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_HSUPA,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_UMTS,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_EVDO_0,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_EVDO_A,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_EVDO_B,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_EHRPD -> "3G"
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_GPRS,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_EDGE,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_CDMA,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_1xRTT,
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_IDEN -> "2G"
                                        android.telephony.TelephonyManager
                                            .NETWORK_TYPE_UNKNOWN ->
                                            "No service"
                                        else -> "Unknown"
                                    },
                                )
                            }
                        } catch (e: SecurityException) {
                            result.success("PERMISSION")
                        } catch (e: Exception) {
                            result.error("DEVICE_FAILED", e.message, null)
                        }
                    }
                    "esim" -> {
                        result.success(
                            if (packageManager.hasSystemFeature(
                                    android.content.pm.PackageManager
                                        .FEATURE_TELEPHONY_EUICC,
                                )
                            ) {
                                "Supported"
                            } else {
                                "Not Supported"
                            },
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("DEVICE_FAILED", e.message, null)
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

    /// Sanitizes a RELATIVE subfolder path (e.g. "CubicLM/System Logs")
    /// segment by segment, preserving '/' separators. Prevents both
    /// traversal ('..') and flattening ('/' → '_').
    private fun sanitizeSubfolder(subfolder: String): String {
        val clean = subfolder
            .split('/')
            .map { it.trim().replace(Regex("""[\\:*?"<>|]"""), "") }
            .filter { it.isNotEmpty() && it != "." && it != ".." }
            .joinToString("/")
        return clean.ifBlank { "CubicLM" }
    }

    /// JVM crash-file handler for System Logs: writes uncaught Java/Kotlin
    /// stack traces where Dart can read them on next boot (works on every
    /// API level, unlike the trace stream). Chained: the previous handler
    /// still runs so crash behavior is unchanged.
    private fun installCrashFileHandler() {
        if (crashHandlerInstalled) return
        crashHandlerInstalled = true
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val appFlutter = java.io.File(filesDir.parentFile, "app_flutter/cubiclm_crashes")
                appFlutter.mkdirs()
                val f = java.io.File(appFlutter, "crash_${System.currentTimeMillis()}.txt")
                f.writeText("${java.util.Date()}\nthread=${t.name}\n${Log.getStackTraceString(e)}")
                // Keep only the newest few files.
                appFlutter.listFiles()
                    ?.sortedBy { it.lastModified() }
                    ?.dropLast(3)
                    ?.forEach { try { it.delete() } catch (_: Exception) {} }
            } catch (_: Exception) {
            }
            try {
                prev?.uncaughtException(t, e)
            } catch (_: Exception) {
            }
        }
    }

    /// Recent death records for this package (newest first, max 8).
    /// Each map: reason (int code), timestampMs, importance, status,
    /// description (signal + fault addr for native crashes), trace (head
    /// of the system trace stream: Java stack for CRASH, tombstone
    /// excerpt for CRASH_NATIVE — API 31+, null below), rssKb, pssKb.
    /// Empty below API 30 or on any failure — Dart treats that as "none".
    private fun recentExitReasons(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.getHistoricalProcessExitReasons(packageName, 0, 8).map { info ->
                mapOf(
                    "reason" to info.reason,
                    "timestampMs" to info.timestamp,
                    "importance" to info.importance,
                    "status" to info.status,
                    "description" to (info.description ?: ""),
                    "trace" to readTraceHead(info),
                    "rssKb" to (info.rss / 1024L),
                    "pssKb" to (info.pss / 1024L),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /// First ~8KB of the system trace stream (Java stack / tombstone
    /// head). Null-safe: stream exists only on API 31+ and only for
    /// some death kinds. Never throws — forensics must not break boot.
    private fun readTraceHead(info: android.app.ApplicationExitInfo): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return ""
        return try {
            info.traceInputStream?.bufferedReader()?.use { reader ->
                val buf = CharArray(8192)
                val n = reader.read(buf, 0, buf.size)
                if (n > 0) String(buf, 0, n) else ""
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }
}
