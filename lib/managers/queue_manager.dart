import 'package:bluebubbles_wearos/helpers/logger.dart';

class QueueItem {
  String event;
  dynamic item;

  QueueItem({required this.event, this.item});
}

abstract class QueueManager {
  bool isProcessing = false;
  List<QueueItem> queue = [];

  /// Adds an item to the queue and kicks off the processing (if required)
  Future<void> add(QueueItem item) async {
    // Add the item to the queue, no matter what
    queue.add(item);

    // Only process this item if we aren't currently processing
    if (!isProcessing) processNextItem();
  }

  /// Processes the next item in the queue
  Future<void> processNextItem() async {
    // If there are no queued items, we are done processing
    if (queue.isEmpty) {
      isProcessing = false;
      //MethodChannelInterface().closeThread();
      return;
    }

    // Start processing top item
    isProcessing = true;
    QueueItem queued = queue.removeAt(0);

    try {
      await beforeProcessing(queued, {});
      await handleQueueItem(queued);
      await afterProcessing(queued, {});
    } catch (ex, stacktrace) {
      Logger.error("Failed to handle queued item! " + ex.toString());
      Logger.error(stacktrace.toString());
    }

    // Process the next item
    await processNextItem();
  }

  /// Performs pre-processing before the [item] is handled by the implementer.
  /// You can pass any number of [params] using the second Map parameter
  Future<void> beforeProcessing(QueueItem item, Map params) async {
    /* Do Nothing */
  }

  /// Handles the currently passed [item] from the queue
  Future<void> handleQueueItem(QueueItem item);

  /// Performs post-processing before the [item] is handled by the implementer.
  /// You can pass any number of [params] using the second Map parameter
  Future<void> afterProcessing(QueueItem item, Map params) async {
    /* Do Nothing */
  }
}
