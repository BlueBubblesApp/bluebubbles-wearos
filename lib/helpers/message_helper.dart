import 'dart:async';

import 'package:bluebubbles_wearos/helpers/attachment_downloader.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/life_cycle_manager.dart';
import 'package:bluebubbles_wearos/managers/new_message_manager.dart';
import 'package:bluebubbles_wearos/managers/notification_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

import 'emoji_regex.dart';

class EmojiConst {
  static final String charNonSpacingMark = String.fromCharCode(0xfe0f);
  static final String charColon = ':';
  static final String charEmpty = '';
}

Map<String, String> nameMap = {
  'com.apple.Handwriting.HandwritingProvider': 'Handwritten Message',
  'com.apple.DigitalTouchBalloonProvider': 'Digital Touch'
};

class MessageHelper {
  static Future<List<Message>> bulkAddMessages(Chat? chat, List<dynamic> messages,
      {bool notifyForNewMessage = false,
      bool notifyMessageManager = true,
      bool checkForLatestMessageText = true,
      bool isIncremental = false,
      Function(int progress, int length)? onProgress}) async {
    // Create master list for all the messages and a chat cache
    List<Message> _messages = <Message>[];
    Map<Message, String?> notificationMessages = <Message, String?>{};
    Map<String, Chat> chats = <String, Chat>{};

    // Add the chat in the cache and save it if it hasn't been saved yet
    if (chat?.guid != null) {
      chats[chat!.guid!] = chat;
      if (chat.id == null) {
        chat = chat.save();
      }
    }

    // Iterate over each message to parse it
    int index = 0;
    List<Message> messagesList = messages.map((e) => Message.fromMap(e)).toList();

    for (dynamic item in messages) {
      if (onProgress != null) {
        onProgress(_messages.length, messages.length);
      }

      // Pull the chats out of the message, if there isnt a default
      Chat? msgChat = chat;
      if (msgChat == null) {
        List<Chat> msgChats = parseChats(item);
        msgChat = msgChats.isNotEmpty ? msgChats.first : null;

        // If there is a cached chat, get it. Otherwise, save the new one
        if (msgChat != null && chats.containsKey(msgChat.guid)) {
          msgChat = chats[msgChat.guid];
        } else if (msgChat?.guid != null) {
          msgChat!.save();
          chats[msgChat.guid!] = msgChat;
        }
      }

      // If we can't get a chat from the data, skip the message
      if (msgChat == null) continue;

      Message message = Message.fromMap(item);
      Message? existing = Message.findOne(guid: message.guid);
      if (chat == null || kIsWeb) {
        await msgChat.addMessage(
          message,
          changeUnreadStatus: notifyForNewMessage,
          checkForMessageText: checkForLatestMessageText,
        );
      }

      if (existing == null) {
        if (isIncremental && !notificationMessages.containsValue(msgChat.guid)) {
          notificationMessages[message] = msgChat.guid;
        } else if (!isIncremental) {
          notificationMessages[message] = msgChat.guid;
        }
      } else {
        message = existing;
      }

      // Add message to the "master list"
      if (chat == null || kIsWeb) _messages.add(message);

      // Every 50 messages synced, who a message
      index += 1;
      if (index % 50 == 0) {
        Logger.info('Saved $index of ${messages.length} messages', tag: "BulkIngest");
      } else if (index == messages.length) {
        Logger.info('Saved ${messages.length} messages', tag: "BulkIngest");
      }
    }

    if (chat != null && !kIsWeb) {
      final msgs = await chat.bulkAddMessages(
        messagesList,
        changeUnreadStatus: notifyForNewMessage,
        checkForMessageText: checkForLatestMessageText,
      );
      _messages.addAll(msgs);
    }

    if (notifyForNewMessage || notifyMessageManager) {
      notificationMessages.forEach((message, value) async {
        //this should always be non-null
        Chat msgChat = chats[value]!;

        if (notifyForNewMessage) {
          await MessageHelper.handleNotification(message, msgChat, force: true);
        }

        // Tell all listeners that we have a new message, and save the message
        if (notifyMessageManager) {
          NewMessageManager().addMessage(msgChat, message);
        }
      });
    }

    // Return all the synced messages
    return _messages;
  }

  static Future<void> bulkDownloadAttachments(Chat? chat, List<dynamic> messages) async {
    // Create master list for all the messages and a chat cache
    Map<String, Chat> chats = <String, Chat>{};

    // Add the chat in the cache and save it if it hasn't been saved yet
    if (chat?.guid != null) {
      chats[chat!.guid!] = chat;
      if (chat.id == null) {
        chat.save();
      }
    }

    // Iterate over each message to parse it
    for (dynamic item in messages) {
      // Pull the chats out of the message, if there isnt a default
      Chat? msgChat = chat;
      if (msgChat == null) {
        List<Chat> msgChats = parseChats(item);
        msgChat = msgChats.isNotEmpty ? msgChats[0] : null;

        // If there is a cached chat, get it. Otherwise, save the new one
        if (msgChat != null && chats.containsKey(msgChat.guid)) {
          msgChat = chats[msgChat.guid];
        } else if (msgChat?.guid != null) {
          msgChat!.save();
          chats[msgChat.guid!] = msgChat;
        }
      }

      // If we can't get a chat from the data, skip the message
      if (msgChat == null) continue;

      // Create the attachments
      List<dynamic> attachments = item['attachments'];
      for (dynamic attachmentItem in attachments) {
        Attachment file = Attachment.fromMap(attachmentItem);
        await MessageHelper.downloadAttachmentSync(file);
      }
    }
  }

  static Future<void> downloadAttachmentSync(Attachment file) {
    Completer<void> completer = Completer();
    Get.put(
        AttachmentDownloadController(
            attachment: file,
            onComplete: () {
              completer.complete();
            },
            onError: () {
              completer.completeError(Error());
            }),
        tag: file.guid);

    return completer.future;
  }

  static List<Chat> parseChats(Map<String, dynamic> data) {
    List<Chat> chats = [];

    if (data.containsKey("chats") && data["chats"] != null && data["chats"].length > 0) {
      for (int i = 0; i < data["chats"].length; i++) {
        Chat chat = Chat.fromMap(data["chats"][i]);
        chats.add(chat);
      }
    }

    return chats;
  }

  static Future<void> handleNotification(Message message, Chat chat, {bool force = false}) async {
    // See if there is an existing message for the given GUID
    Message? existingMessage;
    if (!force) existingMessage = Message.findOne(guid: message.guid);
    // If we've already processed the GUID, skip it
    if (NotificationManager().hasProcessed(message.guid!)) return;
    // Add the message to the "processed" list
    NotificationManager().addProcessed(message.guid!);
    // Handle all the cases that would mean we don't show the notification
    if (!SettingsManager().settings.finishedSetup.value) return; // Don't notify if not fully setup
    if (existingMessage != null) return;
    if (chat.shouldMuteNotification(message)) return; // Don''t notify if the chat is muted
    if (message.isFromMe! || message.handle == null) return; // Don't notify if the text is from me

    CurrentChat? currChat = CurrentChat.activeChat;
    if (((LifeCycleManager().isAlive && !kIsWeb) || (kIsWeb && !(html.window.document.hidden ?? false))) &&
        ((currChat == null &&
                !Get.currentRoute.contains("settings")) ||
            currChat?.chat.guid == chat.guid)) {
      // Don't notify if the the chat is the active chat
      return;
    }
    await NotificationManager().createNotificationFromMessage(chat, message);
  }

  static String getNotificationText(Message message) {
    // If the item type is not 0, it's a group event
    if (message.isGroupEvent()) {
      return getGroupEventText(message);
    }

    if (message.isInteractive()) {
      return "Interactive: ${MessageHelper.getInteractiveText(message)}";
    }

    if (isNullOrEmpty(message.text, trimString: true)! && !message.hasAttachments) {
      return "Empty message";
    }

    // Parse/search for links
    List<RegExpMatch> matches = parseLinks(message.text!);

    // If there are attachments, return the number of attachments
    int aCount = (message.attachments ?? []).length;
    if (message.hasAttachments && matches.isEmpty) {
      // Build the attachment output by counting the attachments
      String output = "Attachment${aCount > 1 ? "s" : ""}";
      Map<String, int> counts = {};
      for (Attachment? attachment in message.attachments ?? []) {
        String? mime = attachment!.mimeType;
        String key;
        if (mime == null) {
          key = "link";
        } else if (mime.contains("vcard")) {
          key = "contact card";
        } else if (mime.contains("location")) {
          key = "location";
        } else if (mime.contains("contact")) {
          key = "contact";
        } else if (mime.contains("video")) {
          key = "movie";
        } else if (mime.contains("image/gif")) {
          key = "GIF";
        } else if (mime.contains("application/pdf")) {
          key = "PDF";
        } else {
          key = mime.split("/").first;
        }

        int current = counts.containsKey(key) ? counts[key]! : 0;
        counts[key] = current + 1;
      }

      List<String> attachmentStr = [];
      counts.forEach((key, value) {
        attachmentStr.add("$value $key${value > 1 ? "s" : ""}");
      });

      return "$output: ${attachmentStr.join(attachmentStr.length == 2 ? " & " : ", ")}";
    } else if (![null, ""].contains(message.associatedMessageGuid)) {
      // It's a reaction message, get the "sender"
      String? sender = message.isFromMe! ? "You" : ContactManager().getContactTitle(message.handle);

      return "$sender ${message.text}";
    } else {
      // It's all other message types
      return message.text ?? "Unknown Message";
    }
  }

  static bool shouldShowBigEmoji(String text) {
    if (isEmptyString(text)) return false;

    RegExp pattern = emojiRegex;
    List<RegExpMatch> matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return false;

    List<String> items = matches.map((m) => m.toString()).toList();

    String replaced = text.replaceAll(pattern, "").replaceAll(String.fromCharCode(65039), "");
    RegExp darkSunglasses = RegExp('\u{1F576}');
    replaced = replaced.replaceAll(darkSunglasses, "").trim();
    return items.length <= 3 && replaced.isEmpty;
  }

  /// Removes duplicate associated message guids from a list of [associatedMessages]
  static List<Message> normalizedAssociatedMessages(List<Message> associatedMessages) {
    Set<int> guids = associatedMessages.map((e) => e.handleId ?? 0).toSet();
    List<Message> normalized = [];

    for (Message message in associatedMessages.reversed.toList()) {
      if (guids.remove(message.handleId ?? 0)) {
        normalized.add(message);
      }
    }
    return normalized;
  }

  static String getInteractiveText(Message message) {
    if (message.balloonBundleId == null) return "Null Balloon Bundle ID";
    if (nameMap.containsKey(message.balloonBundleId)) {
      return nameMap[message.balloonBundleId!]!;
    }

    String val = message.balloonBundleId!.toLowerCase();
    if (val.contains("gamepigeon")) {
      return "Game Pigeon";
    } else if (val.contains("contextoptional")) {
      List<String> items = val.split(".").reversed.toList();
      if (items.length >= 2) {
        return items[1];
      }
    } else if (val.contains("mobileslideshow")) {
      return "Photo Slideshow";
    } else if (val.contains("PeerPayment")) {
      return "Payment Request";
    }

    List<String> items = val.split(":").reversed.toList();
    return (items.isNotEmpty) ? items[0] : val;
  }

  static bool withinTimeThreshold(Message? first, Message? second, {threshold = 5}) {
    if (first == null || second == null) return false;
    return second.dateCreated!.difference(first.dateCreated!).inMinutes.abs() > threshold;
  }

  static bool getShowTail(BuildContext context, Message? message, Message? newerMessage) {
    if (MessageHelper.withinTimeThreshold(message, newerMessage, threshold: 1)) return true;
    if (!sameSender(message, newerMessage)) return true;
    if (message!.isFromMe! &&
        newerMessage!.isFromMe! &&
        message.dateDelivered != null &&
        newerMessage.dateDelivered == null) return true;

    Message? lastRead = CurrentChat.of(context)?.messageMarkers.lastReadMessage;
    if (lastRead != null && lastRead.guid == message.guid) return true;
    Message? lastDelivered = CurrentChat.of(context)?.messageMarkers.lastDeliveredMessage;
    if (lastDelivered != null && lastDelivered.guid == message.guid) return true;

    return false;
  }

  static bool getShowTailReversed(BuildContext context, Message message, Message? olderMessage) =>
      getShowTail(context, message, olderMessage);

// static List<TextSpan> buildEmojiText(String text, TextStyle style) {
//   final children = <TextSpan>[];
//   final runes = text.runes;

//   for (int i = 0; i < runes.length; /* empty */) {
//     int current = runes.elementAt(i);
//     final isEmoji = current > 255;
//     final shouldBreak = isEmoji ? (x) => x <= 255 : (x) => x > 255;

//     final chunk = <int>[];
//     while (!shouldBreak(current)) {
//       chunk.add(current);
//       if (++i >= runes.length) break;
//       current = runes.elementAt(i);
//     }

//     children.add(
//       TextSpan(text: String.fromCharCodes(chunk), style: style),
//     );
//   }

//   return children;
// }
}
