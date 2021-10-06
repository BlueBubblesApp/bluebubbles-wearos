import 'dart:math';
import 'dart:ui';

import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/ui_helpers.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_list/conversation_list.dart';
import 'package:bluebubbles_wearos/layouts/conversation_list/conversation_tile.dart';
import 'package:bluebubbles_wearos/layouts/conversation_list/pinned_conversation_tile.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class CupertinoConversationList extends StatefulWidget {
  const CupertinoConversationList({Key? key, required this.parent}) : super(key: key);

  final ConversationListState parent;

  @override
  State<StatefulWidget> createState() => CupertinoConversationListState();
}

class CupertinoConversationListState extends State<CupertinoConversationList> {
  final key = GlobalKey<NavigatorState>();
  bool openedChatAlready = false;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: context.theme.backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            context.theme.backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: buildChatList(context, false),
    );
  }

  Widget buildChatList(BuildContext context, bool showAltLayout) {
    bool showArchived = widget.parent.widget.showArchivedChats;
    bool showUnknown = widget.parent.widget.showUnknownSenders;
    Brightness brightness = ThemeData.estimateBrightnessForColor(context.theme.backgroundColor);
    return Scaffold(
        appBar: kIsWeb || kIsDesktop
            ? null
            : PreferredSize(
                preferredSize: Size(
                  (showAltLayout) ? CustomNavigator.width(context) * 0.33 : CustomNavigator.width(context),
                  40,
                ),
                child: ClipRRect(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: AppBar(
                        iconTheme: IconThemeData(color: context.theme.primaryColor),
                        elevation: 0,
                        backgroundColor: Get.context!.theme.accentColor.withOpacity(0.5),
                        centerTitle: true,
                        brightness: brightness,
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            Text(
                              showArchived
                                  ? "Archive"
                                  : showUnknown
                                  ? "Unknown Senders"
                                  : "Messages",
                              style: context.textTheme.bodyText1,
                            ),
                          ],
                        ),
                      ),),
                ),
              ),
        backgroundColor: context.theme.backgroundColor,
        extendBodyBehindAppBar: true,
        body: CustomScrollView(
          controller: widget.parent.scrollController,
          slivers: <Widget>[
            // todo add archived back
            SliverPadding(padding: EdgeInsets.only(top: 50),),
            Obx(() {
              ChatBloc().chats.archivedHelper(showArchived).sort(Chat.sort);
              if (!ChatBloc().loadedChatBatch.value) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.only(top: 50.0),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              "Loading chats...",
                              style: Theme.of(context).textTheme.subtitle1,
                            ),
                          ),
                          buildProgressIndicator(context, size: 15),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (ChatBloc().loadedChatBatch.value && !ChatBloc().hasChats.value) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.only(top: 50.0),
                      child: Text(
                        showArchived
                            ? "You have no archived chats :("
                            : showUnknown
                                ? "You have no messages from unknown senders :)"
                                : "You have no chats :(",
                        style: Theme.of(context).textTheme.subtitle1,
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return ListTile(
                        onTap: widget.parent.openNewChatCreator,
                        tileColor: context.theme.accentColor,
                        title: Container(
                          width: MediaQuery.of(context).size.width - 20,
                          child: Row(
                            children: [
                              Icon(Icons.message, color: Colors.white, size: 25),
                              SizedBox(width: 20),
                              Container(
                                width: MediaQuery.of(context).size.width - 80,
                                child: Text("New Conversation", style: context.theme.textTheme.bodyText1)
                              ),
                            ],
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: BorderSide.none,
                        ),
                      );
                    }
                    return ConversationTile(
                      key: Key(ChatBloc()
                          .chats
                          .archivedHelper(showArchived)[index - 1]
                          .guid
                          .toString()),
                      chat: ChatBloc()
                          .chats
                          .archivedHelper(showArchived)[index - 1],
                    );
                  },
                  childCount: ChatBloc()
                      .chats
                      .archivedHelper(showArchived)
                      .length + 1,
                ),
              );
            }),
          ],
        ),
      );
  }
}
