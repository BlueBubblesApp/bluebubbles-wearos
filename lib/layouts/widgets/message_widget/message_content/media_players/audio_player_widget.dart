import 'package:universal_html/html.dart' as html;

import 'package:bluebubbles_wearos/repository/models/platform_file.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

import 'package:bluebubbles_wearos/helpers/constants.dart';
import 'package:bluebubbles_wearos/helpers/navigator.dart';
import 'package:bluebubbles_wearos/managers/settings_manager.dart';
import 'package:chewie_audio/chewie_audio.dart';
import 'package:bluebubbles_wearos/managers/current_chat.dart';
import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';
import 'package:video_player/video_player.dart';

class AudioPlayerWiget extends StatefulWidget {
  AudioPlayerWiget({
    Key? key,
    required this.file,
    required this.context,
    this.isFromMe = false,
    this.width,
  }) : super(key: key);

  final PlatformFile file;
  final BuildContext context;
  final double? width;
  final bool isFromMe;

  @override
  _AudioPlayerWigetState createState() => _AudioPlayerWigetState();
}

class _AudioPlayerWigetState extends State<AudioPlayerWiget> {
  late final ChewieAudioController controller;
  late final VideoPlayerController audioController;

  @override
  void initState() {
    super.initState();

    CurrentChat? thisChat = CurrentChat.of(widget.context);
    if (!kIsWeb && thisChat != null && thisChat.audioPlayers.containsKey(widget.file.path)) {
      audioController = thisChat.audioPlayers[widget.file.path]!.item2;
      controller = thisChat.audioPlayers[widget.file.path]!.item1;
    } else {
      if (kIsWeb || widget.file.path == null) {
        final blob = html.Blob([widget.file.bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        audioController = VideoPlayerController.network(url);
      } else {
        dynamic file = File(widget.file.path!);
        audioController = VideoPlayerController.file(file);
      }
      controller = ChewieAudioController(
        videoPlayerController: audioController,
        autoPlay: false,
        looping: true,
        showSeekButtons: false,
        showControls: true,
        autoInitialize: true,
        materialProgressColors: ChewieProgressColors(
            playedColor: Theme.of(widget.context).primaryColor,
            handleColor: Theme.of(widget.context).primaryColor,
            bufferedColor: Theme.of(widget.context).backgroundColor,
            backgroundColor: Theme.of(widget.context).disabledColor),
        cupertinoProgressColors: ChewieProgressColors(
            playedColor: Theme.of(widget.context).primaryColor,
            handleColor: Theme.of(widget.context).primaryColor,
            bufferedColor: Theme.of(widget.context).backgroundColor,
            backgroundColor: Theme.of(widget.context).disabledColor),
        cupertinoBackgroundColor: Theme.of(widget.context).accentColor,
        cupertinoIconColor: Theme.of(widget.context).textTheme.bodyText1?.color,
        cupertinoColumnAlignment: widget.isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      );

      thisChat = CurrentChat.of(widget.context);
      if (!kIsWeb && thisChat != null && widget.file.path != null) {
        CurrentChat.of(widget.context)!.audioPlayers[widget.file.path!] = Tuple2(controller, audioController);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  String formatDuration(Duration duration) {
    String minutes = duration.inMinutes.toString();
    int sec = (duration.inSeconds - (duration.inMinutes * 60));
    String seconds = sec.isNaN || sec.isNegative ? "0" : sec.toString();
    minutes = (minutes.length == 1) ? "0$minutes" : minutes;
    seconds = (seconds.length == 1) ? "0$seconds" : seconds;
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    double maxWidth = widget.width ?? CustomNavigator.width(context) - 20;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
      controller.pause();
    }
    return Container(
      alignment: Alignment.center,
      color: Theme.of(context).accentColor,
      height: 75,
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Theme(
        data: Theme.of(context).copyWith(
            platform: TargetPlatform.iOS,
            dialogBackgroundColor: Theme.of(context).accentColor,
            iconTheme: Theme.of(context).iconTheme.copyWith(color: Theme.of(context).textTheme.bodyText1?.color)),
        child: ChewieAudio(
          controller: controller,
        ),
      ),
    );
  }
}
