// android/app/src/main/kotlin/com/main_memo/memo_cat_project/ScreenWatchService.kt
package com.main_memo.memo_cat_project

import android.app.*
import android.content.*
import android.os.Build
import android.os.IBinder
import android.content.pm.ServiceInfo
import android.util.Log
import androidx.core.app.NotificationCompat

class ScreenWatchService : Service() {

    private val TAG = "ScreenWatchService"

    companion object {
        const val CHANNEL_ID_FOREGROUND = "memo_cat_service_silent_v2"
        const val CHANNEL_ID_REMINDER   = "memo_cat_reminder_meow_v2" // (미사용 유지 가능)

        // ✅ 새: 단일 알람 스케줄 액션
        const val ACTION_SCHEDULE_ONE = "memo.cat.action.SCHEDULE_ONE"
        const val ACTION_CANCEL_THREE = "memo.cat.action.CANCEL_THREE" // (기존 호환)

        const val EXTRA_NOTE_ID   = "noteId"
        const val EXTRA_TITLE     = "title"
        const val EXTRA_BODY      = "body"
        const val EXTRA_SUBTEXT   = "subText"
        const val EXTRA_NOTIFY_ID = "notifyId"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // 채널들 보장
        createForegroundSilentChannel()
        createSilentReminderChannel() // ⬅️ 무음 알림 채널(메인과 동일 ID) 보장

        // 포그라운드 고정(무음)
        val open = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, open,
            if (Build.VERSION.SDK_INT >= 31)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notif = NotificationCompat.Builder(this, CHANNEL_ID_FOREGROUND)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("메모냥이")
            .setContentText("누르면 들어가진다냥~")
            .setOngoing(true)
            .setContentIntent(pi)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(10100, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(10100, notif)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            // ✅ Dart에서 noteId/body/whenTs(ms)로 호출
            ACTION_SCHEDULE_ONE -> {
                val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: return START_STICKY
                val title  = intent.getStringExtra(EXTRA_TITLE) ?: "예약 알림"
                val body   = intent.getStringExtra(EXTRA_BODY) ?: ""
                val whenTs = intent.getLongExtra("whenTs", -1L)
                if (whenTs > 0) scheduleOne(noteId, title, body, fmtFull(whenTs), whenTs)
            }
            // (기존 호환 취소용)
            ACTION_CANCEL_THREE -> {
                val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: return START_STICKY
                cancelThree(noteId)
            }
        }
        return START_STICKY
    }

    // ============== 채널 ==============
    private fun createForegroundSilentChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID_FOREGROUND,
                "메모냥이(무음 서비스)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                description = "서비스 고정 알림(무음)"
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    // ✅ 메인 액티비티에서 쓰는 무음 채널 ID를 서비스에서도 보장 생성
    private fun createSilentReminderChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                MainActivity.CHANNEL_ID_SILENT,
                "메모냥 무음 알림",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "무음 + 알림창에만 표시"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            nm.createNotificationChannel(ch)
        }
    }

    // ============== 스케줄/취소 ==============
    private fun scheduleOne(
        noteId: String,
        title: String,
        body: String,
        subText: String,
        fireAt: Long
    ) {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        val pi = buildReceiverPI(noteId, 2, title, body, subText) // index=2 유지

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
                } else {
                    am.set(AlarmManager.RTC_WAKEUP, fireAt, pi)
                }
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, fireAt, pi)
            }
        } catch (se: SecurityException) {
            Log.w(TAG, "Exact alarm blocked; fallback to inexact", se)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, fireAt, pi)
            }
        }
    }

    private fun cancelThree(noteId: String) {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        for (i in 0..2) {
            val pi = PendingIntent.getBroadcast(
                this,
                reqId(noteId, i),
                Intent(this, ReminderReceiver::class.java),
                if (Build.VERSION.SDK_INT >= 31)
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                else PendingIntent.FLAG_NO_CREATE
            )
            pi?.let { am.cancel(it); it.cancel() }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(reqId(noteId, i))
        }
    }

    private fun buildReceiverPI(
        noteId: String,
        index: Int,
        title: String,
        body: String,
        subText: String
    ): PendingIntent {
        val intent = Intent(this, ReminderReceiver::class.java).apply {
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_SUBTEXT, subText)
            putExtra(EXTRA_NOTIFY_ID, reqId(noteId, index))
        }
        val flags = if (Build.VERSION.SDK_INT >= 31)
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_CANCEL_CURRENT
        return PendingIntent.getBroadcast(this, reqId(noteId, index), intent, flags)
    }

    private fun reqId(noteId: String, idx: Int): Int {
        val base = (noteId.hashCode() and 0x7fffffff) % 2000000000
        return (base + idx) % 2000000000
    }

    private fun two(n: Int) = n.toString().padStart(2, '0')
    private fun fmtFull(epochMs: Long): String {
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = epochMs }
        val y = cal.get(java.util.Calendar.YEAR)
        val M = two(cal.get(java.util.Calendar.MONTH) + 1)
        val d = two(cal.get(java.util.Calendar.DAY_OF_MONTH))
        val h = two(cal.get(java.util.Calendar.HOUR_OF_DAY))
        val m = two(cal.get(java.util.Calendar.MINUTE))
        return "$y-$M-$d $h:$m"
    }
}
