// android/app/src/main/kotlin/com/main_memo/memo_cat_project/ReminderReceiver.kt
package com.main_memo.memo_cat_project

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class ReminderReceiver : BroadcastReceiver() {
    @RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
    override fun onReceive(context: Context, intent: Intent) {
        val noteId   = intent.getStringExtra(ScreenWatchService.EXTRA_NOTE_ID) ?: return
        val title    = intent.getStringExtra(ScreenWatchService.EXTRA_TITLE) ?: "알림"
        val body     = intent.getStringExtra(ScreenWatchService.EXTRA_BODY) ?: ""
        val subText  = intent.getStringExtra(ScreenWatchService.EXTRA_SUBTEXT)
        val notifyId = intent.getIntExtra(ScreenWatchService.EXTRA_NOTIFY_ID, 0)

        val open = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
        }
        val pi = PendingIntent.getActivity(
            context, 0, open,
            if (Build.VERSION.SDK_INT >= 31)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ⬇️ 무음 채널로 전환 + 트레이 전용
        val b = NotificationCompat.Builder(context, MainActivity.CHANNEL_ID_SILENT)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_LOW)   // 트레이 전용
            .setSilent(true)                                 // 완전 무음
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (!subText.isNullOrBlank()) b.setSubText(subText)

        NotificationManagerCompat.from(context).notify(notifyId, b.build())
    }
}
