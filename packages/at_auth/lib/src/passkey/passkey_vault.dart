import 'dart:typed_data';

import 'passkey_derivation.dart';
import 'passkey_record.dart';

/// The passkey-derived identity of one atSign on one device: the record id
/// and pointer namespace, a sealer for its records, and the seed of its APKAM
/// signing key.
///
/// Built from a [PasskeyDerivation]. [close] marks the vault closed at once:
/// sealing, opening and reading the seed afterwards throw [StateError]. The
/// auth seed is wiped and the sealer closed when no [withAuthSeed] use is still
/// running, so a use that began before [close] finishes with the intact seed.
/// Only the buffers the vault holds are wiped.
class PasskeyVault {
  /// Takes ownership of [derivation]'s auth seed and sealer, for the canonical
  /// [atSign] it was derived for.
  ///
  /// Throws [ArgumentError] when the auth seed is not exactly 32 bytes.
  PasskeyVault(PasskeyDerivation derivation, {required this.atSign})
      : lookupHex = derivation.lookupHex,
        ns = derivation.ns,
        _authSeed = _checkedSeed(derivation.authSeed),
        _sealer = derivation.sealer;

  static Uint8List _checkedSeed(Uint8List seed) {
    if (seed.length != 32) {
      throw ArgumentError.value(
          seed.length, 'authSeed.length', 'auth seed must be 32 bytes');
    }
    return seed;
  }

  /// The canonical atSign this vault belongs to; its records open for this
  /// atSign only.
  final String atSign;

  /// 64 lowercase hex characters naming the record
  /// `public:_<lookupHex>.<ns>@<atSign>`.
  final String lookupHex;

  /// 64 lowercase hex characters naming the namespace of this passkey's
  /// pointer.
  final String ns;

  final Uint8List _authSeed;
  final RecordSealer _sealer;
  var _closed = false;
  var _seedWiped = false;
  var _inFlight = 0;

  /// [document] of type [typ] sealed as a record's JSON text.
  Future<String> seal(
          PasskeyRecordType typ, Map<String, dynamic> document) async =>
      PasskeyRecordCodec.seal(_open(), atSign, typ, document);

  /// The document in [record], opened as type [typ].
  ///
  /// Throws [UnsupportedPasskeyRecordException] or
  /// [PasskeyRecordAuthenticationException] as [PasskeyRecordCodec.open] does.
  Future<Map<String, dynamic>> open(
          PasskeyRecordType typ, String record) async =>
      PasskeyRecordCodec.open(_open(), atSign, typ, record);

  /// Runs [use] with the 32-byte auth seed; [use] must not keep it. A [close]
  /// during [use] does not touch the seed until [use] completes, after which
  /// the seed is overwritten with zeroes.
  ///
  /// Throws [StateError] once the vault is closed or [wipeAuthSeed] was called.
  Future<T> withAuthSeed<T>(Future<T> Function(Uint8List seed) use) async {
    _open();
    if (_seedWiped) throw StateError('the auth seed was wiped');
    _inFlight++;
    try {
      return await use(_authSeed);
    } finally {
      _inFlight--;
      _release();
    }
  }

  /// Overwrites the auth seed with zeroes, as soon as no [withAuthSeed] use is
  /// running, and refuses later uses. Sealing and opening keep working until
  /// [close]. Safe to call again.
  void wipeAuthSeed() {
    _seedWiped = true;
    if (_inFlight == 0) _authSeed.fillRange(0, _authSeed.length, 0);
  }

  /// Marks the vault closed, then wipes the auth seed and closes the sealer
  /// once no [withAuthSeed] use is running (at once when none is). Safe to call
  /// again.
  void close() {
    if (_closed) return;
    _closed = true;
    _release();
  }

  void _release() {
    if (_inFlight > 0) return;
    if (_closed || _seedWiped) _authSeed.fillRange(0, _authSeed.length, 0);
    if (_closed) _sealer.close();
  }

  RecordSealer _open() {
    if (_closed) throw StateError('PasskeyVault is closed');
    return _sealer;
  }
}
