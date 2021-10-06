import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/layouts/widgets/circle_progress_bar.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tuple/tuple.dart';

class MediaFile extends StatefulWidget {
  MediaFile({
    Key? key,
    required this.child,
    required this.attachment,
  }) : super(key: key);
  final Widget child;
  final Attachment attachment;

  @override
  _MediaFileState createState() => _MediaFileState();
}

class _MediaFileState extends State<MediaFile> {
  @override
  void initState() {
    super.initState();
    SocketManager().attachmentSenderCompleter.listen((event) {
      if (event == widget.attachment.guid && mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      widget.child,
      if (widget.attachment.originalROWID == null)
        Container(
          child: Theme(
            data: ThemeData(
              cupertinoOverrideTheme: CupertinoThemeData(brightness: Brightness.dark),
            ),
            child: CupertinoActivityIndicator(
              radius: 10,
            ),
          ),
          height: 45,
          width: 45,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(10)), color: Colors.black.withOpacity(0.5)),
        ),
    ]);
  }
}
