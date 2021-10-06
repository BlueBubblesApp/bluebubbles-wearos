import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/helpers/darty.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/message_helper.dart';
import 'package:bluebubbles_wearos/helpers/metadata_helper.dart';
import 'package:bluebubbles_wearos/helpers/reaction.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/main.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/objectbox.g.dart';
import 'package:bluebubbles_wearos/repository/models/attachment.dart';
import 'package:bluebubbles_wearos/repository/models/join_tables.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:collection/collection.dart';
import 'package:faker/faker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:universal_io/io.dart';

import 'handle.dart';
import 'message.dart';

String getFullChatTitle(Chat _chat) {
  String? title = "";
  if (isNullOrEmpty(_chat.displayName)!) {
    Chat chat = _chat;
    if (isNullOrEmpty(chat.participants)!) {
      chat = _chat.getParticipants();
    }

    //todo - do we really need this here?
    /*// If there are no participants, try to get them from the server
    if (chat.participants.isEmpty) {
      await ActionHandler.handleChat(chat: chat);
      chat = chat.getParticipants();
    }*/

    List<String> titles = [];
    for (int i = 0; i < chat.participants.length; i++) {
      String? name = ContactManager().getContactTitle(chat.participants[i]);

      if (chat.participants.length > 1 && !name!.isPhoneNumber) {
        name = name.trim().split(" ")[0];
      } else {
        name = name!.trim();
      }

      titles.add(name);
    }

    if (titles.isEmpty) {
      title = _chat.chatIdentifier;
    } else if (titles.length == 1) {
      title = titles[0];
    } else if (titles.length <= 4) {
      title = titles.join(", ");
      int pos = title.lastIndexOf(", ");
      if (pos != -1) title = "${title.substring(0, pos)} & ${title.substring(pos + 2)}";
    } else {
      title = titles.sublist(0, 3).join(", ");
      title = "$title & ${titles.length - 3} others";
    }
  } else {
    title = _chat.displayName;
  }

  return title!;
}

/// Async method to get attachments from objectbox
Future<List<Attachment>> getAttachmentsIsolate(List<dynamic> stuff) async {
  /// Pull args from input and create new instances of store and boxes
  int chatId = stuff[0];
  String? storeRef = stuff[1];
  store = Store.fromReference(getObjectBoxModel(), base64.decode(storeRef!).buffer.asByteData());
  attachmentBox = store.box<Attachment>();
  chatBox = store.box<Chat>();
  handleBox = store.box<Handle>();
  messageBox = store.box<Message>();
  amJoinBox = store.box<AttachmentMessageJoin>();
  chJoinBox = store.box<ChatHandleJoin>();
  cmJoinBox = store.box<ChatMessageJoin>();
  return store.runInTransaction(TxMode.read, () {
    /// Get the [ChatMessageJoin] objects matching the [chatId], and then find
    /// the message IDs
    final cmJoinQuery = cmJoinBox.query(ChatMessageJoin_.chatId.equals(chatId)).build();
    final cmJoinValues = cmJoinQuery.property(ChatMessageJoin_.messageId).find();
    cmJoinQuery.close();
    /// Get the [AttachmentMessageJoin] objects matching the message IDs, and then find
    /// the attachment IDs
    final amJoinQuery = amJoinBox.query(AttachmentMessageJoin_.messageId.oneOf(cmJoinValues)).build();
    final amJoinValues = amJoinQuery.find();
    amJoinQuery.close();
    final attachmentIds = amJoinValues.map((e) => e.attachmentId).toList();
    final messageIds = amJoinValues.map((e) => e.messageId).toList();
    /// Query the [messageBox] for all the message IDs and order by date
    /// descending
    final query2 = (messageBox.query(Message_.id.oneOf(messageIds))..order(Message_.dateCreated, flags: Order.descending)..order(Message_.originalROWID, flags: Order.descending)).build();
    final messages = query2.find();
    query2.close();
    /// Query the [attachmentBox] for all the attachment IDs and remove where
    /// [mimeType] is null
    final attachments = attachmentBox.getMany(attachmentIds, growableResult: true)..removeWhere((element) => element == null || element.mimeType == null);
    final actualAttachments = <Attachment>[];
    /// Match the attachments to their messages
    for (Message m in messages) {
      final attachmentIdsForMessage = amJoinValues.where((element) => element.messageId == m.id).map((e) => e.attachmentId).toList();
      m.attachments = attachments.where((element) => attachmentIdsForMessage.contains(element!.id)).toList();
      actualAttachments.addAll((m.attachments ?? []).map((e) => e!));
    }
    /// Remove duplicate attachments from the list, just in case
    if (actualAttachments.isNotEmpty) {
      final guids = actualAttachments.map((e) => e.guid).toSet();
      actualAttachments.retainWhere((element) => guids.remove(element.guid));
    }
    return actualAttachments;
  });
}

/// Async method to get messages from objectbox
Future<List<Message>> getMessagesIsolate(List<dynamic> stuff) async {
  /// Pull args from input and create new instances of store and boxes
  int chatId = stuff[0];
  int offset = stuff[1];
  int limit = stuff[2];
  bool includeDeleted = stuff[3];
  String? storeRef = stuff[4];
  final store = Store.fromReference(getObjectBoxModel(), base64.decode(storeRef!).buffer.asByteData());
  final handleBox = store.box<Handle>();
  final messageBox = store.box<Message>();
  final attachmentBox = store.box<Attachment>();
  final cmJoinBox = store.box<ChatMessageJoin>();
  final amJoinBox = store.box<AttachmentMessageJoin>();
  return store.runInTransaction(TxMode.read, () {
    /// Get the message IDs for the chat by querying the [cmJoinBox]
    final cmJoinQuery = cmJoinBox.query(ChatMessageJoin_.chatId.equals(chatId)).build();
    final messageIds = cmJoinQuery.property(ChatMessageJoin_.messageId).find();
    cmJoinQuery.close();
    /// Query [messsageBox] for the messages, including deleted when necessary
    /// and ordering in descending order
    final query = (messageBox.query(Message_.id.oneOf(messageIds)
        .and(includeDeleted ? Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()) : Message_.dateDeleted.isNull()))
      ..order(Message_.dateCreated, flags: Order.descending)..order(Message_.originalROWID, flags: Order.descending)).build();
    query
      ..limit = limit
      ..offset = offset;
    final messages = query.find();
    query.close();
    /// Fetch and match handles
    final handles = handleBox.getMany(messages.map((e) => e.handleId ?? 0).toList()..removeWhere((element) => element == 0));
    for (int i = 0; i < messages.length; i++) {
      Message message = messages[i];
      if (handles.isNotEmpty && message.handleId != 0) {
        Handle? handle = handles.firstWhereOrNull((e) => e?.id == message.handleId);
        if (handle == null) {
          messages.remove(message);
          i--;
        } else {
          message.handle = handle;
        }
      }
    }
    // Fetch attachments and reactions
    final amJoinQuery = amJoinBox.query(AttachmentMessageJoin_.messageId.oneOf(messageIds)).build();
    final amJoinValues = amJoinQuery.find();
    final attachmentIds = amJoinValues.map((e) => e.attachmentId).toSet().toList();
    amJoinQuery.close();
    final attachments = attachmentBox.getMany(attachmentIds, growableResult: true)..removeWhere((element) => element == null);
    final messageGuids = messages.map((e) => e.guid!).toList();
    final associatedMessagesQuery = (messageBox.query(Message_.associatedMessageGuid.oneOf(messageGuids))..order(Message_.originalROWID)).build();
    List<Message> associatedMessages = associatedMessagesQuery.find();
    associatedMessagesQuery.close();
    associatedMessages = MessageHelper.normalizedAssociatedMessages(associatedMessages);
    for (Message m in messages) {
      final attachmentIdsForMessage = amJoinValues.where((element) => element.messageId == m.id).map((e) => e.attachmentId).toList();
      m.attachments = attachments.where((element) => attachmentIdsForMessage.contains(element!.id)).toList();
      m.associatedMessages = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
    }
    return messages;
  });
}

/// Async method to get messages from objectbox
Future<List<Message>> addMessagesIsolate(List<dynamic> stuff) async {
  /// Pull args from input and create new instances of store and boxes
  List<Message> messages = stuff[0].map((e) => Message.fromMap(e)).toList().cast<Message>();
  String? storeRef = stuff[1];
  store = Store.fromReference(getObjectBoxModel(), base64.decode(storeRef!).buffer.asByteData());
  attachmentBox = store.box<Attachment>();
  chatBox = store.box<Chat>();
  handleBox = store.box<Handle>();
  messageBox = store.box<Message>();
  amJoinBox = store.box<AttachmentMessageJoin>();
  chJoinBox = store.box<ChatHandleJoin>();
  cmJoinBox = store.box<ChatMessageJoin>();
  /// Save the new messages and their attachments in a write transaction
  final newMessages = store.runInTransaction(TxMode.write, () {
    List<Message> newMessages = Message.bulkSave(messages);
    Attachment.bulkSave(Map.fromIterables(newMessages, newMessages.map((e) => (e.attachments ?? []).map((e) => e!).toList())));
    return newMessages;
  });
  /// fetch attachments and reactions in a read transaction
  return store.runInTransaction(TxMode.read, () {
    /// Query the [amJoinBox] for the attachment IDs matching the message IDs
    final amJoinQuery = amJoinBox.query(AttachmentMessageJoin_.messageId.oneOf(newMessages.map((e) => e.id!).toList())).build();
    final amJoinValues = amJoinQuery.find();
    final attachmentIds = amJoinValues.map((e) => e.attachmentId).toSet().toList();
    amJoinQuery.close();
    /// Query the [attachmentBox] for all the attachment IDs
    final attachments = attachmentBox.getMany(attachmentIds, growableResult: true)..removeWhere((element) => element == null);
    final messageGuids = newMessages.map((e) => e.guid!).toList();
    /// Query the [messageBox] for associated messages (reactions) matching the
    /// message IDs
    final associatedMessagesQuery = (messageBox.query(Message_.associatedMessageGuid.oneOf(messageGuids))..order(Message_.originalROWID)).build();
    List<Message> associatedMessages = associatedMessagesQuery.find();
    associatedMessagesQuery.close();
    associatedMessages = MessageHelper.normalizedAssociatedMessages(associatedMessages);
    /// Assign the relevant attachments and associated messages to the original
    /// messages
    for (Message m in newMessages) {
      final attachmentIdsForMessage = amJoinValues.where((element) => element.messageId == m.id).map((e) => e.attachmentId).toList();
      m.attachments = attachments.where((element) => attachmentIdsForMessage.contains(element!.id)).toList();
      m.associatedMessages = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
    }
    return newMessages;
  });
}

/// Async method to get chats from objectbox
Future<List<Chat>> getChatsIsolate(List<dynamic> stuff) async {
  /// Pull args from input and create new instances of store and boxes
  store = Store.fromReference(getObjectBoxModel(), base64.decode(stuff[2]).buffer.asByteData());
  attachmentBox = store.box<Attachment>();
  chatBox = store.box<Chat>();
  handleBox = store.box<Handle>();
  messageBox = store.box<Message>();
  amJoinBox = store.box<AttachmentMessageJoin>();
  chJoinBox = store.box<ChatHandleJoin>();
  cmJoinBox = store.box<ChatMessageJoin>();
  return store.runInTransaction(TxMode.read, () {
    /// Query the [chatBox] for chats with limit and offset, prioritize pinned
    /// chats and order by latest message date
    final query = (chatBox.query()..order(Chat_.isPinned, flags: Order.descending)..order(Chat_.latestMessageDate, flags: Order.descending)).build();
    query
      ..limit = stuff[0]
      ..offset = stuff[1];
    final chats = query.find();
    query.close();
    /// Query the [chJoinBox] to get the handle IDs associated with the chats
    final handleIdQuery = chJoinBox.query(ChatHandleJoin_.chatId.oneOf(chats.map((e) => e.id!).toList())).build();
    final chJoins = handleIdQuery.find();
    final handleIds = handleIdQuery.property(ChatHandleJoin_.handleId).find();
    handleIdQuery.close();
    /// Get the handles themselves
    final handles = handleBox.getMany(handleIds.toList(), growableResult: true)..retainWhere((e) => e != null);
    final nonNullHandles = List<Handle>.from(handles);
    /// Assign the handles to the chats, deduplicate, and get fake participants
    /// for redacted mode
    for (Chat c in chats) {
      final eligibleHandles = chJoins.where((element) => element.chatId == c.id).map((e) => e.handleId);
      c.participants = nonNullHandles.where((element) => eligibleHandles.contains(element.id)).toList();
      c._deduplicateParticipants();
      c.fakeParticipants = c.participants.map((p) => ContactManager().handleToFakeName[p.address] ?? "Unknown").toList();
    }
    return chats;
  });
}

@Entity()
class Chat {
  int? id;
  int? originalROWID;
  @Unique()
  String? guid;
  int? style;
  String? chatIdentifier;
  bool? isArchived;
  bool? isFiltered;
  String? muteType;
  String? muteArgs;
  bool? isPinned;
  bool? hasUnreadMessage;
  DateTime? latestMessageDate;
  String? latestMessageText;
  String? fakeLatestMessageText;
  String? title;
  String? displayName;
  List<Handle> participants = [];
  List<String> fakeParticipants = [];
  Message? latestMessage;
  final RxnString _customAvatarPath = RxnString();
  String? get customAvatarPath => _customAvatarPath.value;
  set customAvatarPath(String? s) => _customAvatarPath.value = s;
  final RxnInt _pinIndex = RxnInt();
  int? get pinIndex => _pinIndex.value;
  set pinIndex(int? i) => _pinIndex.value = i;

  Chat({
    this.id,
    this.originalROWID,
    this.guid,
    this.style,
    this.chatIdentifier,
    this.isArchived,
    this.isFiltered,
    this.isPinned,
    this.muteType,
    this.muteArgs,
    this.hasUnreadMessage,
    this.displayName,
    String? customAvatar,
    int? pinnedIndex,
    this.participants = const [],
    this.fakeParticipants = const [],
    this.latestMessage,
    this.latestMessageDate,
    this.latestMessageText,
    this.fakeLatestMessageText,
  }) {
    customAvatarPath = customAvatar;
    pinIndex = pinnedIndex;
  }

  factory Chat.fromMap(Map<String, dynamic> json) {
    List<Handle> participants = [];
    List<String> fakeParticipants = [];
    if (json.containsKey('participants')) {
      for (dynamic item in (json['participants'] as List<dynamic>)) {
        participants.add(Handle.fromMap(item));
        fakeParticipants.add(ContactManager().handleToFakeName[participants.last.address] ?? "Unknown");
      }
    }
    Message? message;
    if (json['lastMessage'] != null) {
      message = Message.fromMap(json['lastMessage']);
    }
    var data = Chat(
      id: json.containsKey("ROWID") ? json["ROWID"] : null,
      originalROWID: json.containsKey("originalROWID") ? json["originalROWID"] : null,
      guid: json["guid"],
      style: json['style'],
      chatIdentifier: json.containsKey("chatIdentifier") ? json["chatIdentifier"] : null,
      isArchived: (json["isArchived"] is bool) ? json['isArchived'] : ((json['isArchived'] == 1) ? true : false),
      isFiltered: json.containsKey("isFiltered")
          ? (json["isFiltered"] is bool)
              ? json['isFiltered']
              : ((json['isFiltered'] == 1) ? true : false)
          : false,
      muteType: json["muteType"],
      muteArgs: json["muteArgs"],
      isPinned: json.containsKey("isPinned")
          ? (json["isPinned"] is bool)
              ? json['isPinned']
              : ((json['isPinned'] == 1) ? true : false)
          : false,
      hasUnreadMessage: json.containsKey("hasUnreadMessage")
          ? (json["hasUnreadMessage"] is bool)
              ? json['hasUnreadMessage']
              : ((json['hasUnreadMessage'] == 1) ? true : false)
          : false,
      latestMessage: message,
      latestMessageText: json.containsKey("latestMessageText") ? json["latestMessageText"] : message != null ? MessageHelper.getNotificationText(message) : null,
      fakeLatestMessageText: json.containsKey("latestMessageText")
          ? faker.lorem.words((json["latestMessageText"] ?? "").split(" ").length).join(" ")
          : null,
      latestMessageDate: json.containsKey("latestMessageDate") && json['latestMessageDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['latestMessageDate'] as int)
          : message?.dateCreated,
      displayName: json.containsKey("displayName") ? json["displayName"] : null,
      customAvatar: json['_customAvatarPath'],
      pinnedIndex: json['_pinIndex'],
      participants: participants,
      fakeParticipants: fakeParticipants,
    );

    // Adds fallback getter for the ID
    data.id ??= json.containsKey("id") ? json["id"] : null;

    return data;
  }

  /// Save a chat to the DB
  Chat save() {
    if (kIsWeb) return this;
    store.runInTransaction(TxMode.write, () {
      /// Find an existing, and update the ID to the existing ID if necessary
      Chat? existing = Chat.findOne(guid: guid);
      id = existing?.id ?? id;
      /// Save the chat and add the participants
      try {
        id = chatBox.put(this);
      } on UniqueViolationException catch (_) {}
      // Save participants to the chat
      for (int i = 0; i < participants.length; i++) {
        addParticipant(participants[i]);
      }
    });
    return this;
  }

  /// Change a chat's display name
  Chat changeName(String? name) {
    if (kIsWeb) {
      displayName = name;
      return this;
    }
    displayName = name;
    save();
    return this;
  }

  /// Get a chat's title
  String? getTitle() {
    title = getFullChatTitle(this);
    return title;
  }

  /// Get the latest message date as text
  String getDateText() {
    return buildDate(latestMessageDate);
  }

  /// Return whether or not the notification should be muted
  bool shouldMuteNotification(Message? message) {
    if (muteType == "mute") {
      return true;
    /// Check if the sender is muted
    } else if (muteType == "mute_individuals") {
      List<String> individuals = muteArgs!.split(",");
      return individuals.contains(message?.handle?.address ?? "");
    /// Check if the chat is temporarily muted
    } else if (muteType == "temporary_mute") {
      DateTime time = DateTime.parse(muteArgs!);
      bool shouldMute = DateTime.now().toLocal().difference(time).inSeconds.isNegative;
      if (!shouldMute) {
        toggleMute(false);
        muteType = null;
        muteArgs = null;
        save();
      }
      return shouldMute;
    /// Check if the chat has specific text detection and notify accordingly
    } else if (muteType == "text_detection") {
      List<String> text = muteArgs!.split(",");
      for (String s in text) {
        if (message?.text?.toLowerCase().contains(s.toLowerCase()) ?? false) {
          return false;
        }
      }
      return true;
    }
    return true;
  }

  /// Delete a chat locally
  static void deleteChat(Chat chat) {
    if (kIsWeb) return;
    List<Message> messages = Chat.getMessages(chat);
    store.runInTransaction(TxMode.write, () {
      /// Remove all references of chat - from chatBox, messageBox,
      /// chJoinBox, and cmJoinBox
      chatBox.remove(chat.id!);
      messageBox.removeMany(messages.map((e) => e.id!).toList());
      final query = chJoinBox.query(ChatHandleJoin_.chatId.equals(chat.id!)).build();
      final results = query.property(ChatHandleJoin_.id).find();
      query.close();
      chJoinBox.removeMany(results);
      final query2 = cmJoinBox.query(ChatMessageJoin_.chatId.equals(chat.id!)).build();
      final results2 = query2.property(ChatMessageJoin_.id).find();
      query2.close();
      cmJoinBox.removeMany(results2);
    });
  }

  Chat toggleHasUnread(bool hasUnread) {
    if (hasUnread) {
      if (CurrentChat.isActive(guid!)) {
        return this;
      }
    }

    hasUnreadMessage = hasUnread;
    save();

    if (hasUnread) {
      EventDispatcher().emit("add-unread-chat", {"chatGuid": guid});
    } else {
      EventDispatcher().emit("remove-unread-chat", {"chatGuid": guid});
    }

    ChatBloc().updateUnreads();
    return this;
  }

  Future<Chat> addMessage(Message message, {bool changeUnreadStatus = true, bool checkForMessageText = true}) async {
    // If this is a message preview and we don't already have metadata for this, get it
    if (message.fullText.replaceAll("\n", " ").hasUrl && !MetadataHelper.mapIsNotEmpty(message.metadata)) {
      MetadataHelper.fetchMetadata(message).then((Metadata? meta) async {
        // If the metadata is empty, don't do anything
        if (!MetadataHelper.isNotEmpty(meta)) return;

        // Save the metadata to the object
        message.metadata = meta!.toJson();

      });
    }

    // Save the message
    Message? existing = Message.findOne(guid: message.guid);
    Message? newMessage;

    try {
      newMessage = message.save();
    } catch (ex, stacktrace) {
      newMessage = Message.findOne(guid: message.guid);
      if (newMessage == null) {
        Logger.error(ex.toString());
        Logger.error(stacktrace.toString());
      }
    }
    bool isNewer = false;

    // If the message was saved correctly, update this chat's latestMessage info,
    // but only if the incoming message's date is newer
    if ((newMessage?.id != null || kIsWeb) && checkForMessageText) {
      if (latestMessageDate == null) {
        isNewer = true;
      } else if (latestMessageDate!.millisecondsSinceEpoch < message.dateCreated!.millisecondsSinceEpoch) {
        isNewer = true;
      }
    }

    if (isNewer && checkForMessageText) {
      latestMessage = message;
      latestMessageText = MessageHelper.getNotificationText(message);
      fakeLatestMessageText = faker.lorem.words((latestMessageText ?? "").split(" ").length).join(" ");
      latestMessageDate = message.dateCreated;
    }

    // Save any attachments
    for (Attachment? attachment in message.attachments ?? []) {
      attachment!.save(newMessage);
    }

    // Save the chat.
    // This will update the latestMessage info as well as update some
    // other fields that we want to "mimic" from the server
    save();

    try {
      // Add the relationship
      cmJoinBox.put(ChatMessageJoin(chatId: id!, messageId: message.id!));
    } catch (ex) {
      // Don't do anything if it already exists
    }

    // If the incoming message was newer than the "last" one, set the unread status accordingly
    if (checkForMessageText && changeUnreadStatus && isNewer && existing == null) {
      // If the message is from me, mark it unread
      // If the message is not from the same chat as the current chat, mark unread
      if (message.isFromMe!) {
        toggleHasUnread(false);
      } else if (!CurrentChat.isActive(guid!)) {
        toggleHasUnread(true);
      }
    }

    if (checkForMessageText) {
      // Update the chat position
      ChatBloc().updateChatPosition(this);
    }

    // If the message is for adding or removing participants,
    // we need to ensure that all of the chat participants are correct by syncing with the server
    if (isParticipantEvent(message) && checkForMessageText) {
      serverSyncParticipants();
    }

    // Return the current chat instance (with updated vals)
    return this;
  }

  /// Add a lot of messages for the single chat to avoid running [addMessage]
  /// in a loop
  Future<List<Message>> bulkAddMessages(List<Message> messages, {bool changeUnreadStatus = true, bool checkForMessageText = true}) async {
    for (Message m in messages) {
      // If this is a message preview and we don't already have metadata for this, get it
      if (!m.fullText.replaceAll("\n", " ").hasUrl || MetadataHelper.mapIsNotEmpty(m.metadata)) continue;
      Metadata? meta = await MetadataHelper.fetchMetadata(m);
      if (!MetadataHelper.isNotEmpty(meta)) continue;

      // Save the metadata to the object
      m.metadata = meta!.toJson();

    }

    // Save to DB
    final newMessages = await compute(addMessagesIsolate, [messages.map((e) => e.toMap(includeObjects: true)).toList(), prefs.getString("objectbox-reference")]);
    cmJoinBox.putMany(newMessages.map((e) => ChatMessageJoin(chatId: id!, messageId: e.id!)).toList());

    Message? newer = newMessages
        .where((e) => (latestMessageDate?.millisecondsSinceEpoch ?? 0) < e.dateCreated!.millisecondsSinceEpoch)
        .sorted((a, b) => b.dateCreated!.compareTo(a.dateCreated!)).firstOrNull;

    // If the incoming message was newer than the "last" one, set the unread status accordingly
    if (checkForMessageText && changeUnreadStatus && newer != null) {
      // If the message is from me, mark it unread
      // If the message is not from the same chat as the current chat, mark unread
      if (newer.isFromMe!) {
        toggleHasUnread(false);
      } else if (!CurrentChat.isActive(guid!)) {
        toggleHasUnread(true);
      }
    }

    if (checkForMessageText) {
      // Update the chat position
      ChatBloc().updateChatPosition(this);
    }

    // If the message is for adding or removing participants,
    // we need to ensure that all of the chat participants are correct by syncing with the server
    Message? participantEvent = messages.firstWhereOrNull((element) => isParticipantEvent(element));
    if (participantEvent != null && checkForMessageText) {
      serverSyncParticipants();
    }

    if (newer != null && checkForMessageText) {
      latestMessage = newer;
      latestMessageText = MessageHelper.getNotificationText(newer);
      fakeLatestMessageText = faker.lorem.words((latestMessageText ?? "").split(" ").length).join(" ");
      latestMessageDate = newer.dateCreated;
    }

    save();

    // Return the current chat instance (with updated vals)
    return newMessages;
  }

  void serverSyncParticipants() {
    // Send message to server to get the participants
    SocketManager().sendMessage("get-participants", {"identifier": guid}, (response) {
      if (response["status"] == 200) {
        // Get all the participants from the server
        List data = response["data"];
        List<Handle> handles = data.map((e) => Handle.fromMap(e)).toList();

        // Make sure that all participants for our local chat are fetched
        getParticipants();

        // We want to determine all the participants that exist in the response that are not already in our locally saved chat (AKA all the new participants)
        List<Handle> newParticipants = handles
            .where((a) => (participants.where((b) => b.address == a.address).toList().isEmpty))
            .toList();

        // We want to determine all the participants that exist in the locally saved chat that are not in the response (AKA all the removed participants)
        List<Handle> removedParticipants = participants
            .where((a) => (handles.where((b) => b.address == a.address).toList().isEmpty))
            .toList();

        // Add all participants that are missing from our local db
        for (Handle newParticipant in newParticipants) {
          addParticipant(newParticipant);
        }

        // Remove all extraneous participants from our local db
        for (Handle removedParticipant in removedParticipants) {
          removedParticipant.save();
          removeParticipant(removedParticipant);
        }

        // Sync all changes with the chatbloc
        ChatBloc().updateChat(this);
      }
    });
  }

  static int? count() {
    return chatBox.count();
  }

  Future<List<Attachment>> getAttachmentsAsync() async {
    if (kIsWeb || id == null) return [];

    return await compute(getAttachmentsIsolate, [id!, prefs.getString("objectbox-reference")]);
  }

  /// Gets messages synchronously - DO NOT use in performance-sensitive areas,
  /// otherwise prefer [getMessagesAsync]
  static List<Message> getMessages(Chat chat, {int offset = 0, int limit = 25, bool includeDeleted = false, bool getDetails = false}) {
    if (kIsWeb || chat.id == null) return [];
    return store.runInTransaction(TxMode.read, () {
      final messageIdQuery = cmJoinBox.query(ChatMessageJoin_.chatId.equals(chat.id!)).build();
      final messageIds = messageIdQuery.property(ChatMessageJoin_.messageId).find();
      messageIdQuery.close();
      final query = (messageBox.query(Message_.id.oneOf(messageIds)
          .and(includeDeleted ? Message_.dateDeleted.isNull().or(Message_.dateDeleted.notNull()) : Message_.dateDeleted.isNull()))
        ..order(Message_.dateCreated, flags: Order.descending)..order(Message_.originalROWID, flags: Order.descending)).build();
      query
        ..limit = limit
        ..offset = offset;
      final messages = query.find();
      query.close();
      final handles = handleBox.getMany(messages.map((e) => e.handleId ?? 0).toList()..removeWhere((element) => element == 0));
      for (int i = 0; i < messages.length; i++) {
        Message message = messages[i];
        if (handles.isNotEmpty && message.handleId != 0) {
          Handle? handle = handles.firstWhereOrNull((e) => e?.id == message.handleId);
          if (handle == null) {
            messages.remove(message);
            i--;
          } else {
            message.handle = handle;
          }
        }
      }
      // fetch attachments and reactions if requested
      if (getDetails) {
        final amJoinQuery = amJoinBox.query(AttachmentMessageJoin_.messageId.oneOf(messageIds)).build();
        final amJoinValues = amJoinQuery.find();
        final attachmentIds = amJoinValues.map((e) => e.attachmentId).toSet().toList();
        amJoinQuery.close();
        final attachments = attachmentBox.getMany(attachmentIds, growableResult: true)..removeWhere((element) => element == null);
        final messageGuids = messages.map((e) => e.guid!).toList();
        final associatedMessagesQuery = (messageBox.query(Message_.associatedMessageGuid.oneOf(messageGuids))..order(Message_.originalROWID)).build();
        List<Message> associatedMessages = associatedMessagesQuery.find();
        associatedMessagesQuery.close();
        associatedMessages = MessageHelper.normalizedAssociatedMessages(associatedMessages);
        for (Message m in messages) {
          final attachmentIdsForMessage = amJoinValues.where((element) => element.messageId == m.id).map((e) => e.attachmentId).toList();
          m.attachments = attachments.where((element) => attachmentIdsForMessage.contains(element!.id)).toList();
          m.associatedMessages = associatedMessages.where((e) => e.associatedMessageGuid == m.guid).toList();
        }
      }
      return messages;
    });
  }

  /// Fetch messages asynchronously
  static Future<List<Message>> getMessagesAsync(Chat chat, {int offset = 0, int limit = 25, bool includeDeleted = false}) async {
    if (kIsWeb || chat.id == null) return [];

    return await compute(getMessagesIsolate, [chat.id, offset, limit, includeDeleted, prefs.getString("objectbox-reference")]);
  }

  Chat getParticipants() {
    if (kIsWeb || id == null) return this;
    store.runInTransaction(TxMode.read, () {
      /// Query the [chJoinBox] for matching handles
      final handleIdQuery = chJoinBox.query(ChatHandleJoin_.chatId.equals(id!)).build();
      final handleIds = handleIdQuery.property(ChatHandleJoin_.handleId).find();
      handleIdQuery.close();
      /// Find the handles themselves
      final handles = handleBox.getMany(handleIds.toList(), growableResult: true)..retainWhere((e) => e != null);
      final nonNullHandles = List<Handle>.from(handles);
      participants = nonNullHandles;
    });
    /// Deduplicate and generate fake participants for redacted mode
    _deduplicateParticipants();
    fakeParticipants = participants.map((p) => ContactManager().handleToFakeName[p.address] ?? "Unknown").toList();
    return this;
  }

  Chat addParticipant(Handle participant) {
    if (kIsWeb) {
      participants.add(participant);
      _deduplicateParticipants();
      return this;
    }
    // Save participant and add to list
    participant = participant.save();
    if (participant.id == null) return this;

    try {
      chJoinBox.put(ChatHandleJoin(chatId: id!, handleId: participant.id!));
    } catch (_) {}

    // Add to the class and deduplicate
    participants.add(participant);
    _deduplicateParticipants();
    return this;
  }

  Chat removeParticipant(Handle participant) {
    if (kIsWeb) {
      participants.removeWhere((element) => participant.id == element.id);
      _deduplicateParticipants();
      return this;
    }

    // find the join item and delete it
    store.runInTransaction(TxMode.write, () {
      final query = chJoinBox.query(ChatHandleJoin_.handleId.equals(participant.id!).and(ChatHandleJoin_.chatId.equals(id!))).build();
      final result = query.findFirst();
      query.close();
      if (result != null) chJoinBox.remove(result.id!);
    });

    // Second, remove from this object instance
    participants.removeWhere((element) => participant.id == element.id);
    _deduplicateParticipants();
    return this;
  }

  void _deduplicateParticipants() {
    if (participants.isEmpty) return;
    final ids = participants.map((e) => e.address).toSet();
    participants.retainWhere((element) => ids.remove(element.address));
  }

  Chat togglePin(bool isPinned) {
    if (id == null) return this;
    this.isPinned = isPinned;
    _pinIndex.value = null;
    save();
    ChatBloc().updateChat(this);
    return this;
  }

  Chat toggleMute(bool isMuted) {
    if (id == null) return this;
    muteType = isMuted ? "mute" : null;
    muteArgs = null;
    save();
    ChatBloc().updateChat(this);
    return this;
  }

  Chat toggleArchived(bool isArchived) {
    if (id == null) return this;
    this.isArchived = isArchived;
    save();
    ChatBloc().updateChat(this);
    return this;
  }

  /// Finds a chat - only use this method on Flutter Web!!!
  static Future<Chat?> findOneWeb({String? guid, String? chatIdentifier}) async {
    await ChatBloc().chatRequest!.future;
    if (guid != null) {
      return ChatBloc().chats.firstWhere((e) => e.guid == guid);
    } else if (chatIdentifier != null) {
      return ChatBloc().chats.firstWhereOrNull((e) => e.chatIdentifier == chatIdentifier);
    }
    return null;
  }

  /// Finds a chat - DO NOT use this method on Flutter Web!! Prefer [findOneWeb]
  /// instead!!
  static Chat? findOne({String? guid, String? chatIdentifier}) {
    if (guid != null) {
      final query = chatBox.query(Chat_.guid.equals(guid)).build();
      final result = query.findFirst();
      query.close();
      return result;
    } else if (chatIdentifier != null) {
      final query = chatBox.query(Chat_.chatIdentifier.equals(chatIdentifier)).build();
      final result = query.findFirst();
      query.close();
      return result;
    }
    return null;
  }

  static Future<List<Chat>> getChats({int limit = 15, int offset = 0}) async {
    if (kIsWeb) throw Exception("Use socket to get chats on Web!");

    return await compute(getChatsIsolate, [limit, offset, prefs.getString("objectbox-reference")!]);
  }

  bool isGroup() {
    return participants.length > 1;
  }

  void clearTranscript() {
    if (kIsWeb) return;
    store.runInTransaction(TxMode.write, () {
      final messageIdQuery = cmJoinBox.query(ChatMessageJoin_.chatId.equals(id!)).build();
      final messageIds = messageIdQuery.property(ChatMessageJoin_.messageId).find();
      messageIdQuery.close();
      final messages = messageBox.getMany(messageIds, growableResult: true)..removeWhere((e) => e == null);
      final nonNullMessages = List<Message>.from(messages);
      for (Message element in nonNullMessages) {
        element.dateDeleted = DateTime.now().toUtc();
      }
      messageBox.putMany(nonNullMessages);
    });
  }

  Message get latestMessageGetter {
    if (latestMessage != null) return latestMessage!;
    List<Message> latest = Chat.getMessages(this, limit: 1);
    Message message = latest.first;
    latestMessage = message;
    if (message.hasAttachments) {
      message.fetchAttachments();
    }
    return message;
  }

  static int sort(Chat? a, Chat? b) {
    if (a!._pinIndex.value != null && b!._pinIndex.value != null) return a._pinIndex.value!.compareTo(b._pinIndex.value!);
    if (b!._pinIndex.value != null) return 1;
    if (a._pinIndex.value != null) return -1;
    if (!a.isPinned! && b.isPinned!) return 1;
    if (a.isPinned! && !b.isPinned!) return -1;
    if (a.latestMessageDate == null && b.latestMessageDate == null) return 0;
    if (a.latestMessageDate == null) return 1;
    if (b.latestMessageDate == null) return -1;
    return -a.latestMessageDate!.compareTo(b.latestMessageDate!);
  }

  static void flush() {
    if (kIsWeb) return;
    chatBox.removeAll();
  }

  Map<String, dynamic> toMap() => {
        "ROWID": id,
        "originalROWID": originalROWID,
        "guid": guid,
        "style": style,
        "chatIdentifier": chatIdentifier,
        "isArchived": isArchived! ? 1 : 0,
        "isFiltered": isFiltered! ? 1 : 0,
        "muteType": muteType,
        "muteArgs": muteArgs,
        "isPinned": isPinned! ? 1 : 0,
        "displayName": displayName,
        "participants": participants.map((item) => item.toMap()).toList(),
        "hasUnreadMessage": hasUnreadMessage! ? 1 : 0,
        "latestMessageDate": latestMessageDate != null ? latestMessageDate!.millisecondsSinceEpoch : 0,
        "latestMessageText": latestMessageText,
        "_customAvatarPath": _customAvatarPath.value,
        "_pinIndex": _pinIndex.value,
      };
}
