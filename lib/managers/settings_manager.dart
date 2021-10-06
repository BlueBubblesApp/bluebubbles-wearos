import 'dart:async';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/settings.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

/// [SettingsManager] is responsible for making the current settings accessible to other managers and for saving new settings
///
/// The class also holds miscelaneous stuff such as the [appDocDir] which is used a lot throughout the app
/// This class is a singleton
class SettingsManager {
  factory SettingsManager() {
    return _manager;
  }

  static final SettingsManager _manager = SettingsManager._internal();

  SettingsManager._internal();

  /// [appDocDir] is just a directory that is commonly used
  /// It cannot be accessed by the user, and is private to the app
  late Directory appDocDir;

  /// [settings] is just an instance of the current settings that are saved
  late Settings settings;
  FCMData? fcmData;
  late List<ThemeObject> themes;
  String? countryCode;
  int? _macOSVersion;
  String? _serverVersion;

  /// [init] is run at start and fetches both the [appDocDir] and sets the [settings] to a default value
  Future<void> init() async {
    settings = Settings();
    if (!kIsWeb) {
      //ignore: unnecessary_cast, we need this as a workaround
      appDocDir = (await getApplicationSupportDirectory()) as Directory;
    }
  }

  /// Retreives files from disk and stores them in [settings]
  ///
  ///
  /// @param [headless] determines whether the socket will be started automatically and fcm will be initialized.
  ///
  /// @param [context] is an optional parameter to be used for setting the adaptive theme based on the settings.
  /// Setting to null will prevent the theme from being set and will be set to null in the background isolate
  Future<void> getSavedSettings({bool headless = false}) async {
    settings = Settings.getSettings();

    fcmData = FCMData.getFCM();
    if (headless) return;

    // If we aren't running in the background, then we should auto start the socket and authorize fcm just in case we haven't
    if (!headless) {
      try {
        SocketManager().startSocketIO();
        SocketManager().authFCM();
      } catch (_) {}
    }
  }

  /// Saves a [Settings] instance to disk
  ///
  /// @param [newSettings] are the settings to save
  Future<void> saveSettings(Settings newSettings) async {
    // Set the new settings as the current settings in the manager
    settings = newSettings;
    settings.save();
  }

  /// Updates the selected theme for the app
  ///
  /// @param [selectedLightTheme] is the [ThemeObject] of the light theme to save and set as light theme in the db
  ///
  /// @param [selectedDarkTheme] is the [ThemeObject] of the dark theme to save and set as dark theme in the db
  ///
  /// @param [context] is the [BuildContext] used to set the theme of the new settings
  void saveSelectedTheme(
    BuildContext context, {
    ThemeObject? selectedLightTheme,
    ThemeObject? selectedDarkTheme,
  }) {
    selectedLightTheme?.save();
    selectedDarkTheme?.save();
    ThemeObject.setSelectedTheme(light: selectedLightTheme?.id, dark: selectedDarkTheme?.id);

    ThemeData lightTheme = ThemeObject.getLightTheme().themeData;
    ThemeData darkTheme = ThemeObject.getDarkTheme().themeData;
    AdaptiveTheme.of(context).setTheme(
      light: lightTheme,
      dark: darkTheme,
      isDefault: true,
    );
  }

  /// Updates FCM data and saves to disk. It will also run [authFCM] automatically
  ///
  /// @param [data] is the [FCMData] to save
  void saveFCMData(FCMData data) {
    fcmData = data;
    fcmData!.save();
    SocketManager().authFCM();
  }

  Future<void> resetConnection() async {
    if (SocketManager().socket != null && SocketManager().socket!.connected) {
      SocketManager().socket!.disconnect();
    }

    Settings temp = settings;
    temp.finishedSetup.value = false;
    temp.guidAuthKey.value = "";
    temp.serverAddress.value = "";
    temp.lastIncrementalSync.value = 0;
    await saveSettings(temp);
  }

  FutureOr<int?> getMacOSVersion() async {
    if (_macOSVersion == null) {
      var res = await SocketManager().sendMessage("get-server-metadata", {}, (_) {});
      _macOSVersion = int.tryParse(res['data']['os_version'].split(".")[0]);
    }
    return _macOSVersion;
  }

  FutureOr<String?> getServerVersion() async {
    if (_macOSVersion == null) {
      var res = await SocketManager().sendMessage("get-server-metadata", {}, (_) {});
      _serverVersion = res['data']['server_version'];
    }
    return _serverVersion;
  }
}
