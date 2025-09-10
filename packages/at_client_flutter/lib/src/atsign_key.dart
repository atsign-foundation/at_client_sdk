import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_commons/at_commons.dart';

///Save atsign key
/// https://docs.google.com/document/d/1JAXNrGr6J30m1xTWD4t7z2eQRo6O7icEOprJh1KKNas/edit?hl=en&forcehl=1#
class AtsignKey extends AtKeys {
  final String atSign;
  final String? hiveSecret;
  final String? cramKey;

  AtsignKey({
    required this.atSign,
    this.hiveSecret,
    this.cramKey,
    AtBytes? apkamPublicKey,
    AtBytes? apkamPrivateKey,
    AtBytes? defaultEncryptionPublicKey,
    AtBytes? defaultEncryptionPrivateKey,
    AtBytes? defaultSelfEncryptionKey,
    AtBytes? apkamSymmetricKey,
    String? enrollmentId,
  }) : super() {
    this.apkamPrivateKey = apkamPrivateKey;
    this.apkamPublicKey = apkamPublicKey;
    this.defaultEncryptionPublicKey = defaultEncryptionPublicKey;
    this.defaultEncryptionPrivateKey = defaultEncryptionPrivateKey;
    this.defaultSelfEncryptionKey = defaultSelfEncryptionKey;
    this.apkamSymmetricKey = apkamSymmetricKey;
    this.enrollmentId = enrollmentId;
  }

  factory AtsignKey.fromJson(Map<String, dynamic> json) => AtsignKey(
        atSign: json["name"] is String ? json["name"] : '',
        apkamPrivateKey: json["pkamPrivateKey"] is String ? AtBytes(json["pkamPrivateKey"]) : null,
        apkamPublicKey: json["pkamPublicKey"] is String ? AtBytes(json["pkamPublicKey"]) : null,
        defaultEncryptionPublicKey: json["encryptionPublicKey"] is String ? AtBytes(json["encryptionPublicKey"]) : null,
        defaultEncryptionPrivateKey:
            json["encryptionPrivateKey"] is String ? AtBytes(json["encryptionPrivateKey"]) : null,
        defaultSelfEncryptionKey: json["selfEncryptionKey"] is String ? AtBytes(json["selfEncryptionKey"]) : null,
        apkamSymmetricKey: json["apkamSymmetricKey"] is String ? AtBytes(json["apkamSymmetricKey"]) : null,
        enrollmentId: json["enrollmentId"] is String ? json["enrollmentId"] : null,
        hiveSecret: json["hiveSecret"] is String ? json["hiveSecret"] : null,
        cramKey: json["secret"] is String ? json["secret"] : null,
      );

  @override
  Map<String, dynamic> toJson() => {
        "name": atSign,
        "pkamPrivateKey": apkamPrivateKey.toString(),
        "pkamPublicKey": apkamPublicKey.toString(),
        "encryptionPublicKey": defaultEncryptionPublicKey.toString(),
        "encryptionPrivateKey": defaultEncryptionPrivateKey.toString(),
        "selfEncryptionKey": defaultSelfEncryptionKey.toString(),
        "apkamSymmetricKey": apkamSymmetricKey.toString(),
        "enrollmentId": enrollmentId,
        "hiveSecret": hiveSecret,
        "secret": cramKey,
      };

  AtsignKey copyWith({
    String? name,
    String? pkamPublicKey,
    String? pkamPrivateKey,
    String? encryptionPublicKey,
    String? encryptionPrivateKey,
    String? selfEncryptionKey,
    String? apkamSymmetricKey,
    String? enrollmentId,
    String? hiveSecret,
    String? secret,
  }) {
    return AtsignKey(
      atSign: name ?? atSign,
      apkamPublicKey: pkamPublicKey != null ? AtBytes.fromString(pkamPublicKey) : apkamPublicKey,
      apkamPrivateKey: pkamPrivateKey != null ? AtBytes.fromString(pkamPrivateKey) : apkamPrivateKey,
      defaultEncryptionPublicKey:
          encryptionPublicKey != null ? AtBytes.fromString(encryptionPublicKey) : defaultEncryptionPublicKey,
      defaultEncryptionPrivateKey:
          encryptionPrivateKey != null ? AtBytes.fromString(encryptionPrivateKey) : defaultEncryptionPrivateKey,
      defaultSelfEncryptionKey:
          selfEncryptionKey != null ? AtBytes.fromString(selfEncryptionKey) : defaultSelfEncryptionKey,
      apkamSymmetricKey: apkamSymmetricKey != null ? AtBytes.fromString(apkamSymmetricKey) : this.apkamSymmetricKey,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      hiveSecret: hiveSecret ?? this.hiveSecret,
      cramKey: secret ?? this.cramKey,
    );
  }

  AtsignKey copyWithAtKeys(String atSign, AtKeys atKeys, {String? hiveSecret, String? secret}) {
    return AtsignKey(
      atSign: atSign,
      apkamPublicKey: atKeys.apkamPublicKey,
      apkamPrivateKey: atKeys.apkamPrivateKey,
      defaultEncryptionPublicKey: atKeys.defaultEncryptionPublicKey,
      defaultEncryptionPrivateKey: atKeys.defaultEncryptionPrivateKey,
      defaultSelfEncryptionKey: atKeys.defaultSelfEncryptionKey,
      apkamSymmetricKey: atKeys.apkamSymmetricKey,
      enrollmentId: atKeys.enrollmentId,
      hiveSecret: hiveSecret,
      cramKey: secret,
    );
  }
}

class AtClientData {
  AtClientDataConfig? config;
  List<AtsignKey> keys;
  String? defaultAtsign;

  AtClientData({
    this.config,
    this.keys = const [],
    this.defaultAtsign,
  });

  AtClientData copyWith({
    AtClientDataConfig? config,
    List<AtsignKey>? keys,
    String? defaultAtsign,
  }) {
    return AtClientData(
      config: config ?? this.config,
      keys: keys ?? this.keys,
      defaultAtsign: defaultAtsign ?? this.defaultAtsign,
    );
  }

  factory AtClientData.fromJson(Map<String, dynamic> json) => AtClientData(
        config: json['config'] == null
            ? null
            : AtClientDataConfig.fromJson(
                json['config'] as Map<String, dynamic>),
        keys: (json['keys'] as List<dynamic>?)
                ?.map((e) => AtsignKey.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        defaultAtsign: json['defaultAtsign'],
      );

  Map<String, dynamic> toJson() => {
        'config': config,
        'keys': keys,
        'defaultAtsign': defaultAtsign,
      };
}

class AtClientDataConfig {
  final int? schemaVersion;
  final bool? useSharedStorage; //Share atsign account between apps

  const AtClientDataConfig({
    this.schemaVersion,
    this.useSharedStorage,
  });

  factory AtClientDataConfig.defaultConfig() => AtClientDataConfig();

  factory AtClientDataConfig.fromJson(Map<String, dynamic> json) => AtClientDataConfig(
        schemaVersion: json['schemaVersion'] is int ? json['schemaVersion'] : null,
        useSharedStorage: json['useSharedAtsign'] is bool ? json['useSharedAtsign'] : null,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'useSharedAtsign': useSharedStorage,
      };

  AtClientDataConfig copyWith({
    int? schemaVersion,
    bool? useSharedStorage,
  }) {
    return AtClientDataConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      useSharedStorage: useSharedStorage ?? this.useSharedStorage,
    );
  }
}
