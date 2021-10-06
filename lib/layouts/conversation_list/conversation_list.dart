import 'dart:ui';

import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_list/cupertino_conversation_list.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/conversation_view.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class ConversationList extends StatefulWidget {
  ConversationList({Key? key, required this.showArchivedChats, required this.showUnknownSenders}) : super(key: key);

  final bool showArchivedChats;
  final bool showUnknownSenders;

  @override
  ConversationListState createState() => ConversationListState();
}

class ConversationListState extends State<ConversationList> {
  Color? currentHeaderColor;
  bool hasPinnedChats = false;
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (kIsDesktop && !widget.showUnknownSenders) {
      ChatBloc().refreshChats();
    }

    SystemChannels.textInput.invokeMethod('TextInput.hide').catchError((e) {
      Logger.error("Error caught while hiding keyboard: ${e.toString()}");
    });

    // Listen for any incoming events
    EventDispatcher().stream.listen((Map<String, dynamic> event) {
      if (!event.containsKey("type")) return;

      if (event["type"] == 'refresh' && mounted) {
        setState(() {});
      }
    });
  }

  Widget getHeaderTextWidget({double? size}) {
    TextStyle? style = context.textTheme.headline1;
    if (size != null) style = style!.copyWith(fontSize: size);

    return Padding(
      padding: const EdgeInsets.only(right: 10.0),
      child: Text(widget.showArchivedChats ? "Archive" : widget.showUnknownSenders ? "Unknown Senders" : "Messages", style: style),
    );
  }

  void openNewChatCreator({List<PlatformFile>? existing}) {
    EventDispatcher().emit("update-highlight", null);
    CustomNavigator.pushAndRemoveUntil(
      context,
      ConversationView(
        isCreator: true,
        existingAttachments: existing ?? [],
      ),
      (route) => route.isFirst,
    );
  }

  Widget buildSettingsButton() => !widget.showArchivedChats && !widget.showUnknownSenders
      ? PopupMenuButton(
          color: context.theme.accentColor,
          onSelected: (dynamic value) {
            if (value == 0) {
              ChatBloc().markAllAsRead();
            } else if (value == 1) {
              CustomNavigator.pushLeft(
                context,
                ConversationList(
                  showArchivedChats: true,
                  showUnknownSenders: false,
                )
              );
            }
          },
          itemBuilder: (context) {
            return <PopupMenuItem>[
              PopupMenuItem(
                value: 0,
                child: Text(
                  'Mark all as read',
                  style: context.textTheme.bodyText1,
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Text(
                  'Archived',
                  style: context.textTheme.bodyText1,
                ),
              ),
            ];
          },
          child: Icon(
            Icons.more_vert,
            color: context.textTheme.bodyText1!.color,
            size: 25,
          ),
        )
      : Container();

  @override
  Widget build(BuildContext context) {
    return CupertinoConversationList(parent: this);
  }
}
