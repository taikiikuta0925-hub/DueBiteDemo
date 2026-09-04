package com.example.flutter_application_1

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

class ExpiryNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            ExpiryNotificationScheduler.restore(context)
            return
        }

        ExpiryNotificationScheduler.ensureChannel(context)
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, ExpiryNotificationScheduler.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_today)
            .setContentTitle(intent.getStringExtra("title") ?: "賞味期限のお知らせ")
            .setContentText(intent.getStringExtra("body") ?: "登録した食品を確認しましょう")
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        contentIntent?.let(builder::setContentIntent)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
        }

        notificationManager.notify(intent.getIntExtra("notificationId", 0), builder.build())
    }
}

object ExpiryNotificationScheduler {
    const val CHANNEL_ID = "expiry_reminders"
    private const val CHANNEL_NAME = "賞味期限のお知らせ"
    private const val PREFERENCES = "tabekiri_native_notifications"
    private const val STORED_REMINDERS = "reminders"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "登録した食品の賞味期限が近づいたときにお知らせします"
            }
            manager.createNotificationChannel(channel)
        }
    }

    fun sync(context: Context, enabled: Boolean, reminders: List<Map<String, Any>>) {
        cancelStored(context)
        val json = JSONArray()
        if (enabled) {
            reminders.forEach { reminder -> json.put(JSONObject(reminder)) }
        }
        preferences(context).edit().putString(STORED_REMINDERS, json.toString()).apply()
        if (enabled) scheduleJson(context, json)
    }

    fun restore(context: Context) {
        val raw = preferences(context).getString(STORED_REMINDERS, "[]") ?: "[]"
        scheduleJson(context, JSONArray(raw))
    }

    private fun scheduleJson(context: Context, reminders: JSONArray) {
        ensureChannel(context)
        val now = System.currentTimeMillis()
        for (index in 0 until reminders.length()) {
            val reminder = reminders.getJSONObject(index)
            val scheduledAt = reminder.getLong("scheduledAt")
            if (scheduledAt <= now) continue
            schedule(context, reminder, scheduledAt)
        }
    }

    private fun schedule(context: Context, reminder: JSONObject, scheduledAt: Long) {
        val id = reminder.getString("id")
        val notificationId = stableId(id)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            Intent(context, ExpiryNotificationReceiver::class.java).apply {
                action = "${context.packageName}.EXPIRY_REMINDER.$id"
                putExtra("notificationId", notificationId)
                putExtra("title", reminder.getString("title"))
                putExtra("body", reminder.getString("body"))
                putExtra("itemId", reminder.optString("itemId"))
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, scheduledAt, pendingIntent)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, scheduledAt, pendingIntent)
        }
    }

    private fun cancelStored(context: Context) {
        val raw = preferences(context).getString(STORED_REMINDERS, "[]") ?: "[]"
        val reminders = JSONArray(raw)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (index in 0 until reminders.length()) {
            val id = reminders.getJSONObject(index).getString("id")
            val notificationId = stableId(id)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId,
                Intent(context, ExpiryNotificationReceiver::class.java).apply {
                    action = "${context.packageName}.EXPIRY_REMINDER.$id"
                },
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun stableId(value: String): Int {
        var hash = 0x811C9DC5.toInt()
        value.forEach { character ->
            hash = hash xor character.code
            hash *= 0x01000193
        }
        return hash and 0x7FFFFFFF
    }
}
