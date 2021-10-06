import 'package:bluebubbles_wearos/repository/models/models.dart';

enum Indicator { READ, DELIVERED, SENT, NONE }

Indicator shouldShow(
    Message? latestMessage, Message? myLastMessage, Message? lastReadMessage, Message? lastDeliveredMessage) {
  if (!(latestMessage?.isFromMe ?? false)) return Indicator.NONE;
  if (latestMessage?.dateRead != null) return Indicator.READ;
  if (latestMessage?.dateDelivered != null) return Indicator.DELIVERED;
  if (latestMessage?.dateCreated != null) return Indicator.SENT;

  return Indicator.NONE;
}
