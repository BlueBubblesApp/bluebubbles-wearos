import 'package:bluebubbles_wearos/helpers/darty.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/widgets/contact_avatar_widget.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/media_players/balloon_bundle_widget.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/message_tail.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/message_time_stamp.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_popup_holder.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_widget_mixin.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'message_content/delivered_receipt.dart';

class ReceivedMessage extends StatefulWidget {
  final bool showTail;
  final Message message;
  final Message? olderMessage;
  final Message? newerMessage;
  final bool showHandle;

  // Sub-widgets
  final Widget stickersWidget;
  final Widget attachmentsWidget;
  final Widget reactionsWidget;
  final Widget urlPreviewWidget;

  final bool showTimeStamp;

  ReceivedMessage({
    Key? key,
    required this.showTail,
    required this.olderMessage,
    required this.newerMessage,
    required this.message,
    required this.showHandle,

    // Sub-widgets
    required this.stickersWidget,
    required this.attachmentsWidget,
    required this.reactionsWidget,
    required this.urlPreviewWidget,
    this.showTimeStamp = false,
  }) : super(key: key);

  @override
  _ReceivedMessageState createState() => _ReceivedMessageState();
}

class _ReceivedMessageState extends State<ReceivedMessage> with MessageWidgetMixin {
  bool checkedHandle = false;
  late String contactTitle;
  late final spanFuture = MessageWidgetMixin.buildMessageSpansAsync(context, widget.message,
      colors: widget.message.handle?.color != null ? getBubbleColors() : null);

  @override
  initState() {
    super.initState();
    contactTitle = ContactManager().getContactTitle(widget.message.handle) ?? "";

    EventDispatcher().stream.listen((Map<String, dynamic> event) {
      if (!event.containsKey("type")) return;

      if (event["type"] == 'refresh-avatar' && event["data"][0] == widget.message.handle?.address && mounted) {
        widget.message.handle?.color = event['data'][1];
        setState(() {});
      }
    });
  }

  List<Color> getBubbleColors() {
    List<Color> bubbleColors = [Theme.of(context).accentColor, Theme.of(context).accentColor];
    return bubbleColors;
  }

  /// Builds the message bubble with teh tail (if applicable)
  Widget _buildMessageWithTail(Message message) {
    if (message.isBigEmoji()) {

      bool hasReactions = message.getReactions().isNotEmpty;
      return Padding(
        padding: EdgeInsets.only(
          left: CurrentChat.of(context)!.chat.participants.length > 1 ? 5.0 : 0.0,
          right: (hasReactions) ? 15.0 : 0.0,
          top: widget.message.getReactions().isNotEmpty ? 15 : 0,
        ),
        child: Text(
                message.text!,
                style: Theme.of(context).textTheme.bodyText2!.apply(fontSizeFactor: 4),
              ),
      );
    }

    return Stack(
      alignment: AlignmentDirectional.bottomStart,
      children: [
        if (widget.showTail)
          MessageTail(
            isFromMe: false,
            color: getBubbleColors()[0],
          ),
        Container(
          margin: EdgeInsets.only(
            top: widget.message.getReactions().isNotEmpty && !widget.message.hasAttachments
                ? 18
                : (widget.message.isFromMe != widget.olderMessage?.isFromMe)
                    ? 5.0
                    : 0,
            left: 10,
            right: 10,
          ),
          constraints: BoxConstraints(
            maxWidth: CustomNavigator.width(context) * MessageWidgetMixin.maxSize,
          ),
          padding: EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(17),
                    bottomRight: Radius.circular(20),
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
            gradient: LinearGradient(
              begin: AlignmentDirectional.bottomCenter,
              end: AlignmentDirectional.topCenter,
              colors: getBubbleColors(),
            ),
          ),
          child: FutureBuilder<List<InlineSpan>>(
              future: spanFuture,
              initialData: MessageWidgetMixin.buildMessageSpans(context, widget.message,
                  colors: widget.message.handle?.color != null ? getBubbleColors() : null),
              builder: (context, snapshot) {
                return RichText(
                  text: TextSpan(
                    children: snapshot.data ?? MessageWidgetMixin.buildMessageSpans(context, widget.message,
                        colors: widget.message.handle?.color != null ? getBubbleColors() : null),
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                );
              }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The column that holds all the "messages"
    List<Widget> messageColumn = [];

    // First, add the message sender (if applicable)
    bool isGroup = CurrentChat.of(context)?.chat.isGroup() ?? false;
    bool addedSender = false;
    bool showSender = isGroup ||
        widget.message.guid == "redacted-mode-demo" ||
        widget.message.guid!.contains("theme-selector");
    if (widget.message.guid == "redacted-mode-demo" ||
        widget.message.guid!.contains("theme-selector") ||
          (!sameSender(widget.message, widget.olderMessage) ||
              !widget.message.dateCreated!.isWithin(widget.olderMessage!.dateCreated!, minutes: 30))) {
      messageColumn.add(
        Padding(
          padding: EdgeInsets.only(left: 15.0, top: 5.0, bottom: widget.message.getReactions().isNotEmpty ? 0.0 : 3.0),
          child: Text(
            contactTitle,
            style: Theme.of(context).textTheme.subtitle1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      addedSender = true;
    }

    // Second, add the attachments
    if (widget.message.getRealAttachments().isNotEmpty) {
      messageColumn.add(
        MessageWidgetMixin.addStickersToWidget(
          message: MessageWidgetMixin.addReactionsToWidget(
              messageWidget: widget.attachmentsWidget,
              reactions: widget.reactionsWidget,
              message: widget.message,
              shouldShow: widget.message.hasAttachments),
          stickers: widget.stickersWidget,
          isFromMe: widget.message.isFromMe!,
        ),
      );
    }

    // Third, let's add the actual message we want to show
    Widget? message;
    if (widget.message.isInteractive()) {
      message = Padding(padding: EdgeInsets.only(left: 10.0), child: BalloonBundleWidget(message: widget.message));
    } else if (widget.message.hasText()) {
      message = _buildMessageWithTail(widget.message);
      if (widget.message.fullText.replaceAll("\n", " ").hasUrl) {
        message = widget.message.fullText.isURL
            ? Padding(
                padding: EdgeInsets.only(left: 10.0),
                child: widget.urlPreviewWidget,
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Padding(
                      padding: EdgeInsets.only(left: 10.0),
                      child: widget.urlPreviewWidget,
                    ),
                    message,
                  ]);
      }
    }

    // Fourth, let's add any reactions or stickers to the widget
    if (message != null) {
      messageColumn.add(
        MessageWidgetMixin.addStickersToWidget(
          message: MessageWidgetMixin.addReactionsToWidget(
              messageWidget: message,
              reactions: widget.reactionsWidget,
              message: widget.message,
              shouldShow: widget.message.getRealAttachments().isEmpty),
          stickers: widget.stickersWidget,
          isFromMe: widget.message.isFromMe!,
        ),
      );
    }

    if (widget.showTimeStamp) {
      messageColumn.add(
        DeliveredReceipt(
          message: widget.message,
          showDeliveredReceipt: widget.showTimeStamp,
          shouldAnimate: true,
        ),
      );
    }

    List<Widget> messagePopupColumn = List<Widget>.from(messageColumn);
    if (!addedSender && isGroup) {
      messagePopupColumn.insert(
        0,
        Padding(
          padding: EdgeInsets.only(left: 15.0, top: 5.0, bottom: widget.message.getReactions().isNotEmpty ? 0.0 : 3.0),
          child: Text(
            contactTitle,
            style: Theme.of(context).textTheme.subtitle1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Now, let's create a row that will be the row with the following:
    // -> Contact avatar
    // -> Message
    List<Widget> msgRow = [];

    List<Widget> msgPopupRow = List<Widget>.from(msgRow);

    // Add the message column to the row
    msgRow.add(
      Padding(
        // Padding to shift the bubble up a bit, relative to the avatar
        padding: EdgeInsets.only(bottom: widget.showTail ? 0.0 : 5.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messageColumn,
        ),
      ),
    );

    msgPopupRow.add(
      Padding(
        // Padding to shift the bubble up a bit, relative to the avatar
        padding: EdgeInsets.only(bottom: 0.0),
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: messagePopupColumn,
          ),
        ),
      ),
    );

    // Finally, create a container row so we can have the swipe timestamp
    return Padding(
      // Add padding when we are showing the avatar
      padding: EdgeInsets.only(
          bottom: (widget.showTail) ? 10.0 : 0.0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MessagePopupHolder(
            message: widget.message,
            olderMessage: widget.olderMessage,
            newerMessage: widget.newerMessage,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: msgRow,
              ),
            ]),
            popupChild: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: msgPopupRow,
            ),
          ),
          if (!kIsDesktop && !kIsWeb && widget.message.guid != widget.olderMessage?.guid)
            MessageTimeStamp(
              message: widget.message,
            )
        ],
      ),
    );
  }
}
