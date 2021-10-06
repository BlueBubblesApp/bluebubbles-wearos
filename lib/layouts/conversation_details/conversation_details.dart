import 'dart:ui';

import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/blocs/message_bloc.dart';
import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/message_helper.dart';
import 'package:bluebubbles_wearos/helpers/ui_helpers.dart';
import 'package:bluebubbles_wearos/layouts/conversation_details/attachment_details_card.dart';
import 'package:bluebubbles_wearos/layouts/conversation_details/contact_tile.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

class ConversationDetails extends StatefulWidget {
  final Chat chat;
  final MessageBloc messageBloc;

  ConversationDetails({Key? key, required this.chat, required this.messageBloc}) : super(key: key);

  @override
  _ConversationDetailsState createState() => _ConversationDetailsState();
}

class _ConversationDetailsState extends State<ConversationDetails> {
  late TextEditingController controller;
  bool readOnly = true;
  late Chat chat;
  List<Attachment> attachmentsForChat = <Attachment>[];
  bool isClearing = false;
  bool isCleared = false;
  int maxPageSize = 5;
  bool showMore = false;
  bool showNameField = false;

  bool get shouldShowMore {
    return chat.participants.length > maxPageSize;
  }

  List<Handle> get participants {
    // If we are showing all, return everything
    if (showMore) return chat.participants;

    // If we aren't showing all, show the max we can show
    return chat.participants.length > maxPageSize ? chat.participants.sublist(0, maxPageSize) : chat.participants;
  }

  @override
  void initState() {
    super.initState();
    chat = widget.chat;
    readOnly = !(chat.participants.length > 1);
    controller = TextEditingController(text: chat.displayName);
    showNameField = chat.displayName?.isNotEmpty ?? false;
    fetchAttachments();

    ever(ChatBloc().chats, (List<Chat> chats) async {
      Chat? _chat = chats.firstWhereOrNull((e) => e.guid == widget.chat.guid);
      if (_chat == null) return;
      _chat.getParticipants();
      chat = _chat;
      readOnly = !(chat.participants.length > 1);
      if (mounted) setState(() {});
    });
  }

  void fetchAttachments() async {
    if (kIsWeb) {
      attachmentsForChat = CurrentChat.activeChat?.chatAttachments ?? [];
      if (attachmentsForChat.length > 25) attachmentsForChat = attachmentsForChat.sublist(0, 25);
      if (mounted) setState(() {});
      return;
    }
    attachmentsForChat = await chat.getAttachmentsAsync();
    if (attachmentsForChat.length > 25) attachmentsForChat = attachmentsForChat.sublist(0, 25);
    if (mounted) setState(() {});
  }

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
        backgroundColor: Theme.of(context).backgroundColor,
        appBar: CupertinoNavigationBar(
                backgroundColor: Theme.of(context).accentColor.withAlpha(125),
                automaticallyImplyLeading: false,
                middle: Text(
                  "Details",
                  style: Theme.of(context).textTheme.headline1,
                ),
              ),
        extendBodyBehindAppBar: true,
        body: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: EdgeInsets.symmetric(vertical: 25),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index >= participants.length && shouldShowMore) {
                  return ListTile(
                    onTap: () {
                      if (!mounted) return;
                      setState(() {
                        showMore = !showMore;
                      });
                    },
                    leading: Text(
                      showMore ? "Show less" : "Show more",
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    trailing: Padding(
                      padding: EdgeInsets.only(right: 15),
                      child: Icon(
                        Icons.more_horiz,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  );
                }

                if (index >= chat.participants.length) return Container();

                return ContactTile(
                  key: Key(chat.participants[index].address),
                  handle: chat.participants[index],
                  chat: chat,
                  updateChat: (Chat newChat) {
                    chat = newChat;
                    if (mounted) setState(() {});
                  },
                  canBeRemoved: chat.participants.length > 1,
                );
              }, childCount: participants.length + 1),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(vertical: 10),
            ),
            SliverToBoxAdapter(
              child: InkWell(
                onTap: () async {
                  await showDialog(
                    context: context,
                    builder: (context) =>
                        SyncDialog(chat: chat, withOffset: true, initialMessage: "Fetching messages...", limit: 100),
                  );

                  fetchAttachments();
                },
                child: ListTile(
                  leading: Text(
                    "Fetch more messages",
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  trailing: Padding(
                    padding: EdgeInsets.only(right: 15),
                    child: Icon(
                      Icons.file_download,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: InkWell(
                onTap: () async {
                  showDialog(
                    context: context,
                    builder: (context) => SyncDialog(chat: chat, initialMessage: "Syncing messages...", limit: 25),
                  );
                },
                child: ListTile(
                  leading: Text(
                    "Sync last 25 messages",
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  trailing: Padding(
                    padding: EdgeInsets.only(right: 15),
                    child: Icon(
                      Icons.replay,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: InkWell(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      isClearing = true;
                    });
                  }

                  try {
                    widget.chat.clearTranscript();
                    EventDispatcher().emit("refresh-messagebloc", {"chatGuid": widget.chat.guid});
                    if (mounted) {
                      setState(() {
                        isClearing = false;
                        isCleared = true;
                      });
                    }
                  } catch (ex) {
                    if (mounted) {
                      setState(() {
                        isClearing = false;
                        isCleared = false;
                      });
                    }
                  }
                },
                child: ListTile(
                  leading: Text(
                    "Clear Transcript (Local Only)",
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  trailing: Padding(
                    padding: EdgeInsets.only(right: 15),
                    child: (isClearing)
                        ? CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                          )
                        : (isCleared)
                            ? Icon(
                                Icons.done,
                                color: Theme.of(context).primaryColor,
                              )
                            : Icon(
                                Icons.delete_forever,
                                color: Theme.of(context).primaryColor,
                              ),
                  ),
                ),
              ),
            ),
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, int index) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).backgroundColor, width: 3),
                    ),
                    child: AttachmentDetailsCard(
                      attachment: attachmentsForChat[index],
                    ),
                  );
                },
                childCount: attachmentsForChat.length,
              ),
            ),
            SliverToBoxAdapter(child: Container(height: 50))
          ],
        ),
      ),
    );
  }
}

class SyncDialog extends StatefulWidget {
  SyncDialog({Key? key, required this.chat, this.initialMessage, this.withOffset = false, this.limit = 100})
      : super(key: key);
  final Chat chat;
  final String? initialMessage;
  final bool withOffset;
  final int limit;

  @override
  _SyncDialogState createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  String? errorCode;
  bool finished = false;
  String? message;
  double? progress;

  @override
  void initState() {
    super.initState();
    message = widget.initialMessage;
    syncMessages();
  }

  void syncMessages() {
    int offset = 0;
    if (widget.withOffset) {
      offset = Message.countForChat(widget.chat) ?? 0;
    }

    SocketManager().fetchMessages(widget.chat, offset: offset, limit: widget.limit)!.then((dynamic messages) {
      if (mounted) {
        setState(() {
          message = "Adding ${messages.length} messages...";
        });
      }

      MessageHelper.bulkAddMessages(widget.chat, messages, onProgress: (int progress, int length) {
        if (progress == 0 || length == 0) {
          this.progress = null;
        } else {
          this.progress = progress / length;
        }

        if (mounted) setState(() {});
      }).then((List<Message> __) {
        onFinish(true);
      });
    }).catchError((_) {
      onFinish(false);
    });
  }

  void onFinish([bool success = true]) {
    if (!mounted) return;
    if (success) Navigator.of(context).pop();
    if (!success) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(errorCode != null ? "Error!" : message!),
      content: errorCode != null
          ? Text(errorCode!)
          : Container(
              height: 5,
              child: Center(
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white,
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).primaryColor),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(
            "Ok",
            style: Theme.of(context).textTheme.bodyText1!.apply(
                  color: Theme.of(context).primaryColor,
                ),
          ),
        )
      ],
    );
  }
}
