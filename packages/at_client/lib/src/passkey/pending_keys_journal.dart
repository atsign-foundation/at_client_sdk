import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys, WrittenAtKeysIo;
import 'package:at_auth/passkey.dart';
import 'package:at_commons/atsign.dart';

import 'at_keys_document.dart';

/// A key store for an activation that seals every keys write it sees into a
/// [PendingOnboardingStore], so that the keys an activation mints outlive the
/// process that minted them.
///
/// Reads, writes, flushes and updates go to [inner]; each write, flush or update then seals a
/// copy of the keys without any APKAM private key (the passkey re-derives it)
/// and keeps it as [atSign]'s pending record. A write that cannot be sealed
/// fails, so an activation that files its keys through this store has either
/// kept the record or stopped before it spent anything further. Keys that name
/// no enrollment to authenticate as are not sealed.
class PendingKeysJournal extends WrittenAtKeysIo {
  /// A journal of [inner]'s writes for [atSign], sealed by [vault] and kept
  /// under [credentialId], the passkey that opens it.
  PendingKeysJournal(
      {required WrittenAtKeysIo inner,
      required this.atSign,
      required this.credentialId,
      required PasskeyVault vault,
      required PendingOnboardingStore store})
      : _inner = inner,
        _vault = vault,
        _store = store;

  final WrittenAtKeysIo _inner;
  final PasskeyVault _vault;
  final PendingOnboardingStore _store;

  /// The canonical atSign whose activation this journals.
  final String atSign;

  /// The passkey that sealed the record.
  final Uint8List credentialId;

  @override
  FutureOr<AtKeys> read(String atsign) => _inner.read(atsign);

  @override
  Future write(String atsign, AtKeys atKeys) async {
    await _inner.write(atsign, atKeys);
    await _seal(atKeys);
  }

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) async {
    await _inner.flush(atsign, atKeys);
    await _seal(atKeys);
  }

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    AtKeys? changed;
    await _inner.update(atsign, (keys) async {
      final applied = await mutate(keys);
      if (applied != false) changed = keys;
      return applied;
    });
    final keys = changed;
    if (keys != null) await _seal(keys);
  }

  Future<void> _seal(AtKeys keys) async {
    final enrollmentId = keys.resolveAuthenticatingEnrollment();
    if (enrollmentId == null) return;
    final document = atKeysDocument(keys, atSign);
    final sealed = await _vault.seal(PasskeyRecordType.pending,
        {'enrollmentId': enrollmentId, 'atKeys': document});
    await _store.put(
        atSign,
        PendingOnboardingRecord(
            credentialId: credentialId,
            enrollmentId: enrollmentId,
            encryptionPublicKey: document['aesEncryptPublicKey'] as String?,
            sealed: sealed));
  }
}
