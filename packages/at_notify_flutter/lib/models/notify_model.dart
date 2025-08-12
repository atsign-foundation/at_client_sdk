// ignore_for_file: avoid_renaming_method_parameters

import 'dart:convert';

class Notify {
  int? time;
  String? atSign;
  String? message;

  Notify({
    this.time,
    this.atSign,
    this.message,
  });

  Notify copyWith({int? time, String? atSign, String? message}) {
    return Notify(
        time: time ?? this.time,
        atSign: atSign ?? this.atSign,
        message: message ?? this.message);
  }

  factory Notify.fromMap(Map<String, dynamic>? map) {
    if (map == null) return Notify();

    return Notify(
        time: map['time'], atSign: map['atSign'], message: map['message']);
  }

  Map<String, dynamic> toMap() {
    return {
      'time': time,
      'atSign': atSign,
      'message': message,
    };
  }

  String toJson() => json.encode(toMap());

  factory Notify.fromJson(String source) => Notify.fromMap(json.decode(source));

  @override
  String toString() =>
      'Notify(time: $time, atSign: $atSign, message: $message)';

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is Notify &&
        o.time == time &&
        o.atSign == atSign &&
        o.message == message;
  }

  @override
  int get hashCode => time.hashCode ^ atSign.hashCode ^ message.hashCode;
}
