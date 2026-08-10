import 'dart:convert';

import 'package:at_commons/at_commons.dart';

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
  int? expiresAtInEpochMillis;
  Metadata? metadata;

  /// AtNotification instance is created without initializing the fields
  AtNotification.empty();

  AtNotification(this.id, this.key, this.from, this.to, this.epochMillis,
      this.messageType, this.isEncrypted,
      {this.value, this.operation, this.expiresAtInEpochMillis, this.metadata});

  factory AtNotification.fromJson(Map<String, dynamic> json) {
    Metadata? metadata;

    if (json['metadata'] != null) {
      metadata = Metadata();
      metadata.encKeyName = json['metadata'][AtConstants.encryptingKeyName];
      metadata.encAlgo = json['metadata'][AtConstants.encryptingAlgo];
      metadata.ivNonce = json['metadata'][AtConstants.ivOrNonce];
      metadata.skeEncKeyName =
          json['metadata'][AtConstants.sharedKeyEncryptedEncryptingKeyName];
      metadata.skeEncAlgo =
          json['metadata'][AtConstants.sharedKeyEncryptedEncryptingAlgo];
      metadata.sharedKeyEnc = json['metadata'][AtConstants.sharedKeyEncrypted];
      metadata.appMetadata =
          Metadata.decodeAppMetadata(json['metadata'][AtConstants.appMetadata]);
      // A provider decides its wire format from isBinary, so losing it here
      // makes a binary notification decode as text — garbage, or a raw
      // FormatException, rather than the bytes that were sent.
      metadata.isBinary = _asBool(json['metadata'][AtConstants.isBinary]);
      metadata.encoding = json['metadata'][AtConstants.encoding];
      // AtConstants.sharedWithPublicKeyHash will be sent by the server starting v3.0.52
      // Notifications received from Secondary server before 3.0.52 does not contain
      // AtConstants.sharedWithPublicKeyHash. Therefore, check for null.
      if (json['metadata'][AtConstants.sharedWithPublicKeyHash] != null) {
        var publicKeyHash =
            jsonDecode(json['metadata'][AtConstants.sharedWithPublicKeyHash]);
        metadata.pubKeyHash =
            PublicKeyHash(publicKeyHash['hash'], publicKeyHash['hashingAlgo']);
      }
    }

    return AtNotification(json['id'], json['key'], json['from'], json['to'],
        json['epochMillis'], json['messageType'], json[AtConstants.isEncrypted],
        value: json['value'],
        operation: json['operation'],
        expiresAtInEpochMillis: json['expiresAt'],
        metadata: metadata);
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
      AtConstants.isEncrypted: isEncrypted,
      'notificationStatus': status,
      'expiresAt': expiresAtInEpochMillis,
      'metadata': metadata
    };
  }

  /// The atServer sends notification metadata as JSON, but the booleans in it
  /// arrive as real bools from some paths and as `'true'`/`'false'` strings
  /// from others, so accept both rather than silently reading a string as
  /// false.
  static bool _asBool(dynamic value) =>
      value is bool ? value : value.toString().toLowerCase() == 'true';

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
    return toJson().toString();
  }
}
