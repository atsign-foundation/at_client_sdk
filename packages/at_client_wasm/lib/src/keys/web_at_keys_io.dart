import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

import 'key_bytes_store.dart';
import 'key_envelope.dart';
import 'unlock_secret.dart';

/// [AtKeys] sealed in a key envelope in a [KeyBytesStore], one record per
/// atSign.
///
/// Opens with [secret]; seals new records with [sealWith], which defaults to
/// `[secret]`. A flush or update keeps the record's content key and unlocks.
class WebAtKeysIo extends WrittenAtKeysIo {
  WebAtKeysIo(
    this.store,
    this.secret, {
    this.codec = const KeyEnvelopeCodec(),
    List<UnlockSecret>? sealWith,
  }) : sealWith = sealWith ?? [secret];

  final KeyBytesStore store;
  final UnlockSecret secret;
  final KeyEnvelopeCodec codec;
  final List<UnlockSecret> sealWith;

  Future<void> _tail = Future.value();

  @override
  Future<AtKeys> read(String atsign) async {
    final atSign = atsign.toAtsign();
    final opened = await _open(atSign) ??
        (throw AtKeysSourceAbsentException('no keys for $atSign in the store'));
    return AtKeys.fromJson(opened.plaintext);
  }

  @override
  Future<void> write(String atsign, AtKeys atKeys) {
    final atSign = atsign.toAtsign();
    return _serialized(() async {
      if (await store.get(atSign) != null) {
        throw AtKeysFileOverwriteException(
            'keys for $atSign already exist in the store');
      }
      await _seal(atSign, atKeys);
    });
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) {
    final atSign = atsign.toString();
    return _serialized(() async {
      final opened = await _open(atSign);
      opened == null
          ? await _seal(atSign, atKeys)
          : await _reseal(opened, atKeys);
    });
  }

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) {
    final atSign = atsign.toString();
    return _serialized(() async {
      final opened = await _open(atSign) ??
          (throw AtKeysSourceAbsentException(
              'no keys for $atSign in the store'));
      final keys = AtKeys.fromJson(opened.plaintext);
      if (await mutate(keys)) await _reseal(opened, keys);
    });
  }

  Future<OpenedEnvelope?> _open(String atSign) async {
    final bytes = await store.get(atSign);
    return bytes == null ? null : codec.open(atSign, bytes, secret);
  }

  Future<void> _seal(String atSign, AtKeys atKeys) async => store.put(
      atSign, await codec.seal(atSign, _atRest(atSign, atKeys), sealWith));

  Future<void> _reseal(OpenedEnvelope opened, AtKeys atKeys) async {
    final candidate = _atRest(opened.atSign, atKeys);
    assurance.validateMapUpdate(
        existing: opened.plaintext, candidate: candidate);
    await store.put(opened.atSign, await opened.reseal(candidate));
  }

  /// [atKeys] as the sealed document, once it is confirmed to be [atSign]'s.
  Map<String, dynamic> _atRest(String atSign, AtKeys atKeys) {
    atKeys.atsign ??= Atsign(atSign);
    if (atKeys.atsign != atSign) {
      throw AtKeysValidationException(
          'keys of ${atKeys.atsign} cannot be stored for $atSign');
    }
    return atKeys.toJson();
  }

  /// Runs [action] once every earlier write, flush and update has settled.
  Future<void> _serialized(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.catchError((_) {});
    return run;
  }
}
