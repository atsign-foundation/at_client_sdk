import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';

abstract class AtKeysCodec {
  AtKeysDocument decodeDocument(Map<String, dynamic> json);
  Map<String, dynamic> encodeDocument(AtKeysDocument document);
}

class AtKeysJsonCodec implements AtKeysCodec {
  static const supportedVersion = 1;
  const AtKeysJsonCodec();
  @override
  AtKeysDocument decodeDocument(Map<String, dynamic> json) {
    late final int version;
    // if the json doesn't have a version field, it's a legacy atKeys file.
    try {
      version = _expectInt(json['version'], 'version');
    } catch (_) {
      return LegacyAtKeysDocument(json);
    }
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }

    final atsign = _expectNonEmptyString(json['atSign'], 'atSign').toAtsign();
    final legacyJson = _optionalLegacyJson(json['legacy'], 'legacy');
    final keysJson = _expectList(json['keys'], 'keys');

    final keys = keysJson
        .asMap()
        .entries
        .map((entry) => _decodeRecord(
              _expectMap(entry.value, 'keys[${entry.key}]'),
              entry.key,
            ))
        .toList();

    _validateDuplicateIds(keys);
    _validateProtectionReferences(keys);

    return AtKeysDocument(
      version: version,
      atsign: atsign,
      keys: keys,
      legacyJson: legacyJson,
    );
  }

  @override
  Map<String, dynamic> encodeDocument(AtKeysDocument document) {
    if (document is LegacyAtKeysDocument) {
      return document.legacyJson ?? {};
    }
    return {
      'legacy': jsonEncode(document.legacyJson),
      'version': document.version,
      'atSign': document.atsign,
      'keys': document.keys.map(_encodeRecord).toList(),
    };
  }
}

KeyRecord _decodeRecord(Map<String, dynamic> json, int index) {
  final fieldPrefix = 'keys[$index]';
  final id = _expectNonEmptyString(json['id'], '$fieldPrefix.id');

  final kindToken = _expectNonEmptyString(json['kind'], '$fieldPrefix.kind');
  late final KeyRecordKind kind;
  try {
    kind = KeyRecordKind.values.byName(kindToken);
  } on ArgumentError {
    throw AtKeysValidationException(
        'Unsupported atKeys kind "$kindToken" at $fieldPrefix');
  }

  final algorithm =
      _expectNonEmptyString(json['algorithm'], '$fieldPrefix.algorithm');

  final value = _expectNonEmptyString(json['value'], '$fieldPrefix.value');
  _validateBase64(value, '$fieldPrefix.value');

  final pairId = _optionalString(json['pairId'], '$fieldPrefix.pairId');
  final publicKey =
      _optionalBase64Bytes(json['publicKey'], '$fieldPrefix.publicKey');
  final protection = json.containsKey('protection')
      ? _decodeProtection(json['protection'], '$fieldPrefix.protection')
      : null;

  if (kind == KeyRecordKind.symmetric) {
    if (pairId != null) {
      throw AtKeysValidationException(
          'Symmetric key "$id" must not have pairId');
    }
  } else if (kind != KeyRecordKind.package &&
      (pairId == null || pairId.isEmpty)) {
    throw AtKeysValidationException('Asymmetric key "$id" must have pairId');
  }

  if (publicKey != null && kind != KeyRecordKind.package) {
    throw AtKeysValidationException(
        'Only package key "$id" may have publicKey');
  }

  if (protection != null && kind == KeyRecordKind.public) {
    throw AtKeysValidationException('Public key "$id" must not be protected');
  }

  return KeyRecord(
    id: id,
    pairId: pairId,
    kind: kind,
    algorithm: algorithm,
    operations:
        _optionalStringList(json['operations'], '$fieldPrefix.operations'),
    protection: protection,
    bytes: AtBytes.fromString(value),
    publicKey: publicKey,
  );
}

Map<String, dynamic> _encodeRecord(KeyRecord record) {
  return {
    'id': record.id,
    if (record.pairId != null) 'pairId': record.pairId,
    'kind': record.kind.jsonToken,
    'algorithm': record.algorithm,
    if (record.operations.isNotEmpty) 'operations': record.operations,
    if (record.protection != null) 'protection': record.protection!.toJson(),
    if (record.publicKey != null) 'publicKey': record.publicKey!.toString(),
    'value': record.bytes.toString(),
  };
}

// <------- Expect Types (helpers) ------->

int _expectInt(Object? value, String fieldName) {
  if (value is int) {
    return value;
  }
  throw AtKeysParseException('Expected integer in $fieldName');
}

String _expectNonEmptyString(Object? value, String fieldName) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw AtKeysParseException('Expected string in $fieldName');
}

String? _optionalString(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw AtKeysParseException('Expected string at $fieldName');
}

List<String> _optionalStringList(Object? value, String fieldName) {
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw AtKeysParseException('Expected array at $fieldName');
  }
  return value
      .asMap()
      .entries
      .map((entry) =>
          _expectNonEmptyString(entry.value, '$fieldName[${entry.key}]'))
      .toList();
}

Map<String, dynamic> _expectMap(Object? value, String fieldName) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw AtKeysParseException('Expected object at $fieldName');
}

List<dynamic> _expectList(Object? value, String fieldName) {
  if (value is List) {
    return value;
  }
  throw AtKeysParseException('Expected array at $fieldName');
}

Map<String, dynamic>? _optionalLegacyJson(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded == null) {
      return null;
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  }
  throw AtKeysParseException('Expected object at $fieldName');
}

void _validateBase64(String value, String fieldName) {
  try {
    base64Decode(value);
  } on FormatException catch (e) {
    throw AtKeysValidationException('Malformed base64 at $fieldName: $e');
  }
}

AtBytes? _optionalBase64Bytes(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  final stringValue = _expectNonEmptyString(value, fieldName);
  _validateBase64(stringValue, fieldName);
  return AtBytes.fromString(stringValue);
}

KeyProtection _decodeProtection(Object? value, String fieldName) {
  final json = _expectMap(value, fieldName);
  return KeyProtection(
    keyRef: _expectNonEmptyString(json['keyRef'], '$fieldName.keyRef'),
    algorithm: _expectNonEmptyString(json['algorithm'], '$fieldName.algorithm'),
    iv: _expectNonEmptyString(json['iv'], '$fieldName.iv'),
  );
}

void _validateDuplicateIds(List<KeyRecord> keys) {
  final seen = <String>{};
  for (final key in keys) {
    if (!seen.add(key.id)) {
      throw AtKeysValidationException('Duplicate atKeys id "${key.id}"');
    }
  }
}

void _validateProtectionReferences(List<KeyRecord> keys) {
  final ids = keys.map((key) => key.id).toSet();
  for (final key in keys) {
    final protection = key.protection;
    if (protection == null) {
      continue;
    }
    if (protection.keyRef == key.id) {
      throw AtKeysProtectionException(
          'Key "${key.id}" must not protect itself');
    }
    if (!ids.contains(protection.keyRef)) {
      throw AtKeysProtectionException(
          'Key "${key.id}" references unknown protection key '
          '"${protection.keyRef}"');
    }
  }
}
