import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/message_helper.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Map<String, IconData> iconMap = {
  'com.apple.Handwriting.HandwritingProvider':
      Icons.brush,
  'com.apple.DigitalTouchBalloonProvider':
      Icons.touch_app
};

class BalloonBundleWidget extends StatefulWidget {
  BalloonBundleWidget({
    Key? key,
    required this.message,
  }) : super(key: key);
  final Message? message;

  @override
  _BalloonBubbleState createState() => _BalloonBubbleState();
}

class _BalloonBubbleState extends State<BalloonBundleWidget> {
  late String bundleName;
  late IconData bundleIcon;

  @override
  void initState() {
    super.initState();

    bundleName = MessageHelper.getInteractiveText(widget.message!);
    bundleIcon = getIcon();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {
      bundleName = MessageHelper.getInteractiveText(widget.message!);
      bundleIcon = getIcon();
    });
  }

  IconData getIcon() {
    if (widget.message!.balloonBundleId == null) return Icons.device_unknown;
    if (nameMap.containsKey(widget.message!.balloonBundleId)) {
      return iconMap[widget.message!.balloonBundleId!]!;
    }

    String val = widget.message!.balloonBundleId!.toLowerCase();
    if (val.contains("gamepigeon")) {
      return Icons.games;
    } else if (val.contains("contextoptional")) {
      return Icons.phone_android;
    } else if (val.contains("mobileslideshow")) {
      return Icons.slideshow;
    } else if (val.contains("PeerPayment")) {
      return Icons.monetization_on;
    }

    return Icons.apps;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
          constraints: BoxConstraints(
            maxWidth: CustomNavigator.width(context) * 3 / 4,
          ),
          child: Container(
            width: 200,
            color: Theme.of(context).accentColor,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(bundleName,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headline1),
                  Text("Interactive Message",
                      textAlign: TextAlign.center, maxLines: 1, style: Theme.of(context).textTheme.subtitle1),
                  Container(height: 10.0),
                  Icon(bundleIcon, color: Theme.of(context).textTheme.bodyText1!.color, size: 48),
                  Container(height: 10.0),
                  Text("(Cannot open on Android)",
                      textAlign: TextAlign.center, maxLines: 1, style: Theme.of(context).textTheme.subtitle2),
                ],
              ),
            ),
          )),
    );
  }
}
