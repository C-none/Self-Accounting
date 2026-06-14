package com.example.ledger_client

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ledger/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "checkPermissions" -> result.success(hasSmsPermissions())
                    "requestPermissions" -> requestSmsPermissions(result)
                    "scanSms" -> {
                        if (!hasSmsPermissions()) {
                            result.error("permission_denied", "SMS permission is required", null)
                            return@setMethodCallHandler
                        }
                        val sinceMillis = (call.argument<Number>("sinceMillis") ?: 0).toLong()
                        val limit = (call.argument<Number>("limit") ?: 50).toInt()
                        result.success(scanSms(sinceMillis, limit))
                    }
                    "pollBroadcasts" -> result.success(SmsBridge.consumeRecent())
                    else -> result.notImplemented()
                }
            }
    }

    private fun smsPermissions(): Array<String> =
        arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS)

    private fun hasSmsPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return smsPermissions().all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        if (hasSmsPermissions()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_in_progress", "SMS permission request is already running", null)
            return
        }
        pendingPermissionResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(smsPermissions(), 4103)
        } else {
            pendingPermissionResult = null
            result.success(true)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4103) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun scanSms(sinceMillis: Long, limit: Int): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("_id", "address", "date", "body")
        val selection = if (sinceMillis > 0) "date >= ?" else null
        val selectionArgs = if (sinceMillis > 0) arrayOf(sinceMillis.toString()) else null
        contentResolver.query(
            uri,
            projection,
            selection,
            selectionArgs,
            "date DESC"
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow("_id")
            val addressIndex = cursor.getColumnIndexOrThrow("address")
            val dateIndex = cursor.getColumnIndexOrThrow("date")
            val bodyIndex = cursor.getColumnIndexOrThrow("body")
            while (cursor.moveToNext() && out.size < limit.coerceIn(1, 200)) {
                out.add(
                    mapOf(
                        "id" to cursor.getString(idIndex),
                        "sender" to (cursor.getString(addressIndex) ?: ""),
                        "dateMillis" to cursor.getLong(dateIndex),
                        "body" to (cursor.getString(bodyIndex) ?: "")
                    )
                )
            }
        }
        return out
    }
}
