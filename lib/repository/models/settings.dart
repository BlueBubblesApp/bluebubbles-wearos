import 'dart:async';

import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/reaction.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/main.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

class Settings {
  final RxString guidAuthKey = "".obs;
  final RxString serverAddress = "".obs;
  final RxBool finishedSetup = false.obs;
  final RxInt lastIncrementalSync = 0.obs;

  Settings();

  Settings save() {
    Map<String, dynamic> map = toMap();
    map.forEach((key, value) {
      if (value is bool) {
        prefs.setBool(key, value);
      } else if (value is String) {
        prefs.setString(key, value);
      } else if (value is int) {
        prefs.setInt(key, value);
      } else if (value is double) {
        prefs.setDouble(key, value);
      }
    });
    return this;
  }

  static Settings getSettings() {
    Set<String> keys = prefs.getKeys();

    Map<String, dynamic> items = {};
    for (String s in keys) {
      items[s] = prefs.get(s);
    }
    if (items.isNotEmpty) {
      return Settings.fromMap(items);
    } else {
      return Settings();
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'guidAuthKey': guidAuthKey.value,
      'serverAddress': serverAddress.value,
      'finishedSetup': finishedSetup.value,
      'lastIncrementalSync': lastIncrementalSync.value,
    };
  }

  static Settings fromMap(Map<String, dynamic> map) {
    Settings s = Settings();
    s.guidAuthKey.value = map['guidAuthKey'] ?? "";
    s.serverAddress.value = map['serverAddress'] ?? "";
    s.finishedSetup.value = map['finishedSetup'] ?? false;
    s.lastIncrementalSync.value = map['lastIncrementalSync'] ?? 0;
    return s;
  }
}
