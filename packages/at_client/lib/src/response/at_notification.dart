import 'package:at_client/at_client.dart';

class AtNotification {
  late String id;
  String key = '';
  String from = '';
  String to = '';
  int epochMillis = 0;
  String status = '';
  String? value;
  String? operation;
  String? messageType;
  bool? isEncrypted;

  /// AtNotification instance is created without initializing the fields
  AtNotification.empty();

  AtNotification(this.id, this.key, this.from, this.to, this.epochMillis,
      this.messageType, this.isEncrypted,
      {this.value, this.operation});

  factory AtNotification.fromJson(Map<String, dynamic> json) {
    return AtNotification(json['id'], json['key'], json['from'], json['to'],
        json['epochMillis'], json['messageType'], json[IS_ENCRYPTED],
        value: json['value'], operation: json['operation']);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'from': from,
      'to': to,
      'epochMillis': epochMillis,
      'value': value,
      'operation': operation,
      'messageType': messageType,
      IS_ENCRYPTED: isEncrypted,
      'notificationStatus': status
    };
  }

  static List<AtNotification> fromJsonList(
      List<Map<String, dynamic>> jsonList) {
    final notificationList = <AtNotification>[];
    for (var json in jsonList) {
      notificationList.add(AtNotification.fromJson(json));
    }
    return notificationList;
  }

  @override
  String toString() {
    return 'AtNotification{id: $id, key: $key, from: $from, to: $to, epochMillis: $epochMillis, value: $value, operation: $operation, status: $status}';
  }
}
