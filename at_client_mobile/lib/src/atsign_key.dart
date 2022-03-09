///Save atsign key
/// https://docs.google.com/document/d/1JAXNrGr6J30m1xTWD4t7z2eQRo6O7icEOprJh1KKNas/edit?hl=en&forcehl=1#
class AtsignKey {
  final bool isDefault;
  final String name;
  final String? pkamPublicKey;
  final String? pkamPrivateKey;
  final String? encryptionPublicKey;
  final String? encryptionPrivateKey;
  final String? selfEncryptionKey;
  final String? hiveSecret;
  final String? secret;

  AtsignKey({
    this.isDefault = false,
    required this.name,
    this.pkamPrivateKey,
    this.pkamPublicKey,
    this.encryptionPublicKey,
    this.encryptionPrivateKey,
    this.selfEncryptionKey,
    this.hiveSecret,
    this.secret,
  });

  factory AtsignKey.fromJson(Map<String, dynamic> json) => AtsignKey(
        isDefault: json["isDefault"] is bool ? json["isDefault"] : false,
        name: json["name"] is String ? json["name"] : "",
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
        hiveSecret: json["hiveSecret"] is String ? json["hiveSecret"] : null,
        secret: json["secret"] is String ? json["secret"] : null,
      );

  Map<String, dynamic> toJson() => {
        "isDefault": isDefault,
        "name": name,
        "pkamPrivateKey": pkamPrivateKey,
        "pkamPublicKey": pkamPublicKey,
        "encryptionPublicKey": encryptionPublicKey,
        "encryptionPrivateKey": encryptionPrivateKey,
        "selfEncryptionKey": selfEncryptionKey,
        "hiveSecret": hiveSecret,
        "secret": secret,
      };

  AtsignKey copyWith({
    bool? isDefault,
    String? name,
    String? pkamPublicKey,
    String? pkamPrivateKey,
    String? encryptionPublicKey,
    String? encryptionPrivateKey,
    String? selfEncryptionKey,
    String? hiveSecret,
    String? secret,
  }) {
    return AtsignKey(
      isDefault: isDefault ?? this.isDefault,
      name: name ?? this.name,
      pkamPublicKey: pkamPublicKey ?? this.pkamPublicKey,
      pkamPrivateKey: pkamPrivateKey ?? this.pkamPrivateKey,
      encryptionPublicKey: encryptionPublicKey ?? this.encryptionPublicKey,
      encryptionPrivateKey: encryptionPrivateKey ?? this.encryptionPrivateKey,
      selfEncryptionKey: selfEncryptionKey ?? this.selfEncryptionKey,
      hiveSecret: hiveSecret ?? this.hiveSecret,
      secret: secret ?? this.secret,
    );
  }
}
