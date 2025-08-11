import 'dart:convert';
import 'package:at_contact/at_contact.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

/// Model containing all the information needed for location sharing.
class LocationNotificationModel {
  /// [atsignCreator] who shares their location, [receiver] who receives the location.
  String? atsignCreator, receiver, key;

  /// [lat],[long] co-ordinates being shared.
  double? lat, long;

  /// [isAccepted] if this notification is accepted,
  /// [isSharing] if currently sharing for this notification,
  /// [isExited] if this notification is exited,
  /// [isAcknowledgment] if this is an acknowledgment for any notification,
  /// [isRequest] if this notification is a request location notification.
  /// [rePrompt] if this notification need to prompt the receiver again
  bool isAccepted,
      isSharing,
      isExited,
      isAcknowledgment,
      isRequest,
      updateMap,
      rePrompt;

  /// start sharing location [from],
  /// stop sharing location [to].
  DateTime? from, to;
  AtContact? atContact;
  LocationNotificationModel({
    this.key,
    this.lat,
    this.long,
    this.atsignCreator,
    this.receiver,
    this.from,
    this.to,
    this.isRequest = false,
    this.isAcknowledgment = false,
    this.isAccepted = false,
    this.isExited = false,
    this.isSharing = true,
    this.updateMap = false,
    this.rePrompt = false,
  });

  // ignore: always_declare_return_types
  getAtContact() {
    atContact = AtContact(atSign: receiver);
  }

  LatLng get getLatLng => LatLng(lat!, long!);
  LocationNotificationModel.fromJson(Map<String, dynamic> json)
      : atsignCreator = json['atsignCreator'],
        receiver = json['receiver'],
        lat = json['lat'] != 'null' && json['lat'] != null
            ? double.parse(json['lat'])
            : 0,
        long = json['long'] != 'null' && json['long'] != null
            ? double.parse(json['long'])
            : 0,
        key = json['key'] ?? '',
        isAcknowledgment = json['isAcknowledgment'] == 'true' ? true : false,
        isAccepted = json['isAccepted'] == 'true' ? true : false,
        isExited = json['isExited'] == 'true' ? true : false,
        isRequest = json['isRequest'] == 'true' ? true : false,
        isSharing = json['isSharing'] == 'true' ? true : false,
        from = ((json['from'] != 'null') && (json['from'] != null))
            ? DateTime.parse(json['from']).toLocal()
            : null,
        to = ((json['to'] != 'null') && (json['to'] != null))
            ? DateTime.parse(json['to']).toLocal()
            : null,
        rePrompt = json['rePrompt'] == 'true' ? true : false,
        updateMap = json['updateMap'] == 'true' ? true : false;
  Map<String, dynamic> toJson() => {
        'lat': lat,
        'long': long,
        'isAccepted': isAccepted,
        'atsignCreator': atsignCreator,
        'isExited': isExited,
        'isSharing': isSharing
      };
  static String convertLocationNotificationToJson(
      LocationNotificationModel locationNotificationModel) {
    var notification = json.encode({
      'atsignCreator': locationNotificationModel.atsignCreator,
      'receiver': locationNotificationModel.receiver,
      'lat': locationNotificationModel.lat.toString(),
      'long': locationNotificationModel.long.toString(),
      'key': locationNotificationModel.key.toString(),
      'from': locationNotificationModel.from != null
          ? locationNotificationModel.from!.toUtc().toString()
          : null.toString(),
      'to': locationNotificationModel.to != null
          ? locationNotificationModel.to!.toUtc().toString()
          : null.toString(),
      'isAcknowledgment': locationNotificationModel.isAcknowledgment.toString(),
      'isRequest': locationNotificationModel.isRequest.toString(),
      'isAccepted': locationNotificationModel.isAccepted.toString(),
      'isExited': locationNotificationModel.isExited.toString(),
      'updateMap': locationNotificationModel.updateMap.toString(),
      'rePrompt': locationNotificationModel.rePrompt.toString(),
      'isSharing': locationNotificationModel.isSharing.toString()
    });
    return notification;
  }
}

class LocationInfo {
  late bool isAccepted, isSharing, isExited;

  LocationInfo({
    required this.isSharing,
    required this.isExited,
    required this.isAccepted,
  });
}
