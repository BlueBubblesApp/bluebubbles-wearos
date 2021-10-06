import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/hex_color.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactAvatarWidget extends StatefulWidget {
  ContactAvatarWidget({
    Key? key,
    this.size,
    this.fontSize,
    this.borderThickness = 2.0,
    this.editable = true,
    this.onTap,
    required this.handle,
  }) : super(key: key);
  final Handle? handle;
  final double? size;
  final double? fontSize;
  final double borderThickness;
  final bool editable;
  final Function? onTap;

  @override
  _ContactAvatarWidgetState createState() => _ContactAvatarWidgetState();
}

class _ContactAvatarWidgetState extends State<ContactAvatarWidget> with AutomaticKeepAliveClientMixin {
  Contact? contact;

  String get keyPrefix => widget.handle?.address ?? randomString(8);

  @override
  void initState() {
    super.initState();
    contact = ContactManager().getCachedContact(handle: widget.handle);
    EventDispatcher().stream.listen((Map<String, dynamic> event) {
      if (!event.containsKey("type")) return;

      if (event["type"] == 'refresh-avatar' && event["data"][0] == widget.handle?.address && mounted) {
        widget.handle?.color = event['data'][1];
        setState(() {});
      }
    });
  }

  String? getInitials({Handle? handle, double size = 30}) {
    if (handle == null) return "Y";
    String? name = ContactManager().getContactTitle(handle) ?? "Unknown Name";
    if (name.isEmail) return name[0].toUpperCase();

    // Check if it's just a regular number, no contact
    if (name.isPhoneNumber) return null;

    List<String> items = name.split(" ").where((element) => element.isNotEmpty).toList();
    switch (items.length) {
      case 1:
        return items[0][0].toUpperCase();
      default:
        if (items.length - 1 < 0 || items[items.length - 1].isEmpty) return "";
        String first = items[0][0].toUpperCase();
        String last = items[items.length - 1][0].toUpperCase();
        if (!last.contains(RegExp('[A-Za-z]'))) last = items[1][0];
        if (!last.contains(RegExp('[A-Za-z]'))) last = "";
        return first + last;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      key: Key("$keyPrefix-avatar-container"),
      width: widget.size ?? 40,
      height: widget.size ?? 40,
      padding: EdgeInsets.all(widget.borderThickness),
      decoration: BoxDecoration(
        color: context.theme.backgroundColor, // border color
        shape: BoxShape.circle,
      ),
      child: Obx(() {
        List<Color> colors = [];
        if (widget.handle?.color == null) {
          colors = toColorGradient(widget.handle?.address);
        } else {
          colors = [
            HexColor(widget.handle!.color!).lightenAmount(0.02),
            HexColor(widget.handle!.color!),
          ];
        }
        return CircleAvatar(
          key: Key("$keyPrefix-avatar"),
          radius: (widget.size != null) ? widget.size! / 2 : 20,
          backgroundImage: contact?.avatar.value != null
              ? MemoryImage(contact!.avatar.value!)
              : null,
          child: contact?.avatar.value == null
              ? Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      colors: [
                        colors.isNotEmpty
                                ? colors[1]
                                : HexColor("928E8E"),
                        colors.isNotEmpty
                                ? colors[0]
                                : HexColor("686868")
                      ],
                    ),
                    borderRadius: BorderRadius.circular(widget.size ?? 40),
                  ),
                  child: Container(
                    child: getInitials(handle: widget.handle) == null
                        ? Icon(
                            CupertinoIcons.person_fill,
                            key: Key("$keyPrefix-avatar-icon"),
                            size: (widget.size ?? 40) / 2,
                          )
                        : Text(
                            getInitials(handle: widget.handle)!,
                            key: Key("$keyPrefix-avatar-text"),
                            style: TextStyle(
                              fontSize: widget.fontSize ?? 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                    alignment: AlignmentDirectional.center,
                  ),
                )
              : null,
        );
      }),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
