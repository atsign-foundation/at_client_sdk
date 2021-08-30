class AtNotification {
  late String id;
  late String key;
  late String from;
  late String to;
  late int epochMillis;
  String? value;
  String? operation;

  AtNotification(this.id, this.key, this.from, this.to, this.epochMillis,
      {this.value, this.operation});

  factory AtNotification.fromJson(Map<String, dynamic> json) {
    return AtNotification(
        json['id'], json['key'], json['from'], json['to'], json['epochMillis'],
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
      'operation': operation
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
    return 'AtNotification{id: $id, key: $key, from: $from, to: $to, epochMillis: $epochMillis, value: $value, operation: $operation}';
  }
}
