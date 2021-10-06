package com.bluebubbles.wearos.method_call_handler;

import android.annotation.SuppressLint;
import android.app.AlarmManager;
import android.content.Context;
import android.os.Build;
import android.content.Intent;
import android.provider.Settings;

import androidx.annotation.RequiresApi;

import com.bluebubbles.wearos.MainActivity;
import com.bluebubbles.wearos.method_call_handler.handlers.AlarmScheduler;
import com.bluebubbles.wearos.method_call_handler.handlers.ClearChatNotifs;
import com.bluebubbles.wearos.method_call_handler.handlers.ClearFailedToSend;
import com.bluebubbles.wearos.method_call_handler.handlers.ClearSocketIssue;
import com.bluebubbles.wearos.method_call_handler.handlers.CreateNotificationChannel;
import com.bluebubbles.wearos.method_call_handler.handlers.DownloadHandler;
import com.bluebubbles.wearos.method_call_handler.handlers.FailedToSend;
import com.bluebubbles.wearos.method_call_handler.handlers.FetchMessagesHandler;
import com.bluebubbles.wearos.method_call_handler.handlers.FirebaseAuth;
import com.bluebubbles.wearos.method_call_handler.handlers.GetLastLocation;
import com.bluebubbles.wearos.method_call_handler.handlers.GetServerUrl;
import com.bluebubbles.wearos.method_call_handler.handlers.InitializeBackgroundHandle;
import com.bluebubbles.wearos.method_call_handler.handlers.MediaSessionListener;
import com.bluebubbles.wearos.method_call_handler.handlers.NewMessageNotification;
import com.bluebubbles.wearos.method_call_handler.handlers.OpenCamera;
import com.bluebubbles.wearos.method_call_handler.handlers.OpenFile;
import com.bluebubbles.wearos.method_call_handler.handlers.OpenLink;
import com.bluebubbles.wearos.method_call_handler.handlers.PickFile;
import com.bluebubbles.wearos.method_call_handler.handlers.PushShareTargets;
import com.bluebubbles.wearos.method_call_handler.handlers.SaveToFile;
import com.bluebubbles.wearos.method_call_handler.handlers.SocketIssueWarning;
import com.bluebubbles.wearos.method_call_handler.handlers.SetNextRestart;
import com.bluebubbles.wearos.method_call_handler.handlers.OpenContactForm;
import com.bluebubbles.wearos.method_call_handler.handlers.ViewContactForm;
import com.bluebubbles.wearos.workers.DartWorker;
import static com.bluebubbles.wearos.MainActivity.engine;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;

public class MethodCallHandler {
    @SuppressLint("RestrictedApi")
    @RequiresApi(api = Build.VERSION_CODES.P)
    public static void methodCallHandler(MethodCall call, MethodChannel.Result result, Context context, DartWorker worker) {
        if (call.method.equals(FirebaseAuth.TAG)) {
            new FirebaseAuth(context, call, result).Handle();
        } else if (call.method.equals("close-background-isolate")) {
            if (worker != null) {
                worker.destroyHeadlessThread();
            }
            result.success("");
        } else if(call.method.equals(FetchMessagesHandler.TAG)) {
            new FetchMessagesHandler(context, call, result).Handle();
        } else if (call.method.equals(CreateNotificationChannel.TAG)) {
            new CreateNotificationChannel(context, call, result).Handle();
        } else if (call.method.equals(NewMessageNotification.TAG)) {
            new NewMessageNotification(context, call, result).Handle();
        } else if (call.method.equals(SocketIssueWarning.TAG)) {
            new SocketIssueWarning(context, call, result).Handle();
        } else if (call.method.equals(ClearSocketIssue.TAG)) {
            new ClearSocketIssue(context, call, result).Handle();
        } else if (call.method.equals(OpenFile.TAG)) {
            new OpenFile(context, call, result).Handle();
        } else if (call.method.equals(OpenLink.TAG)) {
            new OpenLink(context, call, result).Handle();
        } else if (call.method.equals(ClearChatNotifs.TAG)) {
            new ClearChatNotifs(context, call, result).Handle();
        } else if (call.method.equals(GetLastLocation.TAG)) {
            new GetLastLocation(context, call, result).Handle();
        } else if (call.method.equals(SaveToFile.TAG)) {
            new SaveToFile(context, call, result).Handle();
        } else if(call.method.equals(PushShareTargets.TAG)) {
            new PushShareTargets(context, call, result).Handle();
        } else if (call.method.equals("get-starting-intent")) {
            String intent = ((MainActivity) context).getIntent().getStringExtra("chatGuid");
            String bubble = ((MainActivity) context).getIntent().getStringExtra("bubble");
            ((MainActivity) context).getIntent().putExtra("chatGuid", (String) null);
            ((MainActivity) context).getIntent().putExtra("bubble", (String) null);
            HashMap<String, Object> args = new HashMap<>();
            args.put("guid", intent);
            args.put("bubble", bubble);
            result.success(args);
        } else if (call.method.equals(InitializeBackgroundHandle.TAG)) {
            new InitializeBackgroundHandle(context, call, result).Handle();
        } else if (call.method.equals(GetServerUrl.TAG)) {
            new GetServerUrl(context, call, result).Handle();
        } else if (call.method.equals(PickFile.TAG)) {
            new PickFile(context, call, result).Handle();
        } else if(call.method.equals(OpenCamera.TAG)) {
            new OpenCamera(context, call, result).Handle();
        } else if (call.method.equals(AlarmScheduler.TAG)) {
            new AlarmScheduler(context, call, result).Handle();
        } else if (call.method.equals(SetNextRestart.TAG)) {
            new SetNextRestart(context, call, result).Handle();
        } else if (call.method.equals(DownloadHandler.TAG)) {
            new DownloadHandler(context, call, result).Handle();
        } else if (call.method.equals(OpenContactForm.TAG)) {
            new OpenContactForm(context, call, result).Handle();
        } else if (call.method.equals(ViewContactForm.TAG)) {
            new ViewContactForm(context, call, result).Handle();
        } else if (call.method.equals(FailedToSend.TAG)) {
            new FailedToSend(context, call, result).Handle();
        } else if (call.method.equals(ClearFailedToSend.TAG)) {
            new ClearFailedToSend(context, call, result).Handle();
        } else if (call.method.equals("start-notif-listener")) {
            if (Settings.Secure.getString(context.getContentResolver(),"enabled_notification_listeners").contains(context.getPackageName()) && engine != null) {
                new MediaSessionListener(context, call, result).Handle();
            } else {
                result.error("could_not_initialize", "Failed to initialize, permission not granted", "");
            }
        } else if (call.method.equals("request-notif-permission")) {
            if (Settings.Secure.getString(context.getContentResolver(),"enabled_notification_listeners").contains(context.getPackageName())) {
                result.success("");
            } else {
                MainActivity activity = (MainActivity) context;
                activity.result = result;
                Intent intent = new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS");
                activity.startActivityForResult(intent, 3000);
            }
        } else {
            result.notImplemented();
        }
    }
}
