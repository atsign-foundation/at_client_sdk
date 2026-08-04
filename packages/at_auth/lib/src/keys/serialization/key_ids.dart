import 'package:at_commons/at_commons.dart';

/// The field names an `.atKeys` document reserves, and the `keyId` tokens this
/// package writes.
///
/// This is the single source of truth for "which fields are special". Every
/// (de)serialization path splits a keyfile's top level three ways, and each
/// piece is owned by exactly one of the sets below:
///
/// - [reservedTopLevelKeys] — the structural fields of the typed-keys document.
///   Read and written explicitly by `AtKeys`, never treated as payload.
/// - [keySchemaList] — the legacy flat key material fields.
/// - everything else — caller metadata, kept verbatim in `AtKeys.metadata`.
///
/// Use [isMetadata] to make that split; do not re-derive it locally. Two
/// divergent copies of this notion are what let `enrollmentId` be duplicated
/// into metadata (where a stale copy then shadowed the real field on write) and
/// later dropped from reads entirely.
abstract final class KeyIds {
  // structural top-level field names of the typed-keys document
  static const String version = 'version';
  static const String atsign = 'atsign';
  static const String keys = 'keys';

  // pq id's
  static const String apkamPQ = 'apkam/mldsa65';
  static const String globalXWing = 'atsign/xwing';
  // all legacy
  static const String apkamPublicKey = 'aesPkamPublicKey';
  static const String apkamPrivateKey = 'aesPkamPrivateKey';
  static const String defaultEncryptionPublicKey = 'aesEncryptPublicKey';
  static const String defaultEncryptionPrivateKey = 'aesEncryptPrivateKey';
  static const String defaultSelfEncryptionKey = 'selfEncryptionKey';
  static const String apkamSymmetricKey = 'apkamSymmetricKey';

  /// The field names of the legacy flat key material.
  static const keySchemaList = [
    apkamPublicKey,
    apkamPrivateKey,
    defaultEncryptionPublicKey,
    defaultEncryptionPrivateKey,
    defaultSelfEncryptionKey,
    apkamSymmetricKey,
  ];

  /// The structural fields of the typed-keys document.
  static const reservedTopLevelKeys = {
    version,
    atsign,
    keys,
    AtConstants.enrollmentId,
    AtConstants.apkamNamespaces,
  };

  /// A field owned by the schema must never be copied into `AtKeys.metadata`.
  static bool isMetadata(String key) =>
      !reservedTopLevelKeys.contains(key) && !keySchemaList.contains(key);
}
