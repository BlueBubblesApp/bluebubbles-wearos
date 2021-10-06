import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrepareToDownload extends StatefulWidget {
  PrepareToDownload({Key? key, required this.controller}) : super(key: key);
  final PageController controller;

  @override
  _PrepareToDownloadState createState() => _PrepareToDownloadState();
}

class _PrepareToDownloadState extends State<PrepareToDownload> {
  double numberOfMessages = 25;
  bool downloadAttachments = false;
  bool skipEmptyChats = true;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
        backgroundColor: Theme.of(context).accentColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ClipOval(
                child: Material(
                  color: Colors.green.withAlpha(200), // button color
                  child: InkWell(
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: Icon(
                        Icons.cloud_download,
                        color: Colors.white,
                      ),
                    ),
                    onTap: () async {
                      // Set the number of messages to sync
                      SocketManager().setup.numberOfMessagesPerPage = numberOfMessages;
                      SocketManager().setup.downloadAttachments = downloadAttachments;
                      SocketManager().setup.skipEmptyChats = skipEmptyChats;

                      // Start syncing
                      SocketManager().setup.startFullSync(SettingsManager().settings);
                      widget.controller.nextPage(
                        duration: Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
