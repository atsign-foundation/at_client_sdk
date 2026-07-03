import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/at_commons.dart';

import '../../../at_auth.dart' as auth_constants;

abstract class AtKeysResolver {
  AtKeys resolve(AtKeysDocument document);
  AtKeysDocument resolveToDocument(AtKeys keys);
}

class AtKeysDocumentResolver implements AtKeysResolver {
  const AtKeysDocumentResolver();

  @override
  AtKeys resolve(AtKeysDocument document) {
    if (document is LegacyAtKeysDocument) {
      if (document.legacyJson == null) {
        throw AtKeysParseException(
            'Somehow parsing a legacy atKeys file with no json in the document object');
      }
      return AtKeys.fromJson(document.legacyJson!);
    }
    //
    var atKeys = AtKeys(
      atsign: document.atsign,
      keysList: document.keys.map(_resolveRecord).toList(),
    );
    //if these atkeys format is new, regardless we need to load legacy for now.
    //I'll come back to this in another PR because I think I do can some changes around atchops without breaking for now.
    return AtKeys.loadLegacy(atKeys, document.legacyJson);
  }

  @override
  AtKeysDocument resolveToDocument(AtKeys keys) {
    final atsign = keys.atsign;
    if (atsign == null) {
      return LegacyAtKeysDocument(keys.toJson());
    }

    return AtKeysDocument(
      version: AtKeysJsonCodec.supportedVersion,
      atsign: atsign,
      keys: keys.keyMaterials.map(_resolveMaterial).toList(),
      legacyJson: keys.toJson(),
    );
  }

  AtKeysMaterial _resolveRecord(KeyRecord record) {
    return switch (record.kind) {
      KeyRecordKind.public => AtPublicKey(
          pairId: _expectPairId(record),
          algorithm: record.algorithm,
          bytes: record.bytes,
          operations: record.operations,
        ),
      KeyRecordKind.private => AtPrivateKey(
          pairId: _expectPairId(record),
          algorithm: record.algorithm,
          bytes: record.bytes,
          operations: record.operations,
          protection: record.protection,
        ),
      KeyRecordKind.symmetric => AtSymmetricKey(
          id: record.id,
          algorithm: record.algorithm,
          bytes: record.bytes,
          operations: record.operations,
          protection: record.protection,
        ),
      KeyRecordKind.package => AtKeyPackage(
          enrollmentId: record.id,
          pairId: _expectPairId(record),
          algorithm: record.algorithm,
          bytes: record.bytes,
          publicKey: _expectPublicKey(record),
          operations: record.operations,
          secretProtection: record.protection,
        ),
    };
  }

  KeyRecord _resolveMaterial(AtKeysMaterial material) {
    return switch (material) {
      AtPublicKey() => KeyRecord(
          id: 'public:${material.pairId}',
          pairId: material.pairId,
          kind: KeyRecordKind.public,
          algorithm: material.algorithm,
          bytes: material.bytes,
          operations: material.operations,
        ),
      AtPrivateKey() => KeyRecord(
          id: 'private:${material.pairId}',
          pairId: material.pairId,
          kind: KeyRecordKind.private,
          algorithm: material.algorithm,
          bytes: material.bytes,
          operations: material.operations,
          protection: material.protection,
        ),
      AtSymmetricKey() => KeyRecord(
          id: material.id,
          kind: KeyRecordKind.symmetric,
          algorithm: material.algorithm,
          bytes: material.bytes,
          operations: material.operations,
          protection: material.protection,
        ),
      AtKeyPackage() => KeyRecord(
          id: material.enrollmentId,
          pairId: material.pairId,
          kind: KeyRecordKind.package,
          algorithm: material.algorithm,
          bytes: material.bytes,
          operations: material.operations,
          protection: material.secretProtection,
          publicKey: material.publicKey,
        ),
    };
  }

  String _expectPairId(KeyRecord record) {
    final pairId = record.pairId;
    if (pairId == null || pairId.isEmpty) {
      throw AtKeysValidationException(
          '${record.kind.name} key "${record.id}" must have pairId');
    }
    return pairId;
  }

  AtBytes _expectPublicKey(KeyRecord record) {
    final publicKey = record.publicKey;
    if (publicKey == null) {
      throw AtKeysValidationException(
          'Package key "${record.id}" must have publicKey');
    }
    return publicKey;
  }
}
