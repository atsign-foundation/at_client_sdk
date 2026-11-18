import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart' show AtException;
import 'package:at_commons/atsign.dart';

import 'at_keys_document.dart';
import 'enrollment_document_store.dart';
import 'enrollment_gateway.dart' show ApkamKeyPair, withApkamKey;
import 'passkey_custody.dart' show MissingAtKeysDocumentException;

/// Thrown when the document read back after a write is not the one written
/// or cannot be opened, when a write is attempted after the store refused one,
/// or when the keys to write belong to another atSign. Nothing was overwritten
/// to repair it.
class AtServerAtKeysWriteException extends AtException {
  AtServerAtKeysWriteException(super.message);

  @override
  String toString() => 'AtServerAtKeysWriteException: $message';
}

/// An enrollment's @keys, held as one sealed document on the atServer.
///
/// [write] creates the document and refuses when one exists. [flush] and
/// [update] replace it: each re-reads the stored document just before writing
/// and refuses a candidate that drops anything stored; they then write, read
/// the document back and compare it with what was written. A mismatch throws
/// and nothing further is written. After any refusal this store accepts no
/// more writes. Nothing is merged and no write is retried.
///
/// Writes on one instance run one at a time: [write], [flush] and [update]
/// each hold this instance's lock across the re-read, the put and the read
/// back, so overlapping calls queue instead of interleaving, and a call that
/// throws does not stop the ones queued behind it. The lock is per instance
/// and in-process; it does not reach another instance or process.
///
/// Several writers may share an enrollment. Every [update] re-reads the stored
/// document and builds its candidate on it, so it keeps what another writer
/// filed since this store last read. A write that would drop stored material is
/// refused, and the store then accepts no more writes this session. Each write
/// is read back and compared with what was written. Two writes that land
/// between one writer's re-read and its own write can still replace each
/// other: the server has no conditional update yet, so nothing detects it.
///
/// The document never holds the enrollment's APKAM private key: a passkey
/// enrollment derives the pair from the passkey and the atServer must not
/// keep it. This store is given that derived pair instead. Every document it
/// seals is stripped of the flat APKAM private key, every typed
/// `privateAuthentication` material and the pair's own public half, so what is
/// read back and compared is the stripped form. A candidate that holds active
/// private authentication material other than the pair (a rotation, a
/// retrofit) is refused with [AtServerAtKeysWriteException], never stripped
/// silently, and the store then accepts no more writes.
///
/// Once the first document is held, [read] does no I/O: it serves the last
/// document this store decoded or wrote, as fresh keys each call, with the
/// pair filed as the enrollment's authentication material. That is what lets
/// the client re-authenticate (reconnect, sync, monitor) from its key store
/// without a round trip to the atServer it is trying to reach. The held
/// document is refreshed by this store's own [update], [flush] and [write];
/// another writer's change shows on the next [update] or reopen. The pair is
/// held as bytes, encoded on each read and zeroed by [close]; a [read] after
/// [close] throws [StateError].
class AtServerAtKeysIo extends WrittenAtKeysIo implements ClosableAtKeysIo {
  AtServerAtKeysIo(
      {required EnrollmentDocumentStore documents,
      required PasskeyVault vault,
      required String enrollmentId,
      required ApkamKeyPair apkamKeyPair,
      this.closedByClient = false,
      AtKeys? restored})
      : _documents = documents,
        _vault = vault,
        _enrollmentId = enrollmentId,
        _publicKey = apkamKeyPair.publicKey,
        _private = base64Decode(apkamKeyPair.privateKey) {
    final seed = restored;
    if (seed != null && seed.atsign != null) {
      _cache = jsonEncode(_stripped(seed));
    }
  }

  final EnrollmentDocumentStore _documents;
  final PasskeyVault _vault;
  final String _enrollmentId;
  final String _publicKey;

  /// The APKAM private key of the derived pair, zeroed by [close].
  final Uint8List _private;
  bool _refused = false;
  bool _closed = false;
  bool _released = false;

  /// Writes queued or running on the chain.
  int _pending = 0;

  /// The stripped document last decoded or written, as JSON; null until the
  /// first read. [read] serves it without I/O.
  String? _cache;

  /// The end of the chain of writes queued on this instance.
  Future<void> _tail = Future<void>.value();

  /// Runs [body] after every earlier call has finished, and returns its
  /// result. A body that throws fails only its own call; the chain goes on.
  ///
  /// A call that has not started when [close] runs fails with
  /// [AtServerAtKeysWriteException] before any I/O. A call already running
  /// finishes whole, with the vault and the pair still open: [close] releases
  /// them only when the last call on the chain has settled.
  Future<T> _serialized<T>(Future<T> Function() body) {
    _pending++;
    final result = _tail.then((_) {
      if (_closed) {
        throw AtServerAtKeysWriteException(
            'enrollment $_enrollmentId: this key store is closed, so the '
            'write was not made');
      }
      return body();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (--_pending == 0 && _closed) _release();
    });
    return result;
  }

  /// Whether the client that runs on this store closes it when it stops.
  ///
  /// False by default: the store is lent, and whoever lent it closes the
  /// [PasskeyVault] it was given. True hands the vault's lifetime to the
  /// client, whose stop then calls [close].
  @override
  final bool closedByClient;

  /// Zeroes the APKAM private key this store holds and, when
  /// [closedByClient], closes the vault it was given, which overwrites the
  /// auth seed with zeroes and closes its sealer. A lent store leaves the
  /// vault open for whoever lent it. Idempotent. A later read throws
  /// [StateError]; a later or queued write, flush or update throws
  /// [AtServerAtKeysWriteException] without touching the atServer.
  ///
  /// A write already running is not cut off: it finishes, and the vault and
  /// the key are released right after it. Never waits, so a write that hangs
  /// cannot hold a stop; it holds the key in memory until it settles.
  @override
  void close() {
    _closed = true;
    _cache = null;
    if (_pending == 0) _release();
  }

  void _release() {
    if (_released) return;
    _released = true;
    _private.fillRange(0, _private.length, 0);
    _cache = null;
    if (closedByClient) _vault.close();
  }

  /// The keys of [atsign]'s document with the derived APKAM pair filed. The
  /// first read of a store that was not seeded goes to the atServer; every
  /// later one is served from memory, as keys the caller may change.
  @override
  Future<AtKeys> read(String atsign) async {
    _requireLive();
    var cache = _cache;
    if (cache == null) {
      final document = _stripped(await _decode(atsign, await _stored(atsign)));
      _requireLive();
      cache = _cache ??= jsonEncode(document);
    }
    return _withPair(jsonDecode(cache) as Map<String, dynamic>, atsign);
  }

  /// [document], a stripped document, as keys with the pair filed.
  ///
  /// The private key is encoded once per read, straight into the keys. That
  /// String is an immutable copy of the key that cannot be wiped (D-30).
  AtKeys _withPair(Map<String, dynamic> document, String atsign) {
    final keys = AtKeys.fromJson(document);
    keys.atsign ??= atsign.toAtsign();
    return withApkamKey(keys, _enrollmentId,
        (publicKey: _publicKey, privateKey: base64Encode(_private)));
  }

  @override
  Future<void> write(String atsign, AtKeys atKeys) =>
      _serialized(() => _write(atsign, atKeys));

  Future<void> _write(String atsign, AtKeys atKeys) async {
    _requireOpen();
    _requireOwnAtsign(atsign, atKeys);
    if (await _documents.get(atsign, _enrollmentId) != null) {
      throw AtKeysFileOverwriteException(
          'enrollment $_enrollmentId already has a @keys document; '
          'write only creates it');
    }
    await _putVerified(atsign, atKeys);
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) =>
      _serialized(() => _flush(atsign, atKeys));

  Future<void> _flush(Atsign atsign, AtKeys atKeys) async {
    _requireOpen();
    final name = atsign.toString();
    _requireOwnAtsign(name, atKeys);
    final existing = _stripped(await _decode(name, await _stored(name)));
    atKeys.atsign ??= atsign;
    try {
      assurance.validateMapUpdate(
          existing: existing, candidate: _document(atKeys), atsign: atsign);
    } on Object {
      _refused = true;
      rethrow;
    }
    await _putVerified(name, atKeys);
  }

  @override
  Future<void> update(
          Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) =>
      _serialized(() => _update(atsign, mutate));

  Future<void> _update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    _requireOpen();
    final name = atsign.toString();
    final keys =
        _withPair(_stripped(await _decode(name, await _stored(name))), name);
    if (await mutate(keys) == false) return;
    await _flush(atsign, keys);
  }

  /// Whether the stored document holds everything [atKeys] holds, so that
  /// filing [atKeys] would lose nothing. False when it drops any of it; the
  /// store stays usable either way. Throws when there is no document or it
  /// cannot be opened.
  Future<bool> keepsAllOf(String atsign, AtKeys atKeys) async {
    _requireLive();
    final stored = await _decode(atsign, await _stored(atsign));
    atKeys.atsign ??= atsign.toAtsign();
    try {
      assurance.validateMapUpdate(
          existing: _stripped(atKeys),
          candidate: _stripped(stored),
          atsign: atsign.toAtsign());
      return true;
    } on AtKeysAssuranceException {
      return false;
    }
  }

  Future<String> _stored(String atsign) async =>
      await _documents.get(atsign, _enrollmentId) ??
      (throw MissingAtKeysDocumentException(_enrollmentId));

  Future<AtKeys> _decode(String atsign, String document) async {
    final keys =
        AtKeys.fromJson(await _vault.open(PasskeyRecordType.atkeys, document));
    keys.atsign ??= atsign.toAtsign();
    return keys;
  }

  /// [keys] as the document this store holds: always versioned and naming its
  /// atSign, so what is read back is the keys written, atSign included, and
  /// without the APKAM private key or the pair's public half.
  ///
  /// Never strips private authentication material that is not the pair, in
  /// whatever status: that refuses, and the store accepts no more writes.
  Map<String, dynamic> _document(AtKeys keys) {
    if (_holdsForeignPrivateKey(keys)) {
      _refused = true;
      throw AtServerAtKeysWriteException(
          'enrollment $_enrollmentId: the keys hold private authentication '
          'material other than this enrollment\'s own, which this store does '
          'not file');
    }
    return _stripped(keys);
  }

  /// Whether [keys] hold an APKAM private key, flat or typed in any status,
  /// other than the pair this store was given.
  bool _holdsForeignPrivateKey(AtKeys keys) {
    final json = keys.toJson();
    final flat = json[apkamPrivateKey];
    if (flat != null && !_isOwnPrivateKey(flat)) return true;
    final enrollments = json['enrollments'];
    if (enrollments is! List) return false;
    for (final e in enrollments) {
      for (final key in (e as Map)['keys'] as List) {
        for (final m in (key as Map)['material'] as List) {
          if (m['role'] == 'privateAuthentication' &&
              !_isOwnPrivateKey(m['bytes'])) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Whether [encoded] is the base64 of the pair's private key. Compares the
  /// decoded bytes, so no String copy of the pair's key is made; the decoded
  /// candidate is zeroed.
  bool _isOwnPrivateKey(Object? encoded) {
    if (encoded is! String) return false;
    final Uint8List candidate;
    try {
      candidate = base64Decode(encoded);
    } on FormatException {
      return false;
    }
    try {
      if (candidate.length != _private.length) return false;
      var diff = 0;
      for (var i = 0; i < candidate.length; i++) {
        diff |= candidate[i] ^ _private[i];
      }
      return diff == 0;
    } finally {
      candidate.fillRange(0, candidate.length, 0);
    }
  }

  /// [keys] as a document without any APKAM private key and without this
  /// enrollment's public authentication key (the read overlay files the
  /// pair's, and a second one would make the keys refuse), and without the empty groups
  /// that leaves, so that stripping a stripped document changes nothing.
  Map<String, dynamic> _stripped(AtKeys keys) {
    final atsign = keys.atsign.toString();
    final json = atKeysDocument(keys, atsign);
    final enrollments = json['enrollments'];
    if (enrollments is List) {
      final kept = <Map<String, dynamic>>[];
      for (final e in enrollments) {
        final enrollment = e as Map<String, dynamic>;
        final own = enrollment['enrollmentId'] == _enrollmentId;
        final groups = <Map<String, dynamic>>[];
        for (final key in enrollment['keys'] as List) {
          final material = [
            for (final m in (key as Map<String, dynamic>)['material'] as List)
              if (!(own && (m as Map)['role'] == 'publicAuthentication')) m
          ];
          if (material.isNotEmpty) groups.add({...key, 'material': material});
        }
        if (groups.isNotEmpty) kept.add({...enrollment, 'keys': groups});
      }
      if (kept.isEmpty) {
        json.remove('enrollments');
      } else {
        json['enrollments'] = kept;
      }
    }
    return {
      ...json,
      'version': AtKeys.supportedVersion,
      'atsign': atsign,
      'keys': <Object?>[],
    };
  }

  /// Refuses [keys] that name an atSign other than [atsign], before anything
  /// is read or written. The store stays usable: nothing was touched.
  void _requireOwnAtsign(String atsign, AtKeys keys) {
    final named = keys.atsign;
    if (named != null && named != atsign.toAtsign()) {
      throw AtServerAtKeysWriteException(
          'enrollment $_enrollmentId: the keys belong to another atSign than '
          'the one being written');
    }
  }

  void _requireLive() {
    if (_closed) throw StateError('this key store is closed');
  }

  /// Refuses once a write was refused. Closure is checked where a call leaves
  /// the queue, so a body already running is never cut off by [close].
  void _requireOpen() {
    if (_refused) {
      throw AtServerAtKeysWriteException(
          'enrollment $_enrollmentId: an earlier write was refused, so no '
          'further write is accepted');
    }
  }

  /// Seals and puts [atKeys], then reads the document back and compares it.
  Future<void> _putVerified(String atsign, AtKeys atKeys) async {
    atKeys.atsign ??= atsign.toAtsign();
    final written = _document(atKeys);
    await _documents.put(atsign, _enrollmentId,
        await _vault.seal(PasskeyRecordType.atkeys, written));
    final stored = await _documents.get(atsign, _enrollmentId);
    AtKeys? back;
    try {
      back = stored == null ? null : await _decode(atsign, stored);
    } on Object {
      _refused = true;
      throw AtServerAtKeysWriteException(
          'enrollment $_enrollmentId: the document read back could not be '
          'opened');
    }
    if (back == null || jsonEncode(_stripped(back)) != jsonEncode(written)) {
      _refused = true;
      throw AtServerAtKeysWriteException(
          'enrollment $_enrollmentId: the document read back differs from '
          'the one written');
    }
    if (!_closed) _cache = jsonEncode(written);
  }
}
