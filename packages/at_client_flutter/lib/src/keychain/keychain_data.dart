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
    keys:
        (json['keys'] as List<dynamic>?)
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

/// A semi-permanent passcode the atSign accepted, and when it stops working;
/// [expiry] is null for one set with no expiry.
class SppData extends KeychainData {
  final String value;
  final DateTime? expiry;

  SppData({required this.value, required this.expiry});

  bool get isExpired {
    final expiry = this.expiry;
    return expiry != null && DateTime.now().isAfter(expiry);
  }

  factory SppData.fromJson(Map<String, dynamic> json) => SppData(
    value: json['spp'] as String,
    expiry: json['expiry'] == null
        ? null
        : DateTime.parse(json['expiry'] as String),
  );

  @override
  Map<String, dynamic> toJson() => {
    'spp': value,
    'expiry': expiry?.toIso8601String(),
  };
}

class SppListData extends KeychainData {
  List<SppData> spps;
  SppListData({this.spps = const []});

  factory SppListData.fromJson(Map<String, dynamic> json) => SppListData(
    spps:
        (json['spps'] as List<dynamic>?)
            ?.map((e) => SppData.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );

  @override
  Map<String, dynamic> toJson() => {
    'spps': (spps).map((e) => e.toJson()).toList(),
  };
}
