//package com.main_memo.memo_cat_project
//
//import android.content.BroadcastReceiver
//import android.content.Context
//import android.content.Intent
//import android.util.Log
//
//class WakeReceiver : BroadcastReceiver() {
//    override fun onReceive(context: Context, intent: Intent?) {
//        val action = intent?.action ?: return
//        Log.d("WakeReceiver", "onReceive: $action")
//
//        when (action) {
//            Intent.ACTION_BOOT_COMPLETED,
//            Intent.ACTION_LOCKED_BOOT_COMPLETED,
//            Intent.ACTION_USER_PRESENT,
//            Intent.ACTION_USER_UNLOCKED,
//            Intent.ACTION_SCREEN_ON -> {
//                val i = Intent(context, MainActivity::class.java).apply {
//                    addFlags(
//                        Intent.FLAG_ACTIVITY_NEW_TASK or
//                                Intent.FLAG_ACTIVITY_SINGLE_TOP or
//                                Intent.FLAG_ACTIVITY_CLEAR_TOP
//                    )
//                }
//                try { context.startActivity(i) } catch (e: Exception) {
//                    Log.e("WakeReceiver", "Failed to start activity", e)
//                }
//            }
//        }
//    }
//}
//
package com.main_memo.memo_cat_project

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class WakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val i = Intent(context, ScreenWatchService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }
    }
}
