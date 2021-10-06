import 'dart:ui';

import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/main.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/method_channel_interface.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/objectbox.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

abstract class BackgroundIsolateInterface {
  static void initialize() {
    CallbackHandle callbackHandle = PluginUtilities.getCallbackHandle(callbackHandler)!;
    MethodChannelInterface().invokeMethod("initialize-background-handle", {"handle": callbackHandle.toRawHandle()});
  }
}

callbackHandler() async {
  // can't use logger here
  debugPrint("(ISOLATE) Starting up...");
  MethodChannel _backgroundChannel = MethodChannel("com.bluebubbles.wearos");
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  //ignore: unnecessary_cast, we need this as a workaround
  var documentsDirectory =
      (kIsDesktop ? await getApplicationSupportDirectory() : await getApplicationDocumentsDirectory()) as Directory;

  debugPrint("Opening ObjectBox store from path");
  store = await openStore(directory: documentsDirectory.path + '/objectbox');
  debugPrint("Opening boxes");
  attachmentBox = store.box<Attachment>();
  chatBox = store.box<Chat>();
  fcmDataBox = store.box<FCMData>();
  handleBox = store.box<Handle>();
  messageBox = store.box<Message>();
  scheduledBox = store.box<ScheduledMessage>();
  themeEntryBox = store.box<ThemeEntry>();
  themeObjectBox = store.box<ThemeObject>();
  amJoinBox = store.box<AttachmentMessageJoin>();
  chJoinBox = store.box<ChatHandleJoin>();
  cmJoinBox = store.box<ChatMessageJoin>();
  tvJoinBox = store.box<ThemeValueJoin>();
  await SettingsManager().init();
  await SettingsManager().getSavedSettings(headless: true);
  await ContactManager().getContacts(headless: true);
  MethodChannelInterface().init(customChannel: _backgroundChannel);
  await SocketManager().refreshConnection(connectToSocket: false);
}
