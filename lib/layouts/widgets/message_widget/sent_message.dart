import 'dart:ui';

import 'package:bluebubbles_wearos/action_handler.dart';
import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/helpers/darty.dart';
import 'package:bluebubbles_wearos/helpers/hex_color.dart';
import 'package:bluebubbles_wearos/helpers/message_helper.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/delivered_receipt.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/media_players/balloon_bundle_widget.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/message_tail.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/message_time_stamp.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_popup_holder.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_widget_mixin.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/new_message_manager.dart';
import 'package:bluebubbles_wearos/managers/notification_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SentMessageHelper {
  static Widget buildMessageWithTail(BuildContext context, Message? message, bool showTail, bool hasReactions,
      bool bigEmoji, Future<List<InlineSpan>> msgSpanFuture,
      {Widget? customContent,
      Message? olderMessage,
      CurrentChat? currentChat,
      Color? customColor,
      bool padding = true,
      bool margin = true,
      double? customWidth}) {
    Color bubbleColor;
    bubbleColor = message == null || message.guid!.startsWith("temp")
        ? Theme.of(context).primaryColor.darkenAmount(0.2)
        : Theme.of(context).primaryColor;

    Widget msg;
    bool hasReactions = (message?.getReactions() ?? []).isNotEmpty;

    if (message?.isBigEmoji() ?? false) {
      // this stack is necessary for layouting width properly
      msg = Stack(alignment: AlignmentDirectional.bottomEnd, children: [
        LayoutBuilder(builder: (_, constraints) {
          return Container(
            width: customWidth != null ? constraints.maxWidth : null,
            child: Padding(
              padding: EdgeInsets.only(
                left: (hasReactions) ? 15.0 : 0.0,
                top: (hasReactions) ? 15.0 : 0.0,
                right: 5,
              ),
              child: Text(
                      message!.text!,
                      style: Theme.of(context).textTheme.bodyText2!.apply(fontSizeFactor: 4),
                    ),
            ),
          );
        })
      ]);
    } else {
      msg = Stack(
        alignment: AlignmentDirectional.bottomEnd,
        children: [
          if (showTail && message != null)
            MessageTail(
              isFromMe: true,
              color: customColor ?? bubbleColor,
            ),
          LayoutBuilder(builder: (_, constraints) {
            return Container(
              width: customWidth != null ? constraints.maxWidth : null,
              constraints: customWidth == null
                  ? BoxConstraints(
                      maxWidth: CustomNavigator.width(context) * MessageWidgetMixin.maxSize + (!padding ? 100 : 0),
                    )
                  : null,
              margin: EdgeInsets.only(
                top: hasReactions && margin ? 18 : 0,
                left: margin ? 10 : 0,
                right: margin ? 10 : 0,
              ),
              padding: EdgeInsets.symmetric(
                vertical: padding ? 8 : 0,
                horizontal: padding ? 14 : 0,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(17),
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                color: customColor ?? bubbleColor,
              ),
              child: customContent ??
                  FutureBuilder<List<InlineSpan>>(
                      future: msgSpanFuture,
                      initialData: MessageWidgetMixin.buildMessageSpans(context, message),
                      builder: (context, snapshot) {
                        return RichText(
                          text: TextSpan(
                            children: snapshot.data ?? MessageWidgetMixin.buildMessageSpans(context, message),
                            style: Theme.of(context).textTheme.bodyText2!.apply(color: Colors.white),
                          ),
                        );
                      }),
            );
          }),
        ],
      );
    }
    if (!padding) return msg;
    return Container(
        width: customWidth != null ? customWidth - (showTail ? 20 : 0) : null,
        constraints: BoxConstraints(
          maxWidth: customWidth != null ? customWidth - (showTail ? 20 : 0) : CustomNavigator.width(context),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (customWidth != null) Expanded(child: msg),
            if (customWidth == null) msg,
            getErrorWidget(
              context,
              message,
              currentChat != null ? currentChat.chat : CurrentChat.of(context)?.chat,
            ),
          ],
        ));
  }

  static Widget getErrorWidget(BuildContext context, Message? message, Chat? chat, {double rightPadding = 8.0}) {
    if (message != null && message.error > 0) {
      int errorCode = message.error;
      String errorText = "Server Error. Contact Support.";
      if (errorCode == 22) {
        errorText = "The recipient is not registered with iMessage!";
      } else if (message.guid!.startsWith("error-")) {
        errorText = message.guid!.split('-')[1];
      }

      return Padding(
        padding: EdgeInsets.only(right: rightPadding),
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text("Message failed to send", style: TextStyle(color: Colors.black)),
                  content: Text("Error ($errorCode): $errorText"),
                  actions: <Widget>[
                    if (chat != null)
                      TextButton(
                        child: Text("Retry"),
                        onPressed: () async {
                          // Remove the OG alert dialog
                          Navigator.of(context).pop();
                          NewMessageManager().removeMessage(chat, message.guid);
                          Message.softDelete(message.guid!);
                          NotificationManager().clearFailedToSend();
                          ActionHandler.retryMessage(message);
                        },
                      ),
                    if (chat != null)
                      TextButton(
                        child: Text("Remove"),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          // Delete the message from the DB
                          Message.softDelete(message.guid!);

                          // Remove the message from the Bloc
                          NewMessageManager().removeMessage(chat, message.guid);
                          NotificationManager().clearFailedToSend();
                          // Get the "new" latest info
                          List<Message> latest = Chat.getMessages(chat, limit: 1);
                          chat.latestMessage = latest.first;
                          chat.latestMessageDate = latest.first.dateCreated;
                          chat.latestMessageText = MessageHelper.getNotificationText(latest.first);

                          // Update it in the Bloc
                          await ChatBloc().updateChatPosition(chat);
                        },
                      ),
                    TextButton(
                      child: Text("Cancel"),
                      onPressed: () {
                        Navigator.of(context).pop();
                        NotificationManager().clearFailedToSend();
                      },
                    )
                  ],
                );
              },
            );
          },
          child: Icon(
              Icons.error_outline,
              color: Colors.red),
        ),
      );
    }
    return Container();
  }
}

class SentMessage extends StatelessWidget {
  final bool showTail;
  final Message message;
  final Message? olderMessage;
  final Message? newerMessage;
  final bool showHero;
  final bool shouldFadeIn;
  final bool showDeliveredReceipt;

  // Sub-widgets
  final Widget stickersWidget;
  final Widget attachmentsWidget;
  final Widget reactionsWidget;
  final Widget urlPreviewWidget;

  SentMessage({
    Key? key,
    required this.showTail,
    required this.olderMessage,
    required this.newerMessage,
    required this.message,
    required this.showHero,
    required this.showDeliveredReceipt,
    required this.shouldFadeIn,

    // Sub-widgets
    required this.stickersWidget,
    required this.attachmentsWidget,
    required this.reactionsWidget,
    required this.urlPreviewWidget,
    required BuildContext context,
  }) : super(key: key) {
    spanFuture = MessageWidgetMixin.buildMessageSpansAsync(context, message);
  }

  late final Future<List<InlineSpan>> spanFuture;

  @override
  Widget build(BuildContext context) {
    // The column that holds all the "messages"
    List<Widget> messageColumn = [];

    // Second, add the attachments
    if (isEmptyString(message.fullText)) {
      messageColumn.add(
        MessageWidgetMixin.addStickersToWidget(
          message: MessageWidgetMixin.addReactionsToWidget(
              messageWidget: attachmentsWidget, reactions: reactionsWidget, message: message),
          stickers: stickersWidget,
          isFromMe: message.isFromMe!,
        ),
      );
    } else {
      messageColumn.add(attachmentsWidget);
    }

    // Third, let's add the message or URL preview
    Widget? messageWidget;
    if (message.balloonBundleId != null && message.balloonBundleId != 'com.apple.messages.URLBalloonProvider') {
      messageWidget = BalloonBundleWidget(message: message);
    } else if (!isEmptyString(message.text)) {
      messageWidget = SentMessageHelper.buildMessageWithTail(
          context, message, showTail, message.hasReactions, message.bigEmoji ?? false, spanFuture,
          olderMessage: olderMessage);
      if (showHero) {
        messageWidget = Hero(
          tag: "first",
          child: Material(
            type: MaterialType.transparency,
            child: messageWidget,
          ),
        );
      }
      if (message.fullText.replaceAll("\n", " ").hasUrl) {
        messageWidget = message.fullText.isURL
            ? Padding(
                padding: EdgeInsets.only(right: 5.0),
                child: urlPreviewWidget,
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                    Padding(
                      padding: EdgeInsets.only(right: 5.0),
                      child: urlPreviewWidget,
                    ),
                    messageWidget,
                  ]);
      }
    }

    // Fourth, let's add any reactions or stickers to the widget
    if (messageWidget != null) {
      messageColumn.add(
        MessageWidgetMixin.addStickersToWidget(
          message: MessageWidgetMixin.addReactionsToWidget(
              messageWidget: Padding(
                padding: EdgeInsets.only(bottom: showTail ? 2.0 : 0),
                child: messageWidget,
              ),
              reactions: reactionsWidget,
              message: message),
          stickers: stickersWidget,
          isFromMe: message.isFromMe!,
        ),
      );
    }
    messageColumn.add(
      DeliveredReceipt(
        message: message,
        showDeliveredReceipt: showDeliveredReceipt,
        shouldAnimate: shouldFadeIn,
      ),
    );

    // Now, let's create a row that will be the row with the following:
    // -> Contact avatar
    // -> Message
    List<Widget> msgRow = [];

    // Add the message column to the row
    msgRow.add(
      Padding(
        // Padding to shift the bubble up a bit, relative to the avatar
        padding: EdgeInsets.only(
            top: 0,
            bottom: (showTail && !isEmptyString(message.fullText)) ? 5.0 : 0,
            right: isEmptyString(message.fullText) && message.error == 0 ? 10.0 : 0.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: messageColumn,
        ),
      ),
    );

    // Finally, create a container row so we can have the swipe timestamp
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MessagePopupHolder(
          message: message,
          olderMessage: olderMessage,
          newerMessage: newerMessage,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: msgRow,
          ),
          popupChild: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: msgRow,
          ),
        ),
        if (!kIsDesktop && !kIsWeb && message.guid != olderMessage?.guid)
          MessageTimeStamp(
            message: message,
          )
      ],
    );
  }
}
