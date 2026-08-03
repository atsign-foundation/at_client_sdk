import 'dart:convert' show base64Encode, jsonEncode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        AtKeysMaterial,
        CryptographicKeyType,
        KeyAlgorithmType,
        WrittenAtKeysIo;
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart' show AtClient, AtKey, Metadata;
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('PqSigningRoot');

/// The atSign's user-owned root of trust: `public:pq_signing_root@<atSign>`.
///
/// ML-DSA-65, and a **signer only** — nothing is ever encapsulated to it. It
/// anchors the chain that vouches for enrollment signing keys, so that a
/// verifier is not left trusting whatever served the record.
///
/// **Create-once, and that matters more here than anywhere else.** The record
/// is written immutable, so the atServer refuses a second create and exactly
/// one root is ever published. The root never rotates, so two roots would be
/// unrecoverable rather than merely untidy — one half of the atSign's
/// enrollments would chain to a root the other half rejected, with no later
/// event able to reconcile them.
///
/// Only a **fully privileged** enrollment mints it — `rw` on `*` *and*
/// `__manage`. A namespace-restricted enrollment has no business minting the
/// key that vouches for every other enrollment, and could not convey it to the
/// privileged ones anyway.
@experimental
class PqSigningRoot {
  static const String recordName = 'pq_signing_root';

  /// The `AtKeys` id the private half is filed under. It carries no namespace
  /// — the root is atSign-level, which is exactly what distinguishes it from
  /// an nskey.
  static const String keyId = 'pq_signing_root';

  /// The published record's version, so a later shape can be told from this
  /// one rather than guessed at.
  static const int currentVersion = 1;

  final AtClient atClient;
  final AtKeysIo? keysIo;

  PqSigningRoot(this.atClient, {this.keysIo});

  AtKey keyFor(String atSign) => AtKey()
    ..key = recordName
    ..sharedBy = atSign
    ..metadata = (Metadata()
      ..isPublic = true
      ..immutable = true);

  /// Mints and publishes the root if this atSign has none, filing the private
  /// half first. Returns the public half, or null when this client did not
  /// mint (it is not privileged, or lost the create).
  ///
  /// A loser of the create does **not** mint a second root — it must be given
  /// the private half by a privileged enrollment that already has it, over the
  /// substrate. That pull is not built here yet.
  Future<Uint8List?> mintIfAbsent({required bool isFullyPrivileged}) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return null;

    if (!isFullyPrivileged) {
      _logger.info('Not minting the signing root for $atSign: this enrollment '
          'is not fully privileged, so it receives the root rather than '
          'creating it');
      return null;
    }

    final pair = await MlDsa65PureDartAlgo().generateKeyPair();

    // Durable before published, for the same reason minting an nskey is: a
    // published root whose private did not survive can never be replaced,
    // because the record is immutable and the root does not rotate.
    if (!await _store(atSign, pair.secretKey)) {
      throw StateError(
          'could not store the signing root private for $atSign, so it is '
          'deliberately not published — an immutable record cannot be retried '
          'with a different key');
    }

    try {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = keyFor(atSign)
            ..value = jsonEncode({
              'v': currentVersion,
              'keys': [base64Encode(pair.publicKey)],
              'successor': null,
            }),
          sync: true);
      return pair.publicKey;
    } catch (e) {
      // Almost certainly the atServer refusing a second create — another
      // privileged enrollment got there first, which is the create-once
      // guarantee working, not a failure.
      _logger.info('Did not publish a signing root for $atSign; one likely '
          'exists already: $e');
      return null;
    }
  }

  Future<bool> _store(String atSign, Uint8List private) async {
    final io = keysIo;
    if (io == null) return false;
    try {
      final AtKeys keys = await io.read(atSign);
      if (keys.getKey(keyId, CryptographicKeyType.privateSigning) != null) {
        return true;
      }
      keys.addKey(AtKeysMaterial(
        keyId: keyId,
        keyPartType: CryptographicKeyType.privateSigning,
        keyAlgorithmType: KeyAlgorithmType.mlDsa65,
        bytes: AtBytes(private),
        createdAt: DateTime.now().toUtc(),
      ));
      if (io is WrittenAtKeysIo) {
        await io.flush(atSign.toAtsign(), keys);
      } else {
        _logger.severe('Filed the signing root for $atSign in memory only — '
            'this AtKeysIo cannot persist, and an immutable root cannot be '
            'minted again');
        return false;
      }
      return true;
    } catch (e) {
      _logger.severe('Cannot store the signing root private for $atSign: $e');
      return false;
    }
  }
}
