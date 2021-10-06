import 'dart:async';
import 'dart:ui';

import 'package:bluebubbles_wearos/action_handler.dart';
import 'package:bluebubbles_wearos/blocs/message_bloc.dart';
import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_details/conversation_details.dart';
import 'package:bluebubbles_wearos/layouts/widgets/contact_avatar_widget.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_widget.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/new_message_loader.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/life_cycle_manager.dart';
import 'package:bluebubbles_wearos/managers/new_message_manager.dart';
import 'package:bluebubbles_wearos/managers/notification_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class MessagesView extends StatefulWidget {
  final MessageBloc? messageBloc;
  final bool showHandle;
  final Chat? chat;
  final Function? initComplete;
  final List<Message> messages;
  final Function send;
  final FocusNode node;

  MessagesView({
    Key? key,
    this.messageBloc,
    required this.showHandle,
    this.chat,
    this.initComplete,
    this.messages = const [],
    required this.send,
    required this.node,
  }) : super(key: key);

  @override
  MessagesViewState createState() => MessagesViewState();
}

class MessagesViewState extends State<MessagesView> with TickerProviderStateMixin, WidgetsBindingObserver {
  Completer<LoadMessageResult>? loader;
  bool noMoreMessages = false;
  bool noMoreLocalMessages = false;
  List<Message> _messages = <Message>[];

  GlobalKey<SliverAnimatedListState>? _listKey;
  final Duration animationDuration = Duration(milliseconds: 400);
  final smartReply = GoogleMlKit.nlp.smartReply();
  bool initializedList = false;
  List<int> loadedPages = [];
  CurrentChat? currentChat;
  bool keyboardOpen = false;

  List<Message> currentMessages = [];
  List<String> replies = [];
  Map<String, Widget> internalSmartReplies = {};

  late StreamController<List<String>> smartReplyController;

  ScrollController? get scrollController {
    if (currentChat == null) return null;

    return currentChat!.scrollController;
  }
  bool widgetsBuilt = false;

  @override
  void initState() {
    super.initState();

    currentChat = CurrentChat.of(context);
    if (widget.messageBloc != null) ever<MessageBlocEvent?>(widget.messageBloc!.event, (e) => handleNewMessage(e));

    // See if we need to load anything from the message bloc
    if (widget.messages.isNotEmpty) {
      _messages = widget.messages;
    } else if (_messages.isEmpty && widget.messageBloc!.messages.isEmpty) {
      widget.messageBloc!.getMessages();
    } else if (_messages.isEmpty && widget.messageBloc!.messages.isNotEmpty) {
      widget.messageBloc!.emitLoaded();
    }

    smartReplyController = StreamController<List<String>>.broadcast();

    EventDispatcher().stream.listen((Map<String, dynamic> event) async {
      if (!mounted) return;
      if (!event.containsKey("type")) return;

      if (event["type"] == "refresh-messagebloc" && event["data"].containsKey("chatGuid")) {
        // Handle event's that require a matching guid
        String? chatGuid = event["data"]["chatGuid"];
        if (widget.chat!.guid == chatGuid) {
          if (event["type"] == "refresh-messagebloc") {
            // Clear state items
            noMoreLocalMessages = false;
            noMoreMessages = false;
            _messages = [];
            loadedPages = [];

            // Reload the state after refreshing
            widget.messageBloc!.refresh();
            if (mounted) {
              await rebuild(this);
            }
          }
        }
      } else if (event["type"] == "add-custom-smartreply") {
        if (event["data"]["path"] != null) {
          internalSmartReplies.addEntries([_buildReply("Attach recent photo", onTap: () async {
            EventDispatcher().emit('add-attachment', event['data']);
            internalSmartReplies.remove('Attach recent photo');
            await rebuild(this);
          })]);
          await rebuild(this);
        }
      }
    });

    WidgetsBinding.instance!.addObserver(this);

    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
      widgetsBuilt = true;
      EventDispatcher().emit("update-highlight", widget.chat!.guid);
    });

    if (widget.initComplete != null) widget.initComplete!();
  }

  Future<void> resetReplies() async {
    if (replies.isEmpty) return;
    replies = [];
    internalSmartReplies.clear();
    await rebuild(this);
    return smartReplyController.sink.add(replies);
  }

  void updateReplies() async {
    // If there are no messages or the latest message is from me, reset the replies
    if (isNullOrEmpty(_messages)!) return await resetReplies();
    if (_messages.first.isFromMe!) return await resetReplies();
    if (kIsWeb || kIsDesktop) return await resetReplies();

    Logger.info("Getting smart replies...");
    Map<String, dynamic> results = await smartReply.suggestReplies();

    if (results.containsKey('suggestions')) {
      List<SmartReplySuggestion> suggestions = results['suggestions'];
      Logger.info("Smart Replies found: ${suggestions.length}");
      replies = suggestions.map((e) => e.getText()).toList().toSet().toList();
      Logger.debug(replies.toString());
    }

    // If there is nothing in the list, get out
    if (isNullOrEmpty(replies)!) {
      resetReplies();
      return;
    }

    // If everything passes, add replies to the stream
    if (!smartReplyController.isClosed) smartReplyController.sink.add(replies);
  }

  Future<void>? loadNextChunk() {
    if (noMoreMessages || loadedPages.contains(_messages.length)) return null;
    int messageCount = _messages.length;

    // If we already are loading a chunk, don't load again
    if (loader != null && !loader!.isCompleted) {
      return loader!.future;
    }

    // Create a new completer
    loader = Completer();
    loadedPages.add(messageCount);

    // Start loading the next chunk of messages
    widget.messageBloc!
        .loadMessageChunk(_messages.length, checkLocal: !noMoreLocalMessages)
        .then((LoadMessageResult val) {
      if (val != LoadMessageResult.FAILED_TO_RETRIEVE) {
        if (val == LoadMessageResult.RETRIEVED_NO_MESSAGES) {
          noMoreMessages = true;
          Logger.info("No more messages to load", tag: "MessageBloc");
        } else if (val == LoadMessageResult.RETRIEVED_LAST_PAGE) {
          // Mark this chat saying we have no more messages to load
          noMoreLocalMessages = true;
        }
      }

      // Complete the future
      loader!.complete(val);
    }).catchError((ex) {
      loader!.complete(LoadMessageResult.FAILED_TO_RETRIEVE);
    });

    return loader!.future;
  }

  void handleNewMessage(MessageBlocEvent? event) async {
    // Get outta here if we don't have a chat "open"
    if (currentChat == null) return;
    if (event == null) return;

    // Skip deleted messages
    if (event.message != null && event.message!.dateDeleted != null) return;
    if (!isNullOrEmpty(event.messages)!) {
      event.messages = event.messages.where((element) => element.dateDeleted == null).toList();
    }
    int originalMessageLength = _messages.length;
    if (event.type == MessageBlocEventType.insert && mounted) {
      if (LifeCycleManager().isAlive && !event.outGoing) {
        NotificationManager().switchChat(CurrentChat.of(context)?.chat);
      }

      bool isNewMessage = true;
      for (Message? message in _messages) {
        if (message!.guid == event.message!.guid) {
          isNewMessage = false;
          break;
        }
      }

      _messages = event.messages;
      if (_listKey != null && _listKey!.currentState != null) {
        _listKey!.currentState!.insertItem(
          event.index != null ? event.index! : 0,
          duration: isNewMessage
              ? event.outGoing
                  ? Duration(milliseconds: 300)
                  : animationDuration
              : Duration(milliseconds: 0),
        );
      }

      if (event.outGoing) {
        currentChat!.sentMessages.add(event.message);
        Future.delayed(Duration(milliseconds: 300) * 2, () {
          currentChat!.sentMessages.removeWhere((element) => element!.guid == event.message!.guid);
        });
      }

      if (event.outGoing) await Future.delayed(Duration(milliseconds: 300));

      currentChat!.getAttachmentsForMessage(event.message);

      if (event.message!.hasAttachments) {
        await currentChat!.updateChatAttachments();
      }

    } else if (event.type == MessageBlocEventType.remove) {
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].guid == event.remove && _listKey!.currentState != null) {
          _messages.removeAt(i);
          _listKey!.currentState!.removeItem(i, (context, animation) => Container());
        }
      }
    } else {
      _messages = event.messages;
      /*for (Message message in _messages) {
        currentChat?.getAttachmentsForMessage(message);
        if (widgetsBuilt) currentChat?.messageMarkers.updateMessageMarkers(message);
      }*/

      // This needs to be in reverse so that the oldest message gets added first
      // We also only want to grab the last 5, so long as there are at least 5 results
      List<Message> reversed = _messages.reversed.toList();
      int sampleSize = (_messages.length > 5) ? 5 : _messages.length;
      reversed.sublist(reversed.length - sampleSize).forEach((message) {
        if (!isEmptyString(message.fullText, stripWhitespace: true) && !kIsWeb && !kIsDesktop) {
          if (message.isFromMe ?? false) {
            smartReply.addConversationForLocalUser(message.fullText);
          } else {
            smartReply.addConversationForRemoteUser(message.fullText, message.handle?.address ?? "participant");
          }
        }
      });

      _listKey ??= GlobalKey<SliverAnimatedListState>();

      if (originalMessageLength < _messages.length) {
        for (int i = originalMessageLength; i < _messages.length; i++) {
          if (_listKey != null && _listKey!.currentState != null) {
            if (SchedulerBinding.instance!.schedulerPhase != SchedulerPhase.idle) {
              // wait for the end of that frame.
              await SchedulerBinding.instance!.endOfFrame;
            }
            _listKey!.currentState!.insertItem(i, duration: Duration(milliseconds: 0));
          }
        }
      } else if (originalMessageLength > _messages.length) {
        for (int i = originalMessageLength; i >= _messages.length; i--) {
          if (_listKey != null && _listKey!.currentState != null) {
            try {
              if (SchedulerBinding.instance!.schedulerPhase != SchedulerPhase.idle) {
                // wait for the end of that frame.
                await SchedulerBinding.instance!.endOfFrame;
              }
              _listKey!.currentState!
                  .removeItem(i, (context, animation) => Container(), duration: Duration(milliseconds: 0));
            } catch (ex) {
              Logger.error("Error removing item animation");
              Logger.error(ex.toString());
            }
          }
        }
      } else {
        await rebuild(this);
      }
    }

    if (originalMessageLength == 0) await rebuild(this);
  }

  /// All message update events are handled within the message widgets, to prevent top level setstates
  Message? onUpdateMessage(NewMessageEvent event) {
    if (event.type != NewMessageType.UPDATE) return null;
    currentChat!.updateExistingAttachments(event);

    String? oldGuid = event.event["oldGuid"];
    Message? message = event.event["message"];

    bool updatedAMessage = false;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].guid == oldGuid) {
        Logger.info("Update message: [${message!.text}] - [${message.guid}] - [$oldGuid]", tag: "MessageStatus");
        _messages[i] = message;
        updatedAMessage = true;
        break;
      }
    }
    if (!updatedAMessage) {
      Logger.warn("Message not updated (not found): [${message!.text}] - [${message.guid}] - [$oldGuid]",
          tag: "MessageStatus");
    }

    return message;
  }

  MapEntry<String, Widget> _buildReply(String text, {Function()? onTap}) => MapEntry(text, Container(
        margin: EdgeInsets.all(5),
        decoration: BoxDecoration(
          border: Border.all(
            width: 2,
            style: BorderStyle.solid,
            color: Theme.of(context).accentColor,
          ),
          borderRadius: BorderRadius.circular(19),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19),
          ),
          onTap: onTap ?? () {
            ActionHandler.sendMessage(currentChat!.chat, text);
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 13.0),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyText1,
              ),
            ),
          ),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragStart: (details) {},
        onHorizontalDragUpdate: (details) {
          CurrentChat.of(context)!.timeStampOffset += details.delta.dx * 0.3;
        },
        onHorizontalDragEnd: (details) {
          CurrentChat.of(context)!.timeStampOffset = 0;
        },
        onHorizontalDragCancel: () {
          CurrentChat.of(context)!.timeStampOffset = 0;
        },
        child: CustomScrollView(
          controller: scrollController ?? ScrollController(),
          reverse: true,
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Offstage(
                    child: Container(
                      width: 1,
                      child: TextField(
                        focusNode: widget.node,
                        onSubmitted: (str) {
                          widget.node.unfocus();
                          widget.send.call(<PlatformFile>[], str);
                        },
                      ),
                    ),
                  ),
                  Stack(
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        margin: EdgeInsets.only(left: 5.0, right: 5.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: ClipRRect(
                          child: InkWell(
                            onTap: () {
                              FocusScope.of(context).requestFocus(widget.node);
                              SystemChannels.textInput.invokeMethod('TextInput.show');
                            },
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: 1,
                                  left: 0),
                              child: Icon(
                                Icons.keyboard,
                                color: Colors.white.withAlpha(225),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    height: 40,
                    width: 40,
                    margin: EdgeInsets.only(left: 5.0, right: 5.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: ClipRRect(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (context) => ConversationDetails(
                                chat: widget.chat!,
                                messageBloc: widget.messageBloc ?? MessageBloc(widget.chat),
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: 1,
                              left: 0),
                          child: Icon(
                            Icons.more_vert,
                            color: Colors.white.withAlpha(225),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _listKey != null
                    ? SliverAnimatedList(
                        initialItemCount: _messages.length + 1,
                        key: _listKey,
                        itemBuilder: (BuildContext context, int index, Animation<double> animation) {
                          // Load more messages if we are at the top and we aren't alrady loading
                          // and we have more messages to load
                          if (index == _messages.length) {
                            if (!noMoreMessages &&
                                (loader == null || !loader!.isCompleted || !loadedPages.contains(_messages.length))) {
                              loadNextChunk();
                              return NewMessageLoader();
                            }

                            return Container();
                          } else if (index > _messages.length) {
                            return Container();
                          }

                          Message? olderMessage;
                          Message? newerMessage;
                          if (index + 1 >= 0 && index + 1 < _messages.length) {
                            olderMessage = _messages[index + 1];
                          }
                          if (index - 1 >= 0 && index - 1 < _messages.length) {
                            newerMessage = _messages[index - 1];
                          }

                          bool fullAnimation =
                              index == 0 && (!_messages[index].isFromMe! || _messages[index].originalROWID == null);

                          Widget messageWidget = Padding(
                              padding: EdgeInsets.only(left: 5.0, right: 5.0),
                              child: MessageWidget(
                                key: Key(_messages[index].guid!),
                                message: _messages[index],
                                olderMessage: olderMessage,
                                newerMessage: newerMessage,
                                showHandle: widget.showHandle,
                                isFirstSentMessage: widget.messageBloc!.firstSentMessage == _messages[index].guid,
                                showHero: fullAnimation,
                                onUpdate: (event) => onUpdateMessage(event),
                                bloc: widget.messageBloc!,
                              ));

                          if (fullAnimation) {
                            return SizeTransition(
                              axis: Axis.vertical,
                              sizeFactor: animation
                                  .drive(Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOut))),
                              child: SlideTransition(
                                position: animation.drive(
                                  Tween(
                                    begin: Offset(0.0, 1),
                                    end: Offset(0.0, 0.0),
                                  ).chain(
                                    CurveTween(
                                      curve: Curves.easeInOut,
                                    ),
                                  ),
                                ),
                                child: Opacity(
                                  opacity: animation.isCompleted || !_messages[index].isFromMe! ? 1 : 0,
                                  child: messageWidget,
                                ),
                              ),
                            );
                          }

                          return messageWidget;
                        })
                    : SliverToBoxAdapter(child: Container()),
            SliverPadding(
              padding: EdgeInsets.all(70),
            ),
          ],
        ));
  }

  @override
  void dispose() {
    if (!smartReplyController.isClosed) smartReplyController.close();
    smartReply.close();
    super.dispose();
  }
}
