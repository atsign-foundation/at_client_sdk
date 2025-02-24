import 'dart:convert';

import 'package:at_commons/atsign.dart';

const JsonEncoder jsonPrettyPrinter = JsonEncoder.withIndent('    ');

abstract interface class AtServerEvent {
  static const String atProtocolCategory = 'atProtocol';
  static const String atSignPKChangedEventName = 'atsign_pk_changed';

  /// The category of event. Events which are part of the atProtocol will
  /// have a category of 'atProtocol'. Events which are specific to particular
  /// AtServer implementations should have a different category (e.g. the name
  /// of the implementation)
  String get category;

  /// The name of the event
  String get name;

  /// The event's data (JSON map)
  Map<String, dynamic> get data;

  Map<String, dynamic> toJson() => {
    'category': category,
    'name': name,
    'data': data,
  };
}

/// This event is specific to when the 'public:publickey@alice' key changes.
class AtSignPKChangedEvent extends AtServerEvent {
  @override
  final String category = AtServerEvent.atProtocolCategory;

  @override
  final String name = AtServerEvent.atSignPKChangedEventName;

  /// The atSign whose PK has changed
  final Atsign atSign;

  AtSignPKChangedEvent(String atSign) : atSign = atSign.toAtsign();

  @override
  Map<String, dynamic> get data => {
    'atSign': atSign,
  };

  static AtSignPKChangedEvent fromJson(Map<String, dynamic> json) =>
      AtSignPKChangedEvent(json['data']['atSign']);

  @override
  String toString() => jsonPrettyPrinter.convert(toJson());
}
