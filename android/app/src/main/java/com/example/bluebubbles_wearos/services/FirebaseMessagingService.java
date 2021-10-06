package com.bluebubbles.wearos.services;

import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.work.Data;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

import com.bluebubbles.wearos.helpers.NotifyRunnable;
import com.bluebubbles.wearos.workers.FCMWorker;
import com.google.firebase.messaging.RemoteMessage;

import io.flutter.plugin.common.MethodChannel;

import static com.bluebubbles.wearos.MainActivity.CHANNEL;
import static com.bluebubbles.wearos.MainActivity.engine;
import static com.bluebubbles.wearos.workers.FCMWorker.backgroundChannel;
import static com.bluebubbles.wearos.workers.FCMWorker.handler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.concurrent.CountDownLatch;

public class FirebaseMessagingService extends com.google.firebase.messaging.FirebaseMessagingService {
    private static final String TAG = "MyFirebaseMsgService";

    @Override
    public void onCreate() {
        Log.d("BlueBubblesApp", "FCM service spawned");
        super.onCreate();
    }

    @Override
    public void onDestroy() {
        Log.d("BlueBubblesApp", "FCM service destroyed");
        super.onDestroy();
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        Log.d("BlueBubblesApp", "FCM task removed");
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        if (remoteMessage == null) return;
        Log.d("BlueBubblesApp", "Received new message from FCM");
        Log.d("BlueBubblesApp", "Message type: " + remoteMessage.getData().get("type"));
        if (ContextHolder.getApplicationContext() == null) {
            ContextHolder.setApplicationContext(getApplicationContext());
        }
        Intent onBackgroundMessageIntent =
                new Intent(getApplicationContext(), FlutterFirebaseMessagingBackgroundService.class);
        onBackgroundMessageIntent.putExtra(
                "notification", remoteMessage);
        FlutterFirebaseMessagingBackgroundService.enqueueMessageProcessing(
                getApplicationContext(), onBackgroundMessageIntent);
    }

}
