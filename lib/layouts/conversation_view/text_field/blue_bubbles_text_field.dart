import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bluebubbles_wearos/blocs/text_field_bloc.dart';
import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/helpers/share.dart';
import 'package:bluebubbles_wearos/helpers/utils.dart';
import 'package:bluebubbles_wearos/layouts/widgets/custom_cupertino_text_field.dart';
import 'package:bluebubbles_wearos/layouts/widgets/message_widget/message_content/media_players/audio_player_widget.dart';
import 'package:bluebubbles_wearos/managers/contact_manager.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:bluebubbles_wearos/managers/event_dispatcher.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:bluebubbles_wearos/repository/models/models.dart';
import 'package:bluebubbles_wearos/repository/models/platform_file.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';
import 'package:dio_http/dio_http.dart';
import 'package:file_picker/file_picker.dart' as pf;
import 'package:file_picker/file_picker.dart' hide PlatformFile;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:record/record.dart';
import 'package:transparent_pointer/transparent_pointer.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';

class BlueBubblesTextField extends StatefulWidget {
  final List<PlatformFile>? existingAttachments;
  final String? existingText;
  final bool? isCreator;
  final bool wasCreator;
  final Future<bool> Function(List<PlatformFile> attachments, String text) onSend;

  BlueBubblesTextField({
    Key? key,
    this.existingAttachments,
    this.existingText,
    required this.isCreator,
    required this.wasCreator,
    required this.onSend,
  }) : super(key: key);

  static BlueBubblesTextFieldState? of(BuildContext context) {
    return context.findAncestorStateOfType<BlueBubblesTextFieldState>();
  }

  @override
  BlueBubblesTextFieldState createState() => BlueBubblesTextFieldState();
}

class BlueBubblesTextFieldState extends State<BlueBubblesTextField> with TickerProviderStateMixin {
  TextEditingController? controller;
  FocusNode? focusNode;
  List<PlatformFile> pickedImages = [];
  TextFieldData? textFieldData;
  final StreamController _streamController = StreamController.broadcast();
  DropzoneViewController? dropZoneController;
  CurrentChat? safeChat;

  bool selfTyping = false;
  int? sendCountdown;
  bool? stopSending;
  bool fileDragged = false;
  int? previousKeyCode;

  final RxString placeholder = "BlueBubbles".obs;
  final RxBool isRecording = false.obs;
  final RxBool canRecord = true.obs;

  // bool selfTyping = false;

  Stream get stream => _streamController.stream;

  bool get _canRecord => controller!.text.isEmpty && pickedImages.isEmpty;

  final RxBool showShareMenu = false.obs;

  final GlobalKey<FormFieldState<String>> _searchFormKey = GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();

    if (CurrentChat.of(context)?.chat != null) {
      textFieldData = TextFieldBloc().getTextField(CurrentChat.of(context)!.chat.guid!);
    }

    controller = textFieldData != null ? textFieldData!.controller : TextEditingController();

    // Add the text listener to detect when we should send the typing indicators
    controller!.addListener(() {
      setCanRecord();
      if (!mounted || CurrentChat.of(context)?.chat == null) return;


      if (controller!.text.isEmpty && pickedImages.isEmpty && selfTyping) {
        selfTyping = false;
        SocketManager().sendMessage("stopped-typing", {"chatGuid": CurrentChat.of(context)!.chat.guid}, (data) {});
      } else if (!selfTyping && (controller!.text.isNotEmpty || pickedImages.isNotEmpty)) {
        selfTyping = true;
      }

      if (mounted) setState(() {});
    });

    // Create the focus node and then add a an event emitter whenever
    // the focus changes
    focusNode = FocusNode();
    focusNode!.addListener(() {
      CurrentChat.of(context)?.keyboardOpen = focusNode?.hasFocus ?? false;

      if (focusNode!.hasFocus && mounted) {
        if (!showShareMenu.value) return;
        showShareMenu.value = false;
      }

      EventDispatcher().emit("keyboard-status", focusNode!.hasFocus);
    });

    if (kIsWeb) {
      html.document.onDragOver.listen((event) {
        var t = event.dataTransfer;
        if (t.types != null && t.types!.length == 1 && t.types!.first == "Files" && fileDragged == false) {
          setState(() {
            fileDragged = true;
          });
        }
      });

      html.document.onDragLeave.listen((event) {
        if (fileDragged == true) {
          setState(() {
            fileDragged = false;
          });
        }
      });
    }

    EventDispatcher().stream.listen((event) {
      if (!event.containsKey("type")) return;
      if (event["type"] == "unfocus-keyboard" && focusNode!.hasFocus) {
        Logger.info("(EVENT) Unfocus Keyboard");
        focusNode!.unfocus();
      } else if (event["type"] == "focus-keyboard" && !focusNode!.hasFocus) {
        Logger.info("(EVENT) Focus Keyboard");
        focusNode!.requestFocus();
      } else if (event["type"] == "text-field-update-attachments") {
        addSharedAttachments();
        while (!(ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop();
        }
      } else if (event["type"] == "text-field-update-text") {
        while (!(ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop();
        }
      }
    });

    if (widget.existingText != null) {
      controller!.text = widget.existingText!;
    }

    if (widget.existingAttachments != null) {
      addAttachments(widget.existingAttachments ?? []);
      updateTextFieldAttachments();
    }

    if (textFieldData != null) {
      addAttachments(textFieldData?.attachments ?? []);
    }

    setCanRecord();
  }

  void setCanRecord() {
    bool canRec = _canRecord;
    if (canRec != canRecord.value) {
      canRecord.value = canRec;
    }
  }

  void addAttachments(List<PlatformFile> attachments) {
    pickedImages.addAll(attachments);
    if (!kIsWeb) pickedImages = pickedImages.toSet().toList();
    setCanRecord();
  }

  void updateTextFieldAttachments() {
    if (textFieldData != null) {
      textFieldData!.attachments = List<PlatformFile>.from(pickedImages);
      _streamController.sink.add(null);
    }

    setCanRecord();
  }

  void addSharedAttachments() {
    if (textFieldData != null && mounted) {
      pickedImages = textFieldData!.attachments;
      setState(() {});
    }

    setCanRecord();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    safeChat = CurrentChat.of(context);
  }

  @override
  void dispose() {
    focusNode!.dispose();
    _streamController.close();

    if (safeChat?.chat == null) controller!.dispose();

    if (!kIsWeb) {
      String dir = SettingsManager().appDocDir.path;
      Directory tempAssets = Directory("$dir/tempAssets");
      tempAssets.exists().then((value) {
        if (value) {
          tempAssets.delete(recursive: true);
        }
      });
    }
    pickedImages = [];
    super.dispose();
  }

  void disposeAudioFile(BuildContext context, PlatformFile file) {
    // Dispose of the audio controller
    CurrentChat.of(context)?.audioPlayers[file.path]?.item1.dispose();
    CurrentChat.of(context)?.audioPlayers[file.path]?.item2.pause();
    CurrentChat.of(context)?.audioPlayers.removeWhere((key, _) => key == file.path);
    if (file.path != null) {
      // Delete the file
      File(file.path!).delete();
    }
  }

  void onContentCommit(dynamic content) async {
    // Add some debugging logs
    Logger.info("[Content Commit] Keyboard received content");
    Logger.info("  -> Content Type: ${content.mimeType}");
    Logger.info("  -> URI: ${content.uri}");
    Logger.info("  -> Content Length: ${content.hasData ? content.data!.length : "null"}");

    // Parse the filename from the URI and read the data as a List<int>
    String filename = uriToFilename(content.uri, content.mimeType);

    // Save the data to a location and add it to the file picker
    if (content.hasData) {
      addAttachments([PlatformFile(
        name: filename,
        size: content.data!.length,
        bytes: content.data,
      )]);

      // Update the state
      updateTextFieldAttachments();
      if (mounted) setState(() {});
    } else {
      showSnackbar('Insertion Failed', 'Attachment has no data!');
    }
  }

  Future<void> reviewAudio(BuildContext originalContext, PlatformFile file) async {
    showDialog(
      context: originalContext,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).accentColor,
          title: Text("Send it?", style: Theme.of(context).textTheme.headline1),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Review your audio snippet before sending it", style: Theme.of(context).textTheme.subtitle1),
              Container(height: 10.0),
              AudioPlayerWiget(
                key: Key("AudioMessage-${file.size}"),
                file: file,
                context: originalContext,
              )
            ],
          ),
          actions: <Widget>[
            TextButton(
                child: Text("Discard", style: Theme.of(context).textTheme.subtitle1),
                onPressed: () {
                  // Dispose of the audio controller
                  if (!kIsWeb) disposeAudioFile(originalContext, file);

                  // Remove the OG alert dialog
                  Get.back();
                }),
            TextButton(
              child: Text(
                "Send",
                style: Theme.of(context).textTheme.bodyText1,
              ),
              onPressed: () async {
                CurrentChat? thisChat = CurrentChat.of(originalContext);
                if (thisChat == null) {
                  addAttachments([file]);
                } else {
                  await widget.onSend([file], "");
                  if (!kIsWeb) disposeAudioFile(originalContext, file);
                }

                // Remove the OG alert dialog
                Get.back();
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    if (showShareMenu.value) {
      if (mounted) {
        showShareMenu.value = false;
      }
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.only(left: 5, top: 5, bottom: 5, right: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    buildTextFieldAlwaysVisible(),
                  ],
                ),
              ),
            ),
          ],
        ));
  }

  Widget buildTextFieldAlwaysVisible() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        buildShareButton(),
        buildActualTextField(),
      ],
    );
  }

  Widget buildShareButton() {
    double size = 40;
    return AnimatedSize(
      vsync: this,
      duration: Duration(milliseconds: 300),
      child: Container(
        height: size,
        width: fileDragged ? size * 3 : size,
        margin: EdgeInsets.only(left: 5.0, right: 5.0),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: BorderRadius.circular(fileDragged ? 5 : 40),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            TransparentPointer(
              child: ClipRRect(
                child: InkWell(
                  onTap: () {},
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: 1,
                        left: 0),
                    child: fileDragged
                        ? Center(child: Text("Drop file here"))
                        : Icon(
                            Icons.share,
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
    );
  }

  Widget buildActualTextField() {
    return Flexible(
      flex: 1,
      fit: FlexFit.loose,
      child: Container(
        child: Stack(
          alignment: AlignmentDirectional.centerEnd,
          children: <Widget>[
            AnimatedSize(
              vsync: this,
              duration: Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              child: CustomCupertinoTextField(
                enabled: sendCountdown == null,
                textInputAction: TextInputAction.newline,
                cursorColor: Theme.of(context).primaryColor,
                onLongPressStart: () {
                  Feedback.forLongPress(context);
                },
                onTap: () {
                  HapticFeedback.selectionClick();
                },
                key: _searchFormKey,
                onSubmitted: (String value) {
                  if (isNullOrEmpty(value)! && pickedImages.isEmpty) return;
                  focusNode!.requestFocus();
                  sendMessage();
                },
                //onContentCommitted: onContentCommit,
                textCapitalization: TextCapitalization.sentences,
                focusNode: focusNode,
                autocorrect: true,
                controller: controller,
                style: Theme.of(context).textTheme.bodyText1!.apply(
                  color: ThemeData.estimateBrightnessForColor(Theme.of(context).backgroundColor) ==
                      Brightness.light
                      ? Colors.black
                      : Colors.white,
                  fontSizeDelta: -0.25,
                ),
                keyboardType: TextInputType.multiline,
                maxLines: 14,
                minLines: 1,
                placeholder: "BlueBubbles",
                padding: EdgeInsets.only(left: 10, top: 10, right: 40, bottom: 10),
                placeholderStyle: Theme.of(context).textTheme.subtitle1,
                decoration: BoxDecoration(
                  color: Theme.of(context).backgroundColor,
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            buildSendButton(),
          ],
        ),
      ),
    );
  }

  Future<void> startRecording() async {
    HapticFeedback.lightImpact();
    String? pathName;
    if (!kIsWeb) {
      String appDocPath = SettingsManager().appDocDir.path;
      Directory directory = Directory("$appDocPath/attachments/");
      if (!await directory.exists()) {
        directory.createSync();
      }
      pathName = "$appDocPath/attachments/OutgoingAudioMessage.m4a";
      File file = File(pathName);
      if (file.existsSync()) file.deleteSync();
    }

    if (!isRecording.value) {
      await Record().start(
        path: pathName, // required
        encoder: AudioEncoder.AAC, // by default
        bitRate: 196000, // by default
        samplingRate: 44100, // by default
      );

      if (mounted) {
        isRecording.value = true;
      }
    }
  }

  Future<void> stopRecording() async {
    HapticFeedback.lightImpact();

    if (isRecording.value) {
      String? pathName = await Record().stop();

      if (mounted) {
        isRecording.value = false;
      }

      if (pathName != null) {
        reviewAudio(
            context,
            PlatformFile(
              name: "${randomString(8)}.m4a",
              path: kIsWeb ? null : pathName,
              size: 0,
              bytes:
                  kIsWeb ? (await Dio().get(pathName, options: Options(responseType: ResponseType.bytes))).data : null,
            ));
      }
    }
  }

  Future<void> sendMessage() async {
    // If send delay is enabled, delay the sending

    if (stopSending != null && stopSending!) {
      stopSending = null;
      return;
    }

    if (await widget.onSend(pickedImages, controller!.text)) {
      controller!.text = "";
      pickedImages.clear();
      updateTextFieldAttachments();
    }
  }

  Future<void> sendAction() async {
    bool shouldUpdate = false;
    if (sendCountdown != null) {
      stopSending = true;
      sendCountdown = null;
      shouldUpdate = true;
    } else if (isRecording.value) {
      await stopRecording();
      shouldUpdate = true;
    } else if (canRecord.value && !isRecording.value && !kIsDesktop && await Record().hasPermission()) {
      await startRecording();
      shouldUpdate = true;
    } else {
      await sendMessage();
    }

    if (shouldUpdate && mounted) setState(() {});
  }

  Widget buildSendButton() => Align(
        alignment: Alignment.bottomRight,
        child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (sendCountdown != null) Text(sendCountdown.toString()),
          Container(
            constraints: BoxConstraints(maxWidth: 35, maxHeight: 34),
            padding: EdgeInsets.only(right: 4, top: 2, bottom: 2),
            child: ButtonTheme(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.only(
                      right: 0,
                    ),
                    primary: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40),
                    ),
                    elevation: 0),
                onPressed: sendAction,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Obx(() => AnimatedOpacity(
                      opacity: sendCountdown == null && canRecord.value && !kIsDesktop ? 1.0 : 0.0,
                      duration: Duration(milliseconds: 150),
                      child: Icon(
                        CupertinoIcons.waveform,
                        color: (isRecording.value) ? Colors.red : Colors.white,
                        size: 22,
                      ),
                    )),
                    Obx(() => AnimatedOpacity(
                      opacity:
                      (sendCountdown == null && (!canRecord.value || kIsDesktop)) && !isRecording.value
                          ? 1.0
                          : 0.0,
                      duration: Duration(milliseconds: 150),
                      child: Icon(
                        CupertinoIcons.arrow_up,
                        color: Colors.white,
                        size: 20,
                      ),
                    )),
                    AnimatedOpacity(
                      opacity: sendCountdown != null ? 1.0 : 0.0,
                      duration: Duration(milliseconds: 50),
                      child: Icon(
                        CupertinoIcons.xmark_circle,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ]),
      );
}
