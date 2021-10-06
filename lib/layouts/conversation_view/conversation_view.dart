import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles_wearos/action_handler.dart';
import 'package:bluebubbles_wearos/blocs/chat_bloc.dart';
import 'package:bluebubbles_wearos/blocs/message_bloc.dart';
import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/hex_color.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/helpers/ui_helpers.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/conversation_view_mixin.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/messages_view.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/new_chat_creator/chat_selector_text_field.dart';
import 'package:bluebubbles_wearos/layouts/conversation_view/text_field/blue_bubbles_text_field.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/message_attachments.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_widget_mixin.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/sent_message.dart';
import 'package:bluebubbles_wearos/main.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/life_cycle_manager.dart';
import 'package:bluebubbles_wearos/managers/notification_manager.dart';
import 'package:bluebubbles_wearos/managers/outgoing_queue.dart';
import 'package:bluebubbles_wearos/managers/queue_manager.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/platform_file.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:simple_animations/simple_animations.dart';
import 'package:slugify/slugify.dart';

abstract class ChatSelectorTypes {
  static const String all = "ALL";
  static const String onlyExisting = "ONLY_EXISTING";
  static const String onlyContacts = "ONLY_CONTACTS";
}

class ConversationView extends StatefulWidget {
  final List<PlatformFile> existingAttachments;
  final String? existingText;
  final List<UniqueContact> selected;

  ConversationView({
    Key? key,
    this.chat,
    this.existingAttachments = const [],
    this.existingText,
    this.isCreator = false,
    this.onSelect,
    this.selectIcon,
    this.customHeading,
    this.customMessageBloc,
    this.onMessagesViewComplete,
    this.selected = const [],
    this.type = ChatSelectorTypes.onlyContacts,
  }) : super(key: key);

  final Chat? chat;
  final Function(List<UniqueContact> items)? onSelect;
  final Widget? selectIcon;
  final String? customHeading;
  final String type;
  final bool isCreator;
  final MessageBloc? customMessageBloc;
  final Function? onMessagesViewComplete;

  @override
  ConversationViewState createState() => ConversationViewState();
}

class ConversationViewState extends State<ConversationView> with ConversationViewMixin, WidgetsBindingObserver {
  List<PlatformFile> existingAttachments = [];
  String? existingText;
  Brightness? brightness;
  Color? previousBackgroundColor;
  bool gotBrightness = false;
  Message? message;
  Tween<double> tween = Tween<double>(begin: 1, end: 0);
  double offset = 0;
  CustomAnimationControl controller = CustomAnimationControl.stop;
  bool wasCreator = false;
  bool widgetsBuilt = false;
  GlobalKey key = GlobalKey();
  Worker? worker;
  final RxBool adjustBackground = RxBool(false);
  final FocusNode chatSelectorNode = FocusNode();
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    getAdjustBackground();

    selected = widget.selected.isEmpty ? [] : widget.selected;
    existingAttachments = widget.existingAttachments.isEmpty ? [] : widget.existingAttachments;
    existingText = widget.existingText;

    // Initialize the current chat state
    if (widget.chat != null) {
      initCurrentChat(widget.chat!);
    }

    isCreator = widget.isCreator;
    chat = widget.chat;

    if (chat != null) {
      prefs.setString('lastOpenedChat', chat!.guid!);
    }

    if (widget.selected.isEmpty) {
      initChatSelector();
    }
    initConversationViewState();

    LifeCycleManager().stream.listen((event) {
      if (!mounted) return;
      currentChat?.isAlive = true;
    });

    ever(ChatBloc().chats, (List<Chat> chats) async {
      currentChat ??= CurrentChat.getCurrentChat(widget.chat);

      if (currentChat != null) {
        Chat? _chat = chats.firstWhereOrNull((e) => e.guid == widget.chat?.guid);
        if (_chat != null) {
          _chat.getParticipants();
          currentChat!.chat = _chat;
          if (mounted) setState(() {});
        }
      }
    });

    KeyboardVisibilityController().onChange.listen((bool visible) async {
      await Future.delayed(Duration(milliseconds: 500));
      final textFieldSize = (key.currentContext?.findRenderObject() as RenderBox?)?.size.height;
      if (mounted) {
        setState(() {
          offset = (textFieldSize ?? 0) > 300 ? 300 : 0;
        });
      }
    });

    // Set the custom message bloc if provided (and there is not already an existing one)
    if (widget.customMessageBloc != null && messageBloc == null) {
      messageBloc = widget.customMessageBloc;
    } else if (widget.chat != null && messageBloc == null) {
      messageBloc = MessageBloc(widget.chat);
    }

    initListener();

    SchedulerBinding.instance!.addPostFrameCallback((_) async {
      if (widget.isCreator && (await SettingsManager().getMacOSVersion())! >= 11) {
        showSnackbar('Warning',
            'Support for creating chats is currently limited on MacOS 11 (Big Sur) and up due to limitations imposed by Apple');
      }
    });

    // Bind the lifecycle events
    WidgetsBinding.instance!.addObserver(this);
  }

  void getAdjustBackground() {
    var lightTheme = ThemeObject.getLightTheme();
    var darkTheme = ThemeObject.getDarkTheme();
    if ((lightTheme.gradientBg && !ThemeObject.inDarkMode(Get.context!)) ||
        (darkTheme.gradientBg && ThemeObject.inDarkMode(Get.context!))) {
      adjustBackground.value = true;
    } else {
      adjustBackground.value = false;
    }
  }

  void initListener() {
    if (messageBloc != null) {
      worker = ever<MessageBlocEvent?>(messageBloc!.event, (event) async {
        // Get outta here if we don't have a chat "open"
        if (currentChat == null) return;
        if (event == null) return;

        // Skip deleted messages
        if (event.message != null && event.message!.dateDeleted != null) return;

        if (event.type == MessageBlocEventType.insert && mounted && event.outGoing) {
          final constraints = BoxConstraints(
            maxWidth: CustomNavigator.width(context) * MessageWidgetMixin.maxSize,
            minHeight: Theme.of(context).textTheme.bodyText2!.fontSize!,
            maxHeight: Theme.of(context).textTheme.bodyText2!.fontSize!,
          );
          final renderParagraph = RichText(
            text: TextSpan(
              text: event.message!.text,
              style: Theme.of(context).textTheme.bodyText2!.apply(color: Colors.white),
            ),
            maxLines: 1,
          ).createRenderObject(context);
          final size = renderParagraph.getDryLayout(constraints);
          if (!(event.message?.hasAttachments ?? false) && !(event.message?.text?.isEmpty ?? false)) {
            setState(() {
              tween = Tween<double>(
                  begin: CustomNavigator.width(context) - 30,
                  end: min(size.width + 68, CustomNavigator.width(context) * MessageWidgetMixin.maxSize + 40));
              controller = CustomAnimationControl.play;
              message = event.message;
            });
          } else {
            setState(() {
              isCreator = false;
              wasCreator = true;
              existingText = "";
              existingAttachments = [];
            });
          }
        }
      });
    }
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    getAdjustBackground();
  }

  /// Called when the app is either closed or opened or paused
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted) {
      Logger.info("Removing CurrentChat imageData");
    }
    if (widgetsBuilt) didChangeDependenciesConversationView();
  }

  @override
  void dispose() {
    if (currentChat != null) {
      currentChat!.disposeControllers();
      currentChat!.dispose();
    }

    // Switching chat to null will clear the currently active chat
    NotificationManager().switchChat(null);
    super.dispose();
  }

  Future<bool> send(List<PlatformFile> attachments, String text) async {
    bool isDifferentChat = currentChat == null || currentChat?.chat.guid != chat?.guid;

    if (isCreator!) {
      if (chat == null && selected.length == 1) {
        try {
          if (kIsWeb) {
            chat = await Chat.findOneWeb(chatIdentifier: slugify(selected[0].address!, delimiter: ''));
          } else {
            chat = Chat.findOne(chatIdentifier: slugify(selected[0].address!, delimiter: ''));
          }
        } catch (_) {}
      }

      // If the chat is null, create it
      chat ??= await createChat();

      // If the chat is still null, return false
      if (chat == null) return false;

      prefs.setString('lastOpenedChat', chat!.guid!);

      // If the current chat is null, set it
      if (isDifferentChat) {
        initCurrentChat(chat!);
      }
      if (worker == null) {
        initListener();
      }
    } else {
      if (isDifferentChat) {
        initCurrentChat(chat!);
      }
    }

    ActionHandler.sendMessage(chat!, text);

    return true;
  }

  Widget buildFAB() {
    if (widget.onSelect != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 55.0),
        child: FloatingActionButton(
          onPressed: () => widget.onSelect!(selected),
          child: widget.selectIcon ??
              Icon(
                Icons.check,
                color: Theme.of(context).textTheme.bodyText1!.color,
              ),
          backgroundColor: Theme.of(context).primaryColor,
        ),
      );
    }

    return Container();
  }

  @override
  Widget build(BuildContext context) {
    Future.delayed(Duration.zero, () {
      widgetsBuilt = true;
    });
    currentChat?.isAlive = true;

    if (messageBloc == null && !widget.isCreator) {
      messageBloc = initMessageBloc();
      messageBloc!.getMessages();
    }

    final Widget child = Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (isCreator!)
          ChatSelectorTextField(
            controller: chatSelectorController,
            onRemove: (UniqueContact item) {
              if (item.isChat) {
                selected.removeWhere((e) => (e.chat?.guid) == item.chat!.guid);
              } else {
                selected.removeWhere((e) => e.address == item.address);
              }
              fetchCurrentChat();
              filterContacts();
              resetCursor();
              if (mounted) setState(() {});
            },
            onSelected: onSelected,
            isCreator: widget.isCreator,
            allContacts: contacts,
            selectedContacts: selected,
            inputFieldNode: chatSelectorNode,
          ),
        Obx(() {
          if (!ChatBloc().hasChats.value) {
            return Center(
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        "Loading existing chats...",
                        style: Theme.of(context).textTheme.subtitle1,
                      ),
                    ),
                    buildProgressIndicator(context, size: 15),
                  ],
                ),
              ),
            );
          } else {
            return SizedBox.shrink();
          }
        }),
        Expanded(
          child: Obx(() => fetchingCurrentChat.value
                ? Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 20.0),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              "Loading chat...",
                              style: Theme.of(context).textTheme.subtitle1,
                            ),
                          ),
                          buildProgressIndicator(context, size: 15),
                        ],
                      ),
                    ),
                  )
                : (searchQuery.isEmpty || !isCreator!) && chat != null
                    ? MessagesView(
                      key: Key(chat?.guid ?? "unknown-chat"),
                      messageBloc: messageBloc,
                      showHandle: chat!.participants.length > 1,
                      chat: chat,
                      initComplete: widget.onMessagesViewComplete,
                      node: focusNode,
                      send: send,
                    )
                    : buildChatSelectorBody(),
          ),
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
        backgroundColor: Theme.of(context).backgroundColor,
        extendBodyBehindAppBar: !isCreator!,
        appBar: !isCreator!
            ? null
            : buildChatSelectorHeader() as PreferredSizeWidget?,
        body: Obx(() => adjustBackground.value
            ? MirrorAnimation<MultiTweenValues<String>>(
                tween: ConversationViewMixin.gradientTween.value,
                curve: Curves.fastOutSlowIn,
                duration: Duration(seconds: 3),
                builder: (context, child, anim) {
                  return Container(
                    decoration: (searchQuery.isEmpty || !isCreator!) && chat != null && adjustBackground.value
                        ? BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, stops: [
                            anim.get("color1"),
                            anim.get("color2")
                          ], colors: [
                            AdaptiveTheme.of(context).mode == AdaptiveThemeMode.light
                                ? Theme.of(context).primaryColor.lightenPercent(20)
                                : Theme.of(context).primaryColor.darkenPercent(20),
                            Theme.of(context).backgroundColor
                          ]))
                        : null,
                    child: child,
                  );
                },
                child: child,
              )
            : child),
        floatingActionButton: AnimatedOpacity(
            duration: Duration(milliseconds: 250), opacity: 1, curve: Curves.easeInOut, child: buildFAB()),
      ),
    );
  }
}
