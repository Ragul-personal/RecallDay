package com.recallday.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Storage Access Framework bridge.
 *
 * Lets the user nominate a folder once; the app then reads and writes a backup
 * file there forever without any storage permission and without a prompt.
 *
 * Why not just write to /storage/emulated/0/Documents with dart:io? Because
 * that is not a real filesystem on modern Android. Writes there appeared to
 * succeed while the matching read failed with EACCES, `File.exists()` returned
 * false on a denied read instead of throwing (so a present backup looked
 * absent), and the OS quietly rewrote file extensions. SAF is the supported
 * contract: `takePersistableUriPermission` grants durable access to exactly
 * the folder the user chose, and it survives reboots.
 *
 * The grant does NOT survive an uninstall — Android drops it with the app's
 * identity — so after reinstalling, the user re-picks the same folder once and
 * the app carries on writing to the same file.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "recallday/saf"
    private val pickFolderRequest = 9001
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "hasAccess" -> result.success(hasAccess(call.argument<String>("uri")))
                "folderName" -> result.success(folderName(call.argument<String>("uri")))
                "writeFile" -> result.success(
                    writeFile(
                        call.argument<String>("uri"),
                        call.argument<String>("name"),
                        call.argument<ByteArray>("bytes"),
                        call.argument<String>("mime") ?: "application/octet-stream",
                    )
                )
                "readFile" -> result.success(
                    readFile(call.argument<String>("uri"), call.argument<String>("name"))
                )
                "release" -> result.success(release(call.argument<String>("uri")))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("saf_error", e.message, null)
        }
    }

    // ------------------------------------------------------------- folder pick

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A folder picker is already open.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, pickFolderRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickFolderRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingPick
        pendingPick = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // User backed out. Null, not an error — the caller treats it as
            // "cancelled" rather than something to report.
            pending?.success(null)
            return
        }

        // This is the line that makes the choice durable. Without it the grant
        // dies with the activity and the next launch has no access.
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            pending?.error("saf_error", "Could not keep access to that folder.", null)
            return
        }
        pending?.success(uri.toString())
    }

    // ------------------------------------------------------------------ access

    /** True when we still hold a persisted read/write grant for [uriString]. */
    private fun hasAccess(uriString: String?): Boolean {
        if (uriString.isNullOrEmpty()) return false
        val uri = Uri.parse(uriString)
        return contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
    }

    private fun folderName(uriString: String?): String? {
        if (uriString.isNullOrEmpty()) return null
        return DocumentFile.fromTreeUri(this, Uri.parse(uriString))?.name
    }

    private fun release(uriString: String?): Boolean {
        if (uriString.isNullOrEmpty()) return false
        return try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(uriString),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            true
        } catch (e: SecurityException) {
            false
        }
    }

    // ------------------------------------------------------------------- files

    /**
     * Create or overwrite [name] inside the chosen folder. Returns the document
     * URI, or null if the folder is no longer reachable.
     */
    private fun writeFile(
        uriString: String?,
        name: String?,
        bytes: ByteArray?,
        mime: String,
    ): String? {
        if (uriString.isNullOrEmpty() || name.isNullOrEmpty() || bytes == null) return null
        val tree = DocumentFile.fromTreeUri(this, Uri.parse(uriString)) ?: return null
        if (!tree.canWrite()) return null

        // Reuse the existing document rather than deleting and recreating it.
        // Creating a fresh file makes Android disambiguate the name — that's
        // how you end up with backup(1).json, backup(2).json and so on.
        val existing = tree.findFile(name)
        val target = existing ?: tree.createFile(mime, name) ?: return null

        contentResolver.openOutputStream(target.uri, "wt").use { out ->
            if (out == null) return null
            out.write(bytes)
            out.flush()
        }
        return target.uri.toString()
    }

    private fun readFile(uriString: String?, name: String?): ByteArray? {
        if (uriString.isNullOrEmpty() || name.isNullOrEmpty()) return null
        val tree = DocumentFile.fromTreeUri(this, Uri.parse(uriString)) ?: return null
        val file = tree.findFile(name) ?: return null
        if (!file.exists() || !file.canRead()) return null
        return contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
    }
}
