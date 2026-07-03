import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysDocument {
  final int version;
  final Atsign atsign;
  final Map<String, dynamic>? legacyJson;
  final List<KeyRecord> keys;

  const AtKeysDocument({
    required this.version,
    required this.atsign,
    required this.keys,
    this.legacyJson,
  });
}

class LegacyAtKeysDocument implements AtKeysDocument {
  @override
  int get version => 0;
  @override
  Atsign get atsign => "@legacy".toAtsign();
  @override
  List<KeyRecord> get keys => [];
  @override
  final Map<String, dynamic>? legacyJson;

  const LegacyAtKeysDocument(this.legacyJson);
}

enum KeyRecordKind { public, private, package, symmetric }

extension KeyKindJson on KeyRecordKind {
  String get jsonToken {
    return switch (this) {
      KeyRecordKind.public => 'public',
      KeyRecordKind.private => 'private',
      KeyRecordKind.symmetric => 'symmetric',
      KeyRecordKind.package => 'package',
    };
  }
}

class KeyRecord {
  final String id;
  final KeyRecordKind kind;
  final String algorithm;
  final List<String> operations;
  final AtBytes bytes;
  //protection for symmetric, private keys and secrets
  final KeyProtection? protection;
  // pairIds exist for the public/private halves to link them together (if applicable)
  final String? pairId;
  // key packages have publicKey and a secret (ie bytes)
  final AtBytes? publicKey;

  const KeyRecord({
    required this.id,
    required this.kind,
    required this.algorithm,
    required this.bytes,
    this.pairId,
    this.operations = const [],
    this.protection,
    this.publicKey,
  });
}
