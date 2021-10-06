import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/layouts/setup/connecting_alert/failed_to_connect_dialog.dart';
import 'package:bluebubbles_wearos/layouts/setup/prepare_to_download/prepare_to_download.dart';
import 'package:bluebubbles_wearos/layouts/setup/qr_scan/qr_scan.dart';
import 'package:bluebubbles_wearos/layouts/setup/request_contact/request_contacts.dart';
import 'package:bluebubbles_wearos/layouts/setup/syncing_messages/syncing_messages.dart';
import 'package:bluebubbles_wearos/layouts/setup/welcome_page/welcome_page.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SetupView extends StatefulWidget {
  SetupView({Key? key}) : super(key: key);

  @override
  _SetupViewState createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  final controller = PageController(initialPage: 0);
  int currentPage = 1;

  @override
  void initState() {
    super.initState();
    ever(SocketManager().state, (event) {
      if (!SettingsManager().settings.finishedSetup.value && controller.hasClients && controller.page! > 3) {
        switch (event) {
          case SocketState.FAILED:
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => FailedToConnectDialog(
                onDismiss: () {
                  controller.animateToPage(
                    3,
                    duration: Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                  Navigator.of(context).pop();
                },
              ),
            );
            break;
          default:
            Logger.info("Default case: " + event.toString());
            break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        PageView(
          onPageChanged: (int page) {
            currentPage = page + 1;
            if (mounted) setState(() {});
          },
          physics: NeverScrollableScrollPhysics(),
          controller: controller,
          children: <Widget>[
            WelcomePage(
              controller: controller,
            ),
            RequestContacts(controller: controller),
            QRScan(
              controller: controller,
            ),
            PrepareToDownload(
              controller: controller,
            ),
            SyncingMessages(
              controller: controller,
            ),
          ],
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  "$currentPage/5",
                  style: Theme.of(context).textTheme.bodyText1,
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}
