package com.main_memo.memo_cat_project

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL_ID_SILENT = "memo_cat_silent_v2"
        const val METHOD_WAKE = "memo.cat/wake"
        const val METHOD_EXACT = "memo.cat/exact_alarm"
        const val REQ_NOTI = 9001
        const val METHOD_TIMEZONE = "memo.cat/timezone"

        // ✅ 새 채널: 메모별 예약 알림
        const val METHOD_REMIND = "memo.cat/remind"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // (기존) 무음 트레이 표시 채널 유지
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_WAKE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "wakeNow" -> {
                        val title = call.argument<String>("title") ?: "메모냥이"
                        val body = call.argument<String>("body") ?: "열어볼래요?"
                        showSilentNotification(title, body)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // (기존) 정확 알람 권한 체크/요청 유지
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_EXACT)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canScheduleExactAlarms" -> {
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            am.canScheduleExactAlarms()
                        } else true
                        result.success(ok)
                    }
                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ✅ 신규: 단일 시각 예약/취소
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_REMIND)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // args: { noteId: "...", body: "...", whenEpochMs: <ms> , title?: "..." }
                    "scheduleAt" -> {
                        val noteId = call.argument<String>("noteId") ?: return@setMethodCallHandler result.error("ARG", "noteId required", null)
                        val body   = call.argument<String>("body") ?: ""
                        val whenTs = call.argument<Long>("whenEpochMs") ?: return@setMethodCallHandler result.error("ARG", "whenEpochMs required", null)
                        val title  = call.argument<String>("title") ?: "예약 알림"

                        val i = Intent(applicationContext, ScreenWatchService::class.java).apply {
                            action = ScreenWatchService.ACTION_SCHEDULE_ONE
                            putExtra(ScreenWatchService.EXTRA_NOTE_ID, noteId)
                            putExtra(ScreenWatchService.EXTRA_TITLE, title)
                            putExtra(ScreenWatchService.EXTRA_BODY, body)
                            putExtra("whenTs", whenTs)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                        result.success(true)
                    }
                    // args: { noteId: "..." }  (기존 호환 취소)
                    "cancelAllForNote" -> {
                        val noteId = call.argument<String>("noteId") ?: return@setMethodCallHandler result.error("ARG", "noteId required", null)
                        val i = Intent(applicationContext, ScreenWatchService::class.java).apply {
                            action = ScreenWatchService.ACTION_CANCEL_THREE
                            putExtra(ScreenWatchService.EXTRA_NOTE_ID, noteId)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createSilentChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            // IMPORTANCE_LOW: 헤드업/소리/진동 없음 (트레이에만 조용히)
            val ch = NotificationChannel(
                CHANNEL_ID_SILENT,
                "메모냥 무음 알림",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "무음 + 알림창에만 표시"
                setSound(null, null)           // 🔇 소리 없음
                enableVibration(false)         // 🔕 진동 없음
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun maybeRequestPostNotification() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTI
            )
        }
    }

    private fun startScreenWatchService() {
        val i = Intent(applicationContext, ScreenWatchService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
        else startService(i)
    }

    // ✅ “무음 + 트레이 전용” 알림 빌더 (기존 기능 유지)
    private fun showSilentNotification(title: String, body: String) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
        }

        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            if (Build.VERSION.SDK_INT >= 31)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID_SILENT)
            .setSmallIcon(resources.getIdentifier("ic_launcher", "mipmap", packageName))
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setOngoing(false)
//            .setSilent(true) // ✅ 강제 무음
            .setPriority(NotificationCompat.PRIORITY_LOW) // (O 미만용 백업)

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(10001, builder.build())
    }


}
