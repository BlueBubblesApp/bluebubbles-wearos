import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:assorted_layout_widgets/assorted_layout_widgets.dart';
import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/hex_color.dart';
import 'package:bluebubbles_wearos/helpers/indicator.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/message_helper.dart';
import 'package:bluebubbles_wearos/helpers/message_marker.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/socket_singletons.dart';
import 'package:bluebubbles_wearos/helpers/ui_helpers.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/conversation_view.dart';
import 'package:bluebubbles_wearos/layouts/widgets/contact_avatar_group_widget.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/new_message_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/platform_file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

class ConversationTile extends StatefulWidget {
  final Chat chat;
  final List<PlatformFile> existingAttachments;
  final String? existingText;
  final Function(bool)? onSelect;
  final bool inSelectMode;
  final List<Chat> selected;
  final Widget? subtitle;

  ConversationTile({
    Key? key,
    required this.chat,
    this.existingAttachments = const [],
    this.existingText,
    this.onSelect,
    this.inSelectMode = false,
    this.selected = const [],
    this.subtitle,
  }) : super(key: key);

  @override
  _ConversationTileState createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  // Typing indicator
  bool showTypingIndicator = false;
  bool shouldHighlight = false;

  bool get selected {
    if (widget.selected.isEmpty) return false;
    return widget.selected.where((element) => widget.chat.guid == element.guid).isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    // Listen for changes in the group
    NewMessageManager().stream.listen((NewMessageEvent event) async {
      // Make sure we have the required data to qualify for this tile
      if (event.chatGuid != widget.chat.guid) return;
      if (!event.event.containsKey("message")) return;
      if (widget.chat.guid == null) return;
      // Make sure the message is a group event
      Message message = event.event["message"];
      if (!message.isGroupEvent()) return;

      // If it's a group event, let's fetch the new information and save it
      try {
        await fetchChatSingleton(widget.chat.guid!);
      } catch (ex) {
        Logger.error(ex.toString());
      }

      setNewChatData(forceUpdate: true);
    });
  }

  void update() {
    setState(() {});
  }

  void setNewChatData({forceUpdate = false}) {
    // Save the current participant list and get the latest
    List<Handle> ogParticipants = widget.chat.participants;
    widget.chat.getParticipants();

    // Save the current title and generate the new one
    String? ogTitle = widget.chat.title;
    widget.chat.getTitle();

    // If the original data is different, update the state
    if (ogTitle != widget.chat.title || ogParticipants.length != widget.chat.participants.length || forceUpdate) {
      if (mounted) setState(() {});
    }
  }

  void onTapUp(details) {
    if (widget.inSelectMode && widget.onSelect != null) {
      onSelect();
    } else {
      CustomNavigator.pushAndRemoveUntil(
        context,
        ConversationView(
          chat: widget.chat,
          existingAttachments: widget.existingAttachments,
          existingText: widget.existingText,
        ),
        (route) => route.isFirst,
      );
    }
  }

  void onTapUpBypass() {
    onTapUp(TapUpDetails(kind: PointerDeviceKind.touch));
  }

  Widget buildTitle() {
    TextStyle? style = Theme.of(context).textTheme.bodyText1;
    widget.chat.getTitle();
    String? title = widget.chat.title ?? "Fake Person";

    return TextOneLine(title, style: style, overflow: TextOverflow.ellipsis);
  }

  Widget buildSubtitle() {
    String latestText = widget.chat.latestMessage != null
        ? MessageHelper.getNotificationText(widget.chat.latestMessage!)
        : widget.chat.latestMessageText ?? "";
    TextStyle style = Theme.of(context).textTheme.subtitle1!.apply(
      color: Theme.of(context).textTheme.subtitle1!.color!.withOpacity(
        0.85,
      ),
    );

    return Text(
      latestText,
      style: style,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  Widget buildLeading() {
    return StreamBuilder<Map<String, dynamic>>(
        stream: CurrentChat.getCurrentChat(widget.chat)?.stream as Stream<Map<String, dynamic>>?,
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.active &&
              snapshot.hasData &&
              snapshot.data["type"] == CurrentChatEvent.TypingStatus) {
            showTypingIndicator = snapshot.data["data"];
          }
          double height = Theme.of(context).textTheme.subtitle1!.fontSize! * 1.25;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(top: 2, right: 2),
                child: !selected
                    ? ContactAvatarGroupWidget(
                        chat: widget.chat,
                        size: 40,
                        editable: false,
                        onTap: onTapUpBypass,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: Theme.of(context).primaryColor,
                        ),
                        width: 40,
                        height: 40,
                        child: Center(
                          child: Icon(
                            Icons.check,
                            color: Theme.of(context).textTheme.bodyText1!.color,
                            size: 20,
                          ),
                        ),
                      ),
              ),
            ],
          );
        });
  }

  void onTap() {
    CustomNavigator.pushAndRemoveUntil(
      context,
      ConversationView(
        chat: widget.chat,
        existingAttachments: widget.existingAttachments,
        existingText: widget.existingText,
      ),
      (route) => route.isFirst,
    );
  }

  void onSelect() {
    if (widget.onSelect != null) {
      widget.onSelect!(!selected);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Cupertino(
      parent: this,
      parentProps: widget,
    );
  }
}

class _Cupertino extends StatelessWidget {
  _Cupertino({Key? key, required this.parent, required this.parentProps}) : super(key: key);
  final _ConversationTileState parent;
  final ConversationTile parentProps;

  @override
  Widget build(BuildContext context) {
    return Material(
        color:
            parent.shouldHighlight ? Theme.of(context).primaryColor.withAlpha(120) : Theme.of(context).backgroundColor,
        borderRadius: BorderRadius.circular(parent.shouldHighlight ? 5 : 0),
        child: GestureDetector(
          onTapUp: (details) {
            parent.onTapUp(details);
          },
          onSecondaryTapUp: (details) async {
            parent.update();
            await showConversationTileMenu(
              context,
              this,
              parent.widget.chat,
              details.globalPosition,
              context.textTheme,
            );
            parent.shouldHighlight = false;
            parent.update();
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            ChatBloc().toggleChatUnread(parent.widget.chat, !parent.widget.chat.hasUnreadMessage!);
            if (parent.mounted) parent.update();
          },
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.only(left: 10),
                minVerticalPadding: 10,
                title: Container(
                  width: MediaQuery.of(context).size.width - 20,
                  child: Row(
                    children: [
                      parent.buildLeading(),
                      SizedBox(width: 10),
                      Container(
                        width: MediaQuery.of(context).size.width - 75,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            parent.buildTitle(),
                            parent.widget.subtitle ?? parent.buildSubtitle()
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Container(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          (parent.widget.chat.muteType != "mute" && parent.widget.chat.hasUnreadMessage!)
                              ? Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(35),
                                    color: Theme.of(context).primaryColor.withOpacity(0.8),
                                  ),
                                  width: 10,
                                  height: 10,
                                )
                              : Container(),
                          parent.widget.chat.isPinned!
                              ? Icon(
                                  CupertinoIcons.pin,
                                  size: 10,
                                  color: Colors
                                      .yellow[AdaptiveTheme.of(context).mode == AdaptiveThemeMode.dark ? 100 : 700],
                                )
                              : Container(),
                        ],
                      ),
                      parent.widget.chat.muteType == "mute"
                          ? SvgPicture.asset(
                              "assets/icon/moon.svg",
                              color: parentProps.chat.hasUnreadMessage!
                                  ? Theme.of(context).primaryColor.withOpacity(0.8)
                                  : Theme.of(context).textTheme.subtitle1!.color,
                              width: 10,
                              height: 10,
                            )
                          : Container()
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
