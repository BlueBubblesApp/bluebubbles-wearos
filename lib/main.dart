import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles_wearos/helpers/attachment_downloader.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_list/conversation_list.dart';
import 'package:bluebubbles_wearos/layouts/setup/failure_to_start.dart';
import 'package:bluebubbles_wearos/layouts/setup/setup_view.dart';
import 'package:bluebubbles_wearos/managers/background_isolate.dart';
import 'package:bluebubbles_wearos/managers/incoming_queue.dart';
import 'package:bluebubbles_wearos/managers/life_cycle_manager.dart';
import 'package:bluebubbles_wearos/managers/method_channel_interface.dart';
import 'package:bluebubbles_wearos/managers/navigator_manager.dart';
import 'package:bluebubbles_wearos/managers/notification_manager.dart';
import 'package:bluebubbles_wearos/managers/queue_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/objectbox.dart';
import 'package:firebase_dart/firebase_dart.dart';
import 'package:firebase_dart/src/auth/utils.dart' as fdu;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Message;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:get/get.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';

// final SentryClient _sentry = SentryClient(
//     dsn:
//         "https://3123d4f0d82d405190cb599d0e904adc@o373132.ingest.sentry.io/5372783");

bool get isInDebugMode {
  // Assume you're in production mode.
  bool inDebugMode = false;

  // Assert expressions are only evaluated during development. They are ignored
  // in production. Therefore, this code only sets `inDebugMode` to true
  // in a development environment.
  assert(inDebugMode = true);

  return inDebugMode;
}

FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
late SharedPreferences prefs;
late final FirebaseApp app;
late final Store store;
late final Box<Attachment> attachmentBox;
late final Box<Chat> chatBox;
late final Box<FCMData> fcmDataBox;
late final Box<Handle> handleBox;
late final Box<Message> messageBox;
late final Box<ScheduledMessage> scheduledBox;
late final Box<ThemeEntry> themeEntryBox;
late final Box<ThemeObject> themeObjectBox;
late final Box<AttachmentMessageJoin> amJoinBox;
late final Box<ChatHandleJoin> chJoinBox;
late final Box<ChatMessageJoin> cmJoinBox;
late final Box<ThemeValueJoin> tvJoinBox;

Future<Null> _reportError(dynamic error, dynamic stackTrace) async {
  // Print the exception to the console.
  Logger.error('Caught error: $error');
  Logger.error(stackTrace.toString());
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      // If there is a bad certificate callback, override it if the host is part of
      // your server URL
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        String serverUrl = getServerAddress() ?? "";
        return serverUrl.contains(host);
      }; // add your localhost detection logic here if you want
  }
}

Future<Null> main() async {
  HttpOverrides.global = MyHttpOverrides();

  // This captures errors reported by the Flutter framework.
  FlutterError.onError = (FlutterErrorDetails details) {
    Logger.error(details.exceptionAsString());
    Logger.error(details.stack.toString());
    if (isInDebugMode) {
      // In development mode simply print to console.
      FlutterError.dumpErrorToConsole(details);
    } else {
      // In production mode report to the application zone to report to
      // Sentry.
      Zone.current.handleUncaughtError(details.exception, details.stack!);
    }
  };

  WidgetsFlutterBinding.ensureInitialized();
  dynamic exception;
  dynamic stacktrace;
  try {
    prefs = await SharedPreferences.getInstance();
    //ignore: unnecessary_cast, we need this as a workaround
    Directory documentsDirectory =
    (kIsDesktop ? await getApplicationSupportDirectory() : await getApplicationDocumentsDirectory()) as Directory;
    store = await openStore(directory: documentsDirectory.path + '/objectbox');
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
    FirebaseDart.setup(
      platform: fdu.Platform.web(
        currentUrl: Uri.base.toString(),
        isMobile: false,
        isOnline: true,
      ),
    );
    var options = FirebaseOptions(
        appId: 'my_app_id',
        apiKey: 'apiKey',
        projectId: 'my_project',
        messagingSenderId: 'ignore',
        authDomain: 'my_project.firebaseapp.com');
    app = await Firebase.initializeApp(options: options);
    await initializeDateFormatting('fr_FR', null);
    await SettingsManager().init();
    await SettingsManager().getSavedSettings(headless: true);
    Get.put(AttachmentDownloadService());
    if (!kIsWeb && !kIsDesktop) {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await FlutterNativeTimezone.getLocalTimezone()));
      if (!await GoogleMlKit.nlp.entityModelManager().isModelDownloaded(EntityExtractorOptions.ENGLISH)) {
        GoogleMlKit.nlp.entityModelManager().downloadModel(EntityExtractorOptions.ENGLISH, isWifiRequired: false);
      }
      await FlutterLibphonenumber().init();
    }
  } catch (e, s) {
    exception = e;
    stacktrace = s;
  }

  if (exception == null) {
    runZonedGuarded<Future<Null>>(() async {
      ThemeObject light = await ThemeObject.getLightTheme();
      ThemeObject dark = await ThemeObject.getDarkTheme();

      runApp(Main(
        lightTheme: light.themeData,
        darkTheme: dark.themeData,
      ));
    }, (Object error, StackTrace stackTrace) async {
      // Whenever an error occurs, call the `_reportError` function. This sends
      // Dart errors to the dev console or Sentry depending on the environment.
      await _reportError(error, stackTrace);
    });
  } else {
    runApp(FailureToStart(e: exception));
    throw Exception(exception + stacktrace);
  }
}

/// The [Main] app.
///
/// This is the entry for the whole app (when the app is visible or not fully closed in the background)
/// This main widget controls
///     - Theming
///     - [NavgatorManager]
///     - [Home] widget
class Main extends StatelessWidget with WidgetsBindingObserver {
  final ThemeData darkTheme;
  final ThemeData lightTheme;

  const Main({Key? key, required this.lightTheme, required this.darkTheme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AdaptiveTheme(
      /// These are the default white and dark themes.
      /// These will be changed by [SettingsManager] when you set a custom theme
      light: darkTheme,

      /// The default is that the dark and light themes will follow the system theme
      /// This will be changed by [SettingsManager]
      initial: AdaptiveThemeMode.light,
      builder: (theme, darkTheme) => GetMaterialApp(
        /// Hide the debug banner in debug mode
        debugShowCheckedModeBanner: false,

        title: 'BlueBubbles',

        /// Set the light theme from the [AdaptiveTheme]
        theme: theme.copyWith(appBarTheme: theme.appBarTheme.copyWith(elevation: 0.0)),

        /// Set the dark theme from the [AdaptiveTheme]
        darkTheme: darkTheme.copyWith(appBarTheme: darkTheme.appBarTheme.copyWith(elevation: 0.0)),

        /// [NavigatorManager] is set as the navigator key so that we can control navigation from anywhere
        navigatorKey: NavigatorManager().navigatorKey,

        /// [Home] is the starting widget for the app
        home: Home(),

        defaultTransition: Transition.cupertino,
      ),
    );
  }
}

/// [Home] widget is responsible for holding the main UI view.
///
/// It renders the main view and also initializes a few managers
///
/// The [LifeCycleManager] also is binded to the [WidgetsBindingObserver]
/// so that it can know when the app is closed, paused, or resumed
class Home extends StatefulWidget {
  Home({Key? key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  ReceivePort port = ReceivePort();
  bool serverCompatible = true;

  @override
  void initState() {
    super.initState();

    // we want to refresh the page rather than loading a new instance of [Home]
    // to avoid errors
    if (LifeCycleManager().isAlive && kIsWeb) {
      html.window.location.reload();
    }

    // Initalize a bunch of managers
    MethodChannelInterface().init();

    // We initialize the [LifeCycleManager] so that it is open, because [initState] occurs when the app is opened
    LifeCycleManager().opened();

    if (!kIsWeb) {
      // This initialization sets the function address in the native code to be used later
      BackgroundIsolateInterface.initialize();
      // Set a reference to the DB so it can be used in another isolate
      prefs.setString("objectbox-reference", base64.encode(store.reference.buffer.asUint8List()));
      // Create the notification in case it hasn't been already. Doing this multiple times won't do anything, so we just do it on every app start
      NotificationManager().createNotificationChannel(
        NotificationManager.newMessageChannel,
        "New Messages",
        "For new messages retreived",
      );
      NotificationManager().createNotificationChannel(
        NotificationManager.socketErrorChannel,
        "Socket Connection Error",
        "Notifications that will appear when the connection to the server has failed",
      );

      // create a send port to receive messages from the background isolate when
      // the UI thread is active
      IsolateNameServer.registerPortWithName(port.sendPort, 'bg_isolate');
      port.listen((dynamic data) {
        Logger.info("SendPort received action ${data['action']}");
        if (data['action'] == 'new-message') {
          // Add it to the queue with the data as the item
          IncomingQueue().add(QueueItem(event: IncomingQueue.handleMessageEvent, item: {"data": data}));
        } else if (data['action'] == 'update-message') {
          // Add it to the queue with the data as the item
          IncomingQueue().add(QueueItem(event: IncomingQueue.handleUpdateMessage, item: {"data": data}));
        }
      });
    }

    // Get the saved settings from the settings manager after the first frame
    SchedulerBinding.instance!.addPostFrameCallback((_) async {
      await SettingsManager().getSavedSettings();

      MethodChannelInterface().invokeMethod("get-starting-intent").then((value) {
        if (!SettingsManager().settings.finishedSetup.value) return;
        if (value != null) {
          LifeCycleManager().isBubble = value['bubble'] == "true";
          MethodChannelInterface().openChat(value['guid'].toString());
        }
      });
    });

    // Bind the lifecycle events
    WidgetsBinding.instance!.addObserver(this);
  }

  @override
  void didChangeDependencies() async {
    Locale myLocale = Localizations.localeOf(context);
    SettingsManager().countryCode = myLocale.countryCode;
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    // Clean up observer when app is fully closed
    WidgetsBinding.instance!.removeObserver(this);
    super.dispose();
  }

  /// Called when the app is either closed or opened or paused
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Call the [LifeCycleManager] events based on the [state]
    if (state == AppLifecycleState.paused) {
      LifeCycleManager().close();
    } else if (state == AppLifecycleState.resumed) {
      LifeCycleManager().opened();
    }
  }

  /// Render
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
      systemNavigationBarIconBrightness:
          Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
      statusBarColor: Colors.transparent, // status bar color
    ));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (BuildContext context) {
            if (SettingsManager().settings.finishedSetup.value) {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.landscapeRight,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ]);
              if (!serverCompatible && kIsWeb) {
                return FailureToStart(
                  otherTitle: "Server version too low, please upgrade!",
                  e: "Required Server Version: v0.2.0",
                );
              }
              return ConversationList(
                showArchivedChats: false,
                showUnknownSenders: false,
              );
            } else {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.portraitUp,
              ]);
              return WillPopScope(
                onWillPop: () async => false,
                child: SetupView(),
              );
            }
          },
        ),
      ),
    );
  }
}
