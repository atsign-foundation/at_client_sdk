import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart'
    show NskeyPrivateFiling;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show verifiedAdvertisementKey;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart'
    show AtClientEnvelopeSigner;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
import 'package:at_commons/at_builders.dart'
    show LLookupVerbBuilder, UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart' show AtKey, StoppedException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:crypto/crypto.dart' show sha256;

final _logger = AtSignLogger('VerifiedAdvertisementRecord');

/// This client's own record that it verified the bytes of its namespace-key
/// advertisement against the publishing enrollment's `_apsk`.
///
/// Kept in local storage under a `local:` key, which never syncs, and signed
/// with this client's data signing key, so nothing that can only write local
/// storage can produce one. It names the namespace keys the client held when
/// it verified, and vouches for exactly those bytes only while the client
/// holds the same ones.
class VerifiedAdvertisementRecord {
  final AtClient _atClient;
  final NskeyPrivateFiling? _filing;
  final AtClientEnvelopeSigner _signer;

  VerifiedAdvertisementRecord(this._atClient, {NskeyPrivateFiling? filing})
      : _filing = filing,
        _signer = AtClientEnvelopeSigner(_atClient);

  /// Records that [payload], this atSign's advertisement for [namespace], was
  /// just verified online. A failure is logged, since the advertisement itself
  /// was verified and only a later offline start loses by it.
  Future<void> remember(String namespace, String payload) async {
    final key = _keyFor(namespace);
    final local = _atClient.getLocalSecondary();
    if (key == null || local == null) return;
    try {
      final record = await _recordFor(namespace, payload);
      if (record == null) return;
      if (await _alreadyRecorded(key, record)) return;
      final envelope = await _signer.wrapAndSign(record,
          type: EnvelopeType.verifiedAdvertisement);
      await local.executeVerb(UpdateVerbBuilder()
        ..atKey = key
        ..value = jsonEncode(envelope.toJson()));
    } on StoppedException {
      rethrow;
    } on Object catch (e) {
      _logger.warning('Verified the advertisement for $namespace but could '
          'not record it locally, so a start with no atServer re-verifies it '
          'online: $e');
    }
  }

  /// Whether this client's record vouches for [payload] as its advertisement
  /// for [namespace]: signed with this client's data signing key, naming
  /// exactly these bytes, and the namespace keys the client holds now.
  Future<bool> vouchesFor(String namespace, String payload) async {
    final key = _keyFor(namespace);
    if (key == null || _atClient.getLocalSecondary() == null) return false;
    try {
      final stored = await _stored(key);
      if (stored == null) return false;
      final record = await _recordFor(namespace, payload);
      if (record == null) return false;
      if (!await _signedByThisClient(stored)) {
        _logger.warning('The local record for $namespace\'s advertisement '
            'is not signed with this client\'s data signing key, so it is '
            'not used');
        return false;
      }
      return _sameRecord(stored, record);
    } on StoppedException {
      rethrow;
    } on Object catch (e) {
      _logger.info('Could not read the local record for $namespace\'s '
          'advertisement, so it vouches for nothing: $e');
      return false;
    }
  }

  /// Whether [key] already holds [record], signed by this client; false when
  /// what it holds cannot be read as a record, so a fresh one replaces it.
  Future<bool> _alreadyRecorded(AtKey key, Map<String, Object?> record) async {
    try {
      final stored = await _stored(key);
      return stored != null &&
          _sameRecord(stored, record) &&
          await _signedByThisClient(stored);
    } on StoppedException {
      rethrow;
    } on Object catch (e) {
      _logger.info('The local record at $key cannot be read as a record, so '
          'it is replaced: $e');
      return false;
    }
  }

  AtKey? _keyFor(String namespace) {
    final enrollmentId = _atClient.enrollmentId;
    final atSign = _atClient.getCurrentAtSign();
    if (enrollmentId == null || atSign == null) return null;
    return verifiedAdvertisementKey(
        sharedBy: atSign, enrollmentId: enrollmentId, namespace: namespace);
  }

  /// What a record of [payload] for [namespace] says, as this client would
  /// write it now; null when there is no keyfile to read the held keys from.
  Future<Map<String, Object?>?> _recordFor(
      String namespace, String payload) async {
    final filing = _filing;
    if (filing == null) return null;
    final held = [for (final f in await filing.filedFor(namespace)) f.nskeyKid]
      ..sort();
    return {
      'atSign': _atClient.getCurrentAtSign(),
      'namespace': namespace,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'held': held,
    };
  }

  Future<SignedEnvelope?> _stored(AtKey key) async {
    final String? value;
    try {
      value = await _atClient
          .getLocalSecondary()!
          .executeVerb(LLookupVerbBuilder()..atKey = key);
    } on Exception {
      return null;
    }
    if (value == null || value == 'data:null') return null;
    final decoded = jsonDecode(value.replaceFirst(RegExp('^data:'), ''));
    if (decoded is! Map) return null;
    return SignedEnvelope.fromJson(decoded);
  }

  Future<bool> _signedByThisClient(SignedEnvelope envelope) async {
    try {
      await verifyEnvelope(envelope,
          signerPublicKey: await _signer.publicSigningKeyValue,
          expecting: EnvelopeType.verifiedAdvertisement);
      return true;
    } on Exception {
      return false;
    }
  }

  bool _sameRecord(SignedEnvelope stored, Map<String, Object?> record) =>
      jsonEncode(stored.payload) == jsonEncode(record);
}
