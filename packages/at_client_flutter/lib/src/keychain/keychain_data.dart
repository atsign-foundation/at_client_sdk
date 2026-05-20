import 'package:at_auth/at_auth.dart' show AtKeys;

sealed class KeychainData {
  KeychainData();
  Map<String, dynamic> toJson() {
    return {};
  }
}

class EmptyKeychainData extends KeychainData {
  EmptyKeychainData();
}

class AtKeysData extends KeychainData {
  List<AtKeys> keys;
  String? defaultAtsign;
  AtKeysData({this.keys = const [], this.defaultAtsign});

  factory AtKeysData.fromJson(Map<String, dynamic> json) => AtKeysData(
        keys: (json['keys'] as List<dynamic>?)
                ?.map((e) => AtKeys.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        defaultAtsign: json['defaultAtsign'],
      );

  @override
  Map<String, dynamic> toJson() => {
        'keys': (keys).map((e) => e.toJson()).toList(),
        'defaultAtsign': defaultAtsign,
      };
}

class EnrollmentData extends KeychainData {
  String enrollmentId;
  AtKeys atAuthKeys;
  int enrollmentSubmissionTimeEpoch;
  Map<String, dynamic>? namespace;
  String? keysFilePath;

  EnrollmentData(
    this.enrollmentId,
    this.atAuthKeys,
    this.enrollmentSubmissionTimeEpoch, {
    this.namespace,
    this.keysFilePath,
  });

  factory EnrollmentData.fromJson(Map<String, dynamic> json) => EnrollmentData(
        json['enrollmentId'] as String,
        AtKeys.fromJson(json['atAuthKeys'] as Map<String, dynamic>),
        json['enrollmentSubmissionTimeEpoch'] as int,
        namespace: json['namespace'] as Map<String, dynamic>?,
        keysFilePath: json['keysFilePath'] as String?,
      );

  @override
  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'atAuthKeys': atAuthKeys.toJson(),
      'enrollmentSubmissionTimeEpoch': enrollmentSubmissionTimeEpoch,
      'namespace': namespace,
      'keysFilePath': keysFilePath,
    };
  }
}

class SppData extends KeychainData {
  final String value;
  final DateTime expiry;

  SppData({required this.value, required this.expiry})
      : assert(value.length == 6, 'SPP must be exactly 6 characters');

  bool get isExpired => DateTime.now().isAfter(expiry);

  factory SppData.fromJson(Map<String, dynamic> json) => SppData(
        value: json['spp'] as String,
        expiry: DateTime.parse(json['expiry'] as String),
      );

  @override
  Map<String, dynamic> toJson() => {
        'spp': value,
        'expiry': expiry.toIso8601String(),
      };
}

class SppListData extends KeychainData {
  List<SppData> spps;
  SppListData({this.spps = const []});

  factory SppListData.fromJson(Map<String, dynamic> json) => SppListData(
        spps: (json['spps'] as List<dynamic>?)
                ?.map((e) => SppData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  @override
  Map<String, dynamic> toJson() => {
        'spps': (spps).map((e) => e.toJson()).toList(),
      };
}
