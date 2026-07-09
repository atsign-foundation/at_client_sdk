import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/document.dart';
import 'package:at_auth/src/keys/types.dart';

abstract class AtKeysResolver {
  AtKeys resolve(AtKeysDocument document);
  AtKeysDocument resolveToDocument(AtKeys keys);
}

class AtKeysDocumentResolver implements AtKeysResolver {
  const AtKeysDocumentResolver();

  @override
  AtKeys resolve(AtKeysDocument document) {
    if (document is LegacyAtKeysDocument) {
      return AtKeys.fromJson(document.legacyJson);
    }
    //
    var atKeys = AtKeys(
      atsign: document.atsign,
      keysList: document.keys.map(_resolveRecord).toList(),
    );
    //if these atkeys format is new, regardless we need to load legacy for now.
    //todo: when we remove legacy callsites, remove this as well
    return AtKeys.loadLegacy(atKeys, document.legacyJson);
  }

  @override
  AtKeysDocument resolveToDocument(AtKeys keys) {
    //todo: remove at v4 when we can expect Atsigns to exist in the AtKeys
    //defintely a suboptimal way of doing this, but a good patch for 3.2.0
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
          enrollmentId: record.enrollmentId,
        ),
      KeyRecordKind.private => AtPrivateKey(
          pairId: _expectPairId(record),
          algorithm: record.algorithm,
          bytes: record.bytes,
          operations: record.operations,
          protection: record.protection,
          enrollmentId: record.enrollmentId,
        ),
      KeyRecordKind.symmetric => AtSymmetricKey(
          id: record.id,
          algorithm: record.algorithm,
          bytes: record.bytes,
          operations: record.operations,
          protection: record.protection,
          enrollmentId: record.enrollmentId,
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
          enrollmentId: material.enrollmentId,
        ),
      AtPrivateKey() => KeyRecord(
          id: 'private:${material.pairId}',
          pairId: material.pairId,
          kind: KeyRecordKind.private,
          algorithm: material.algorithm,
          bytes: material.bytes,
          operations: material.operations,
          protection: material.protection,
          enrollmentId: material.enrollmentId,
        ),
      AtSymmetricKey() => KeyRecord(
          id: material.id,
          kind: KeyRecordKind.symmetric,
          algorithm: material.algorithm,
          bytes: material.bytes,
          operations: material.operations,
          protection: material.protection,
          enrollmentId: material.enrollmentId,
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
}
