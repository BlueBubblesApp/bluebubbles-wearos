import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ignore: non_constant_identifier_names
BaseNavigator CustomNavigator = Get.isRegistered<BaseNavigator>() ? Get.find<BaseNavigator>() : Get.put(BaseNavigator());

/// Handles navigation for the app
class BaseNavigator extends GetxService {
  /// width of left side of split screen view
  double? _widthChatListLeft;
  /// width of right side of split screen view
  double? _widthChatListRight;
  /// width of settings right side split screen
  double? _widthSettings;

  set maxWidthLeft(double w) => _widthChatListLeft = w;
  set maxWidthRight(double w) => _widthChatListRight = w;
  set maxWidthSettings(double w) => _widthSettings = w;

  /// grab the available screen width, returning the split screen width if applicable
  /// this should *always* be used in place of context.width or similar
  double width(BuildContext context) {
    if (Navigator.of(context).widget.key?.toString().contains("Getx nested key: 1") ?? false) {
      return _widthChatListLeft ?? context.width;
    } else if (Navigator.of(context).widget.key?.toString().contains("Getx nested key: 2") ?? false) {
      return _widthChatListRight ?? context.width;
    } else if (Navigator.of(context).widget.key?.toString().contains("Getx nested key: 3") ?? false) {
      return _widthSettings ?? context.width;
    }
    return context.width;
  }

  /// Push a new route onto the chat list right side navigator
  void push(BuildContext context, Widget widget) {
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (BuildContext context) => widget,
    ));
  }

  /// Push a new route onto the chat list left side navigator
  void pushLeft(BuildContext context, Widget widget) {
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (BuildContext context) => widget,
    ));
  }

  /// Push a new route onto the settings navigator
  void pushSettings(BuildContext context, Widget widget, {Bindings? binding}) {
    binding?.dependencies();
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (BuildContext context) => widget,
    ));
  }

  /// Push a new route, popping all previous routes, on the chat list right side navigator
  void pushAndRemoveUntil(BuildContext context, Widget widget, bool Function(Route) predicate) {
    Navigator.of(context).pushAndRemoveUntil(CupertinoPageRoute(
      builder: (BuildContext context) => widget,
    ), predicate);
  }

  /// Push a new route, popping all previous routes, on the settings navigator
  void pushAndRemoveSettingsUntil(BuildContext context, Widget widget, bool Function(Route) predicate, {Bindings? binding}) {
    binding?.dependencies();
    // only push here because we don't want to remove underlying routes when in portrait
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (BuildContext context) => widget,
    ));
  }

  void backSettingsCloseOverlays(BuildContext context) {
    Get.back(closeOverlays: true);
  }
}
