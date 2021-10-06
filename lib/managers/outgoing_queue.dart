import 'package:bluebubbles_wearos/action_handler.dart';
import 'package:bluebubbles_wearos/helpers/logger.dart';
import 'package:bluebubbles_wearos/managers/queue_manager.dart';
import 'package:bluebubbles_wearos/socket_manager.dart';

class OutgoingQueue extends QueueManager {
  factory OutgoingQueue() {
    return _queue;
  }

  static final OutgoingQueue _queue = OutgoingQueue._internal();

  OutgoingQueue._internal();

  @override
  Future<void> handleQueueItem(QueueItem item) async {
    switch (item.event) {
      case "send-message":
        {
          Map<String, dynamic> params = item.item;
          await ActionHandler.sendMessageHelper(params["chat"], params["message"]);
          break;
        }
      case "send-reaction":
        {
          Map<String, dynamic> params = item.item;
          await ActionHandler.sendReactionHelper(params["chat"], params["message"], params["reaction"]);
          break;
        }
      default:
        {
          Logger.warn("Unhandled queue event: ${item.event}");
        }
    }
  }
}
