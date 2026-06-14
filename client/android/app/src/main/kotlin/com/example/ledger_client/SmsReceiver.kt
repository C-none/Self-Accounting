package com.example.ledger_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.provider.Telephony
import java.util.Collections

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }
        if (!SmsBridge.isNetworkAvailable(context)) {
            return
        }
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (message in messages) {
            SmsBridge.add(
                mapOf(
                    "id" to "${message.originatingAddress ?: ""}:${message.timestampMillis}",
                    "sender" to (message.originatingAddress ?: ""),
                    "dateMillis" to message.timestampMillis,
                    "body" to message.messageBody
                )
            )
        }
    }
}

object SmsBridge {
    private val recent = Collections.synchronizedList(mutableListOf<Map<String, Any>>())

    fun add(message: Map<String, Any>) {
        synchronized(recent) {
            recent.add(0, message)
            while (recent.size > 20) {
                recent.removeAt(recent.lastIndex)
            }
        }
    }

    fun consumeRecent(): List<Map<String, Any>> {
        synchronized(recent) {
            val copy = recent.toList()
            recent.clear()
            return copy
        }
    }

    fun isNetworkAvailable(context: Context): Boolean {
        return try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = manager.activeNetwork ?: return false
                val caps = manager.getNetworkCapabilities(network) ?: return false
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            } else {
                @Suppress("DEPRECATION")
                manager.activeNetworkInfo?.isConnected == true
            }
        } catch (_: SecurityException) {
            false
        }
    }
}
