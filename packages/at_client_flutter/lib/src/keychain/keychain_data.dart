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

  /// Reads a keychain document, including one at_client_mobile wrote, whose
  /// entries name their keys differently from an atKeys file.
  factory AtKeysData.fromJson(Map<String, dynamic> json) => AtKeysData(
    keys:
        (json['keys'] as List<dynamic>?)
            ?.map(
              (e) => AtKeys.fromJson(
                _withAtKeysFieldNames(e as Map<String, dynamic>),
              ),
            )
            .toList() ??
        [],
    defaultAtsign: json['defaultAtsign'],
  );

  /// at_client_mobile's `AtsignKey` field names, and the atKeys file names
  /// [AtKeys.fromJson] reads the same keys under.
  static const _atClientMobileFieldNames = {
    'pkamPublicKey': 'aesPkamPublicKey',
    'pkamPrivateKey': 'aesPkamPrivateKey',
    'encryptionPublicKey': 'aesEncryptPublicKey',
    'encryptionPrivateKey': 'aesEncryptPrivateKey',
  };

  /// [entry] with at_client_mobile's field names replaced by the atKeys file
  /// names.
  static Map<String, dynamic> _withAtKeysFieldNames(
    Map<String, dynamic> entry,
  ) => {
    for (final MapEntry(:key, :value) in entry.entries)
      _atClientMobileFieldNames[key] ?? key: value,
  };

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
