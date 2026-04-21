import 'dart:convert';

class CryptoScheme {
  final String keyName;
  final String algorithm;
  final String encKeyName;

  CryptoScheme(this.keyName, this.algorithm, this.encKeyName);

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'keyName': keyName,
      'algorithm': algorithm,
      'encKeyName': encKeyName,
    };
    return map;
  }

  factory CryptoScheme.fromJson(Map<String, dynamic> json) {
    return CryptoScheme(
      json['keyName']?.toString() ?? '',
      json['algorithm']?.toString() ?? '',
      json['encKeyName']?.toString() ?? '',
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
