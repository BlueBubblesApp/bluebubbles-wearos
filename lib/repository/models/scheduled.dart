import 'package:bluebubbles_wearos/main.dart';
import 'package:bluebubbles_wearos/objectbox.g.dart';
import 'package:flutter/foundation.dart';

@Entity()
class ScheduledMessage {
  int? id;
  String? chatGuid;
  String? message;
  int? epochTime;
  bool? completed;

  ScheduledMessage({this.id, this.chatGuid, this.message, this.epochTime, this.completed});

  factory ScheduledMessage.fromMap(Map<String, dynamic> json) {
    return ScheduledMessage(
        id: json.containsKey("ROWID") ? json["ROWID"] : null,
        chatGuid: json["chatGuid"],
        message: json["message"],
        epochTime: json["epochTime"],
        completed: json["completed"] == 0 ? false : true);
  }

  ScheduledMessage save() {
    if (kIsWeb) return this;
    id = scheduledBox.put(this);
    return this;
  }

  static List<ScheduledMessage> find() {
    if (kIsWeb) return [];
    return scheduledBox.getAll();
  }

  static void flush() {
    if (kIsWeb) return;
    scheduledBox.removeAll();
  }

  Map<String, dynamic> toMap() =>
      {"ROWID": id, "chatGuid": chatGuid, "message": message, "epochTime": epochTime, "completed": completed! ? 1 : 0};
}
