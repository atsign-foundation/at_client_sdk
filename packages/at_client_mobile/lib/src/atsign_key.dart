///Save atsign key
/// https://docs.google.com/document/d/1JAXNrGr6J30m1xTWD4t7z2eQRo6O7icEOprJh1KKNas/edit?hl=en&forcehl=1#
class AtsignKey {
  final String atSign;
  final String? pkamPublicKey;
  final String? pkamPrivateKey;
  final String? encryptionPublicKey;
  final String? encryptionPrivateKey;
  final String? selfEncryptionKey;
  final String? apkamSymmetricKey;
  final String? enrollmentId;
  final String? hiveSecret;
  final String? secret;

  AtsignKey({
    required this.atSign,
    this.pkamPrivateKey,
    this.pkamPublicKey,
    this.encryptionPublicKey,
    this.encryptionPrivateKey,
    this.selfEncryptionKey,
    this.apkamSymmetricKey,
    this.enrollmentId,
    this.hiveSecret,
    this.secret,
  });

  factory AtsignKey.fromJson(Map<String, dynamic> json) => AtsignKey(
        atSign: json["name"] is String ? json["name"] : "",
        pkamPrivateKey:
            json["pkamPrivateKey"] is String ? json["pkamPrivateKey"] : null,
        pkamPublicKey:
            json["pkamPublicKey"] is String ? json["pkamPublicKey"] : null,
        encryptionPublicKey: json["encryptionPublicKey"] is String
            ? json["encryptionPublicKey"]
            : null,
        encryptionPrivateKey: json["encryptionPrivateKey"] is String
            ? json["encryptionPrivateKey"]
            : null,
        selfEncryptionKey: json["selfEncryptionKey"] is String
            ? json["selfEncryptionKey"]
            : null,
        apkamSymmetricKey: json["apkamSymmetricKey"] is String
            ? json["apkamSymmetricKey"]
            : null,
        enrollmentId:
            json["enrollmentId"] is String ? json["enrollmentId"] : null,
        hiveSecret: json["hiveSecret"] is String ? json["hiveSecret"] : null,
        secret: json["secret"] is String ? json["secret"] : null,
      );

  Map<String, dynamic> toJson() => {
        "name": atSign,
        "pkamPrivateKey": pkamPrivateKey,
        "pkamPublicKey": pkamPublicKey,
        "encryptionPublicKey": encryptionPublicKey,
        "encryptionPrivateKey": encryptionPrivateKey,
        "selfEncryptionKey": selfEncryptionKey,
        "apkamSymmetricKey": apkamSymmetricKey,
        "enrollmentId": enrollmentId,
        "hiveSecret": hiveSecret,
        "secret": secret,
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
      pkamPublicKey: pkamPublicKey ?? this.pkamPublicKey,
      pkamPrivateKey: pkamPrivateKey ?? this.pkamPrivateKey,
      encryptionPublicKey: encryptionPublicKey ?? this.encryptionPublicKey,
      encryptionPrivateKey: encryptionPrivateKey ?? this.encryptionPrivateKey,
      selfEncryptionKey: selfEncryptionKey ?? this.selfEncryptionKey,
      apkamSymmetricKey: apkamSymmetricKey ?? this.apkamSymmetricKey,
      enrollmentId: enrollmentId ?? this.enrollmentId,
      hiveSecret: hiveSecret ?? this.hiveSecret,
      secret: secret ?? this.secret,
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

  factory AtClientDataConfig.fromJson(Map<String, dynamic> json) =>
      AtClientDataConfig(
        schemaVersion:
            json['schemaVersion'] is int ? json['schemaVersion'] : null,
        useSharedStorage:
            json['useSharedAtsign'] is bool ? json['useSharedAtsign'] : null,
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
