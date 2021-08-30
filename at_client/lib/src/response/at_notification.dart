
class AtNotification {
  late String notificationId;
  late String key;
  late int epochMillis;
  String? value;

  static AtNotification fromJson(Map json) {
    return AtNotification()
      ..notificationId = json['id']
      ..key = json['key']
      ..epochMillis = json['epochMillis']
      ..value = json['value'];
  }

  Map toJson() {
    final jsonMap = {};
    jsonMap['id'] = notificationId;
    jsonMap['key'] = key;
    jsonMap['epochMillis'] = epochMillis;
    jsonMap['value'] = value;
    return jsonMap;
  }

  @override
  String toString() {
    return 'AtNotification{id: $notificationId, key: $key, epochMillis: $epochMillis, value: $value}';
  }
}