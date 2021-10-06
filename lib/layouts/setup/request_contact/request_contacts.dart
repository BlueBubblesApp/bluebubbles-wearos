import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RequestContacts extends StatefulWidget {
  RequestContacts({Key? key, required this.controller}) : super(key: key);
  final PageController controller;

  @override
  _RequestContactsState createState() => _RequestContactsState();
}

class _RequestContactsState extends State<RequestContacts> {
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
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                "Access Contacts?",
                style: Theme.of(context).textTheme.bodyText1!,
                textAlign: TextAlign.center,
              ),
            ),
            Container(height: 20.0),
            ClipOval(
              child: Material(
                color: Theme.of(context).primaryColor, // button color
                child: InkWell(
                  child: SizedBox(width: 60, height: 60, child: Icon(Icons.check, color: Colors.white)),
                  onTap: () async {
                    if (!(await ContactManager().canAccessContacts())) {
                      bool result = await showDialog(
                        context: context,
                        builder: (context) => ContactPermissionWarningDialog(),
                      );
                      if (result) continueToNextPage();
                    } else {
                      continueToNextPage();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void continueToNextPage() {
    widget.controller.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

class ContactPermissionWarningDialog extends StatefulWidget {
  ContactPermissionWarningDialog({Key? key}) : super(key: key);

  @override
  _ContactPermissionWarningDialogState createState() => _ContactPermissionWarningDialogState();
}

class _ContactPermissionWarningDialogState extends State<ContactPermissionWarningDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actions: [
        TextButton(
          child: Text(
            "Accept",
            style: Theme.of(context).textTheme.bodyText1!.apply(color: Theme.of(context).primaryColor),
          ),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
        TextButton(
          child: Text(
            "Cancel",
            style: Theme.of(context).textTheme.bodyText1!.apply(color: Theme.of(context).primaryColor),
          ),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
      ],
      title: Text("Failed to get Contact Permission"),
      content: Text(
          "We were unable to get contact permissions. It is recommended to use BlueBubbles with contacts. Are you sure you want to proceed?"),
    );
  }
}
