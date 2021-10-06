import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:bluebubbles_wearos/action_handler.dart';
import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/helpers/attachment_helper.dart';
import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/darty.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/metadata_helper.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/reaction.dart';
import 'package:bluebubbles_wearos/helpers/share.dart';
import 'package:bluebubbles_wearos/helpers/themes.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/conversation_view.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/conversation_view_mixin.dart';
import 'package:bluebubbles_wearos/layouts/widgets/custom_cupertino_alert_dialog.dart';
import 'package:bluebubbles_wearos/layouts/widgets/custom_cupertino_nav_bar.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/reaction_detail_widget.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/life_cycle_manager.dart';
import 'package:bluebubbles_wearos/managers/method_channel_interface.dart';
import 'package:bluebubbles_wearos/managers/new_message_manager.dart';
import 'package:bluebubbles_wearos/managers/notification_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/platform_file.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:sprung/sprung.dart';
import 'package:url_launcher/url_launcher.dart';

class MessageDetailsPopup extends StatefulWidget {
  MessageDetailsPopup({
    Key? key,
    required this.message,
    required this.childOffset,
    required this.childSize,
    required this.child,
    required this.currentChat,
  }) : super(key: key);

  final Message message;
  final Offset childOffset;
  final Size? childSize;
  final Widget child;
  final CurrentChat? currentChat;

  @override
  MessageDetailsPopupState createState() => MessageDetailsPopupState();
}

class MessageDetailsPopupState extends State<MessageDetailsPopup> with TickerProviderStateMixin {
  List<Widget> reactionWidgets = <Widget>[];
  bool showTools = false;
  String? selfReaction;
  String? currentlySelectedReaction;
  CurrentChat? currentChat;
  Chat? dmChat;

  late double messageTopOffset;
  late double topMinimum;
  double? height;

  @override
  void initState() {
    super.initState();
    currentChat = widget.currentChat;

    messageTopOffset = widget.childOffset.dy;
    topMinimum = CupertinoNavigationBar().preferredSize.height + (widget.message.hasReactions ? 110 : 50);

    dmChat = ChatBloc().chats.firstWhereOrNull(
          (chat) =>
              !chat.isGroup() && chat.participants.where((handle) => handle.id == widget.message.handleId).length == 1,
        );

    fetchReactions();

    // Animate showing the copy menu, slightly delayed
    Future.delayed(Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          showTools = true;
        });
      }
    });

    SchedulerBinding.instance!.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          double totalHeight = context.height - detailsMenuHeight! - 20;
          double offset = (widget.childOffset.dy + widget.childSize!.height) - totalHeight;
          messageTopOffset = widget.childOffset.dy.clamp(topMinimum + 40, double.infinity);
          if (offset > 0) {
            messageTopOffset -= offset;
            messageTopOffset = messageTopOffset.clamp(topMinimum + 40, double.infinity);
          }
        });
      }
    });
  }

  void fetchReactions() {
    // If there are no associated messages, return now
    List<Message> reactions = widget.message.getReactions();
    // Filter down the messages to the unique ones (one per user, newest)
    List<Message> reactionMessages = Reaction.getUniqueReactionMessages(reactions);

    reactionWidgets = [];
    for (Message reaction in reactionMessages) {
      reaction.handle ??= reaction.getHandle();
      if (reaction.isFromMe!) {
        selfReaction = reaction.associatedMessageType;
        currentlySelectedReaction = selfReaction;
      }
      reactionWidgets.add(
        ReactionDetailWidget(
          handle: reaction.handle,
          message: reaction,
        ),
      );
    }
  }

  void sendReaction(String type) {
    Logger.info("Sending reaction type: " + type);
    ActionHandler.sendReaction(widget.currentChat!.chat, widget.message, type);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    bool isSent = !widget.message.guid!.startsWith('temp') && !widget.message.guid!.startsWith('error');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    color: oledDarkTheme.accentColor.withOpacity(0.3),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: Duration(milliseconds: 250),
                curve: Curves.easeOut,
                top: messageTopOffset,
                left: widget.childOffset.dx,
                child: Container(
                  width: widget.childSize!.width,
                  height: widget.childSize!.height,
                  child: widget.child,
                ),
              ),
              Positioned(
                top: 40,
                left: 10,
                child: AnimatedSize(
                  vsync: this,
                  duration: Duration(milliseconds: 500),
                  curve: Sprung.underDamped,
                  alignment: Alignment.center,
                  child: reactionWidgets.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              alignment: Alignment.center,
                              height: 120,
                              width: CustomNavigator.width(context) - 20,
                              color: Theme.of(context).accentColor,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 0),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  scrollDirection: Axis.horizontal,
                                  itemBuilder: (context, index) {
                                    if (index >= 0 && index < reactionWidgets.length) {
                                      return reactionWidgets[index];
                                    } else {
                                      return Container();
                                    }
                                  },
                                  itemCount: reactionWidgets.length,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(),
                ),
              ),
              buildCopyPasteMenu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildReactionMenu() {
    double reactionIconSize =
        ((8.5 / 10 * min(context.isTablet ? max(CustomNavigator.width(context) / 2, 400) : CustomNavigator.width(context), context.height)) / (ReactionTypes.toList().length).toDouble());
    double maxMenuWidth = (ReactionTypes.toList().length * reactionIconSize).toDouble();
    double menuHeight = (reactionIconSize).toDouble();
    double topPadding = -20;
    if (topMinimum > context.height - 120 - menuHeight) {
      topMinimum = context.height - 120 - menuHeight;
    }
    double topOffset = (messageTopOffset - menuHeight).toDouble().clamp(topMinimum, context.height - 120 - menuHeight);
    bool shiftRight = currentChat!.chat.isGroup();
    double leftOffset =
        (widget.message.isFromMe! ? CustomNavigator.width(context) - maxMenuWidth - 25 : 25 + (shiftRight ? 20 : 0)).toDouble();
    Color iconColor = Colors.white;

    if (Theme.of(context).accentColor.computeLuminance() >= 0.179) {
      iconColor = Colors.black.withAlpha(95);
    }

    return Positioned(
      top: topOffset + topPadding,
      left: leftOffset,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(5),
            height: menuHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).accentColor.withAlpha(150),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: ReactionTypes.toList()
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7.5, horizontal: 7.5),
                      child: Container(
                        width: reactionIconSize - 15,
                        height: reactionIconSize - 15,
                        decoration: BoxDecoration(
                          color: currentlySelectedReaction == e
                              ? Theme.of(context).primaryColor
                              : Theme.of(context).accentColor.withAlpha(150),
                          borderRadius: BorderRadius.circular(
                            20,
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            sendReaction(selfReaction == e ? "-$e" : e);
                          },
                          onTapDown: (TapDownDetails details) {
                            if (currentlySelectedReaction == e) {
                              currentlySelectedReaction = null;
                            } else {
                              currentlySelectedReaction = e;
                            }
                            if (mounted) setState(() {});
                          },
                          onTapUp: (details) {},
                          onTapCancel: () {
                            currentlySelectedReaction = selfReaction;
                            if (mounted) setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Reaction.getReactionIcon(e, iconColor),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  bool get showDownload =>
      widget.message.hasAttachments &&
      widget.message.attachments!.where((element) => element!.mimeStart != null).isNotEmpty &&
      widget.message.attachments!.where((element) => AttachmentHelper.getContent(element!) is PlatformFile).isNotEmpty;

  bool get isSent => !widget.message.guid!.startsWith('temp') && !widget.message.guid!.startsWith('error');

  double? get detailsMenuHeight {
    return height;
  }

  set detailsMenuHeight(double? value) {
    height = value;
  }

  Widget buildCopyPasteMenu() {
    double maxMenuWidth = CustomNavigator.width(context) * 2 / 3;

    double maxHeight = context.height - topMinimum - widget.childSize!.height;

    List<Widget> allActions = [
      if (widget.currentChat!.chat.isGroup() && !widget.message.isFromMe! && dmChat != null && !LifeCycleManager().isBubble)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              Navigator.pushReplacement(
                context,
                cupertino.CupertinoPageRoute(
                  builder: (BuildContext context) {
                    return ConversationView(
                      chat: dmChat,
                    );
                  },
                ),
              );
            },
            child: ListTile(
              title: Text(
                "Open Direct Message",
                style: Theme.of(context).textTheme.bodyText1,
              ),
              trailing: Icon(
                Icons.open_in_new,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
            ),
          ),
        ),
      if (widget.currentChat!.chat.isGroup() && !widget.message.isFromMe! && dmChat == null && !LifeCycleManager().isBubble)
        Material(
          color: Colors.transparent,
          child: InkWell(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: () async {
              Handle? handle = widget.message.handle;
              String? address = handle?.address ?? "";
              Contact? contact = ContactManager().getCachedContact(address: address);
              UniqueContact uniqueContact;
              if (contact == null) {
                uniqueContact = UniqueContact(address: address, displayName: (await formatPhoneNumber(handle)));
              } else {
                uniqueContact = UniqueContact(address: address, displayName: contact.displayName);
              }
              Navigator.pushReplacement(
                context,
                cupertino.CupertinoPageRoute(
                  builder: (BuildContext context) {
                    EventDispatcher().emit("update-highlight", null);
                    return ConversationView(
                      isCreator: true,
                      selected: [uniqueContact],
                    );
                  },
                ),
              );
            },
            child: ListTile(
              title: Text(
                "Start Conversation",
                style: Theme.of(context).textTheme.bodyText1,
              ),
              trailing: Icon(
                Icons.message,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
            ),
          ),
        ),
      if (!LifeCycleManager().isBubble)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                cupertino.CupertinoPageRoute(
                  builder: (BuildContext context) {
                    List<PlatformFile> existingAttachments = [];
                    if (!widget.message.isUrlPreview()) {
                      existingAttachments =
                          widget.message.attachments!.map((attachment) => PlatformFile(
                            name: attachment!.transferName!,
                            path: kIsWeb ? null : attachment.getPath(),
                            bytes: attachment.bytes,
                            size: attachment.totalBytes!,
                          )).toList();
                    }
                    EventDispatcher().emit("update-highlight", null);
                    return ConversationView(
                      isCreator: true,
                      existingText: widget.message.text,
                      existingAttachments: existingAttachments,
                    );
                  },
                ),
              );
            },
            child: ListTile(
              title: Text(
                "Forward",
                style: Theme.of(context).textTheme.bodyText1,
              ),
              trailing: Icon(
                Icons.forward,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
            ),
          ),
        ),
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            NewMessageManager().removeMessage(widget.currentChat!.chat, widget.message.guid);
            Message.softDelete(widget.message.guid!);
            Navigator.of(context).pop();
          },
          child: ListTile(
            title: Text(
              "Delete",
              style: Theme.of(context).textTheme.bodyText1,
            ),
            trailing: Icon(
              Icons.delete,
              color: Theme.of(context).textTheme.bodyText1!.color,
            ),
          ),
        ),
      ),
      if (!isEmptyString(widget.message.fullText))
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.message.fullText));
              Navigator.of(context).pop();
              showSnackbar("Copied", "Copied to clipboard!", durationMs: 1000);
            },
            child: ListTile(
              title: Text("Copy", style: Theme.of(context).textTheme.bodyText1),
              trailing: Icon(
                Icons.content_copy,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
            ),
          ),
        ),
      if (showDownload && isSent)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              for (Attachment? element in widget.message.attachments!) {
                AttachmentHelper.redownloadAttachment(element!);
              }
              setState(() {});
              Navigator.of(context).pop();
            },
            child: ListTile(
              title: Text(
                "Re-download from Server",
                style: Theme.of(context).textTheme.bodyText1,
              ),
              trailing: Icon(
                Icons.refresh,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
            ),
          ),
        ),
      if (!kIsWeb && !kIsDesktop)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final messageDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().toLocal(),
                  firstDate: DateTime.now().toLocal(),
                  lastDate: DateTime.now().toLocal().add(Duration(days: 365)));
              if (messageDate != null) {
                final messageTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (messageTime != null) {
                  final finalDate = DateTime(
                      messageDate.year, messageDate.month, messageDate.day, messageTime.hour, messageTime.minute);
                  if (!finalDate.isAfter(DateTime.now().toLocal())) {
                    showSnackbar("Error", "Select a date in the future");
                    return;
                  }
                  NotificationManager().scheduleNotification(widget.currentChat!.chat, widget.message, finalDate);
                  Get.back();
                  showSnackbar("Notice", "Scheduled reminder for ${buildDate(finalDate)}");
                }
              }
            },
            child: ListTile(
              title: Text(
                "Remind Later",
                style: Theme.of(context).textTheme.bodyText1,
              ),
              trailing: Icon(
                Icons.alarm,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
            ),
          ),
        ),
    ];

    List<Widget> detailsActions = [];
    List<Widget> moreActions = [];
    double itemHeight = 56;

    double actualHeight = 2 * itemHeight;
    int index = 0;
    while (actualHeight <= maxHeight - itemHeight && index < allActions.length) {
      actualHeight += itemHeight;
      detailsActions.add(allActions[index++]);
    }
    detailsMenuHeight = (detailsActions.length + 1) * itemHeight;
    moreActions.addAll(allActions.getRange(index, allActions.length));

    // If there is only one 'more' action then it can replace the 'more' button
    if (moreActions.length == 1) {
      detailsActions.add(moreActions.removeAt(0));
    }

    Widget menu = ClipRRect(
      borderRadius: BorderRadius.circular(20.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: Theme.of(context).accentColor.withAlpha(150),
          width: maxMenuWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...detailsActions,
              if (moreActions.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      showDialog(
                          context: context,
                          builder: (_) {
                            Widget content = Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: moreActions,
                            );
                            return AlertDialog(
                              backgroundColor: Theme.of(context).accentColor,
                              content: content,
                            );
                          });
                    },
                    child: ListTile(
                      title: Text("More...", style: Theme.of(context).textTheme.bodyText1),
                      trailing: Icon(
                        Icons.more_vert,
                        color: Theme.of(context).textTheme.bodyText1!.color,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    double upperLimit = context.height - detailsMenuHeight!;
    if (topMinimum > upperLimit) {
      topMinimum = upperLimit;
    }

    double topOffset = (messageTopOffset + widget.childSize!.height).toDouble().clamp(topMinimum, upperLimit);
    bool shiftRight = currentChat!.chat.isGroup();
    double leftOffset =
        (widget.message.isFromMe! ? CustomNavigator.width(context) - maxMenuWidth - 15 : 15 + (shiftRight ? 35 : 0)).toDouble();
    return Positioned(
      top: topOffset + 5,
      left: leftOffset,
      child: menu,
    );
  }
}
