import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/conversation_view_mixin.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/new_chat_creator/contact_selector_custom_cupertino_textfield.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ChatSelectorTextField extends StatelessWidget {
  ChatSelectorTextField({
    Key? key,
    required this.controller,
    required this.onRemove,
    required this.selectedContacts,
    required this.allContacts,
    required this.isCreator,
    required this.onSelected,
    required this.inputFieldNode,
  }) : super(key: key);
  final TextEditingController controller;
  final Function(UniqueContact) onRemove;
  final bool isCreator;
  final List<UniqueContact> selectedContacts;
  final List<UniqueContact> allContacts;
  final Function(UniqueContact item) onSelected;
  final FocusNode inputFieldNode;

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [];
    selectedContacts.forEachIndexed((index, contact) {
      items.add(
        GestureDetector(
          onTap: () {
            onRemove(contact);
          },
          child: Padding(
            padding: EdgeInsets.only(right: 5.0, top: 2.0, bottom: 2.0),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(5.0)),
              child: Container(
                padding: EdgeInsets.all(5.0),
                color: Theme.of(context).primaryColor,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                        contact.displayName!.trim(),
                        style: Theme.of(context).textTheme.bodyText1),
                    SizedBox(
                      width: 5.0,
                    ),
                    InkWell(
                        child: Icon(
                      Icons.close,
                      size: 15.0,
                    ))
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });

    // Add the next text field
    items.add(
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 255.0),
        child: ContactSelectorCustomCupertinoTextfield(
          cursorColor: Theme.of(context).primaryColor,
          focusNode: inputFieldNode,
          onSubmitted: (String done) async {
            FocusScope.of(context).requestFocus(inputFieldNode);
            if (done.isEmpty) return;
            done = done.trim();
            if (done.isEmail || done.isPhoneNumber) {
              Contact? contact = ContactManager().getCachedContact(address: done);
              if (contact == null) {
                onSelected(
                    UniqueContact(address: done, displayName: done.isEmail ? done : await formatPhoneNumber(done)));
              } else {
                onSelected(UniqueContact(address: done, displayName: contact.displayName));
              }
            } else {
              if (allContacts.isEmpty) {
                showSnackbar('Error', "Invalid Number/Email, $done");
                // This is 4 chars due to invisible character
              } else if (controller.text.length >= 4) {
                onSelected(allContacts[0]);
              }
            }
          },
          controller: controller,
          maxLength: 50,
          maxLines: 1,
          autocorrect: false,
          placeholder: "  Type a name...",
          placeholderStyle: Theme.of(context).textTheme.subtitle1!,
          padding: EdgeInsets.only(right: 5.0, top: 2.0, bottom: 2.0),
          style: Theme.of(context).textTheme.bodyText1!.apply(
                color: ThemeData.estimateBrightnessForColor(Theme.of(context).backgroundColor) == Brightness.light
                    ? Colors.black
                    : Colors.white,
                fontSizeDelta: -0.25,
              ),
          decoration: BoxDecoration(
            color: Theme.of(context).backgroundColor,
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(left: 12.0, bottom: 10, top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              "To: ",
              style: Theme.of(context).textTheme.subtitle1,
            ),
          ),
          Flexible(
            flex: 1,
            fit: FlexFit.tight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: items,
              ),
            ),
          ),
          // Padding(
          //   padding: EdgeInsets.only(left: 12, right: 10.0),
          //   child: FlatButton(
          //     color: Theme.of(context).accentColor,
          //     onPressed: () async {
          //       // widget.onCreate();
          //     },
          //     child: Text(
          //       ChatSelector.of(context).widget.isCreator ? "Create" : "Add",
          //       style: Theme.of(context).textTheme.bodyText1,
          //     ),
          //   ),
          // )
        ],
      ),
    );
  }
}
