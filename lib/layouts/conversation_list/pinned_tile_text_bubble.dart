import 'dart:math';
import 'dart:ui';

import 'package:bluebubbles_wearos/helpers/message_helper.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PinnedTileTextBubble extends StatelessWidget {
  PinnedTileTextBubble({
    Key? key,
    required this.chat,
    required this.size,
  }) : super(key: key);

  final Chat chat;
  final double size;

  @override
  Widget build(BuildContext context) {
    bool showTail = !chat.isGroup();
    if (!(chat.hasUnreadMessage ?? false)) return Container();
    Message message = chat.latestMessageGetter;
    bool leftSide = Random(message.id).nextBool();

    String messageText = MessageHelper.getNotificationText(message);
    if (message.associatedMessageGuid != null || message.isFromMe! || isNullOrEmpty(messageText, trimString: true)!) {
      return Container();
    }

    TextStyle style = Get.textTheme.subtitle1!.apply(fontSizeFactor: 0.85);

    return Align(
      alignment: showTail
          ? leftSide
              ? Alignment.centerLeft
              : Alignment.centerRight
          : Alignment.center,
      child: Padding(
        padding: EdgeInsets.only(
          left: showTail
              ? leftSide
                  ? size * 0.06
                  : size * 0.02
              : size * 0.04,
          right: showTail
              ? leftSide
                  ? size * 0.02
                  : size * 0.06
              : size * 0.04,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            if (showTail)
              Positioned(
                top: -8.5,
                right: leftSide ? null : 7,
                left: leftSide ? 7 : null,
                child: CustomPaint(
                  size: Size(18, 9),
                  painter: TailPainter(leftSide: leftSide),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: showTail ? 30 : 0),
              child: ClipRRect(
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(10.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 2,
                    sigmaY: 2,
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      vertical: 3.0,
                      horizontal: 6.0,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.0),
                      color: context.theme.accentColor.withOpacity(0.8),
                    ),
                    child: Text(
                      messageText,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TailPainter extends CustomPainter {
  TailPainter({
    Key? key,
    required this.leftSide,
  });

  final bool leftSide;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = Get.theme.accentColor.withOpacity(0.8);
    Path path = Path();

    if (leftSide) {
      path.moveTo(size.width * 0.9355556, size.height * 0.1489091);
      path.cubicTo(size.width, size.height * 0.3262727, size.width * 0.6313889, size.height * 0.5667273,
          size.width * 0.7722222, size.height * 0.8181818);
      path.cubicTo(size.width * 0.8054444, size.height * 0.8875455, size.width * 0.9209444, size.height, size.width,
          size.height);
      path.cubicTo(size.width * 0.7504167, size.height, size.width * 0.2523611, size.height, 0, size.height);
      path.cubicTo(size.width * 0.2253889, size.height * 0.9245455, size.width * 0.2102778, size.height * 0.6476364,
          size.width * 0.5255556, size.height * 0.3018182);
      path.cubicTo(size.width * 0.7247778, size.height * 0.0966364, size.width * 0.8862222, size.height * 0.0308182,
          size.width * 0.9355556, size.height * 0.1489091);
      path.close();
    } else {
      path.moveTo(size.width * 0.0644444, size.height * 0.1489091);
      path.cubicTo(0, size.height * 0.3262727, size.width * 0.3686111, size.height * 0.5667273, size.width * 0.2277778,
          size.height * 0.8181818);
      path.cubicTo(
          size.width * 0.1945556, size.height * 0.8875455, size.width * 0.0790556, size.height, 0, size.height);
      path.cubicTo(size.width * 0.2495833, size.height, size.width * 0.7476389, size.height, size.width, size.height);
      path.cubicTo(size.width * 0.7746111, size.height * 0.9245455, size.width * 0.7987222, size.height * 0.6476364,
          size.width * 0.4744444, size.height * 0.3018182);
      path.cubicTo(size.width * 0.2752222, size.height * 0.0966364, size.width * 0.1137778, size.height * 0.0308182,
          size.width * 0.0644444, size.height * 0.1489091);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
