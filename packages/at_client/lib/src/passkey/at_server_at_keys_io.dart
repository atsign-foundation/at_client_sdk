import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/src/client/server_mutex.dart';
import 'package:at_commons/at_commons.dart' show AtException;
import 'package:at_commons/atsign.dart';
import 'package:meta/meta.dart' show visibleForTesting;

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

/// Thrown when a write could not take the enrollment's @keys lock within the
/// store's bound, or kept losing it before the put. Nothing was put, and the
/// store stays usable.
class AtServerAtKeysLockedException extends AtServerAtKeysWriteException {
  AtServerAtKeysLockedException(super.message);

  @override
  String toString() => 'AtServerAtKeysLockedException: $message';
}

/// An enrollment's @keys, held as one sealed document on the atServer.
///
/// [write] creates the document and refuses when one exists. [flush] and
/// [update] replace it: each re-reads the stored document just before writing
/// and refuses a candidate that drops anything stored; they then write, read
/// the document back and compare it with what was written. [flush] creates
/// the document when there is none; [update] never does. Nothing is merged
/// and no put is retried.
///
/// Three refusals stop the store, after which it accepts no more writes: a
/// candidate that drops stored material, a candidate holding private
/// authentication material other than the pair, and a read-back that is
/// absent, cannot be opened or differs from what was written. Any other
/// failure leaves it usable: a document that already exists for [write],
/// keys or an atSign other than the store's, a closed store, a lock it could
/// not take or keep, and a lock take, get or put that throws.
///
/// Writes on one instance run one at a time: [write], [flush] and [update]
/// each run whole, from the lock to the read back, before the next starts, so
/// overlapping calls queue instead of interleaving, and a call that throws
/// does not stop the ones queued behind it.
///
/// Several writers may share an enrollment, so every write holds the
/// enrollment's lock on the atServer, taken through
/// [EnrollmentDocumentStore.tryLock], from before it reads the stored document
/// until it puts. A writer that finds the lock held tries again after a pause
/// of a quarter to one second, chosen at random, until it takes it or its wait
/// bound runs out, which throws [AtServerAtKeysLockedException]. When its own
/// last lease is too short to reuse, it first waits until the atServer has let
/// that lock go: what is left of the lease, under half the ttl, plus the time
/// its take took to be answered. The bound starts after that. A put needs at
/// least half the lock's ttl left on its lease, measured by the lease's own
/// stopwatch, and a lease serves this store's later writes only while that much
/// is left. When less is left by the time the document is sealed, nothing is
/// put: the write takes the lock again and starts over from a fresh read,
/// running an [update]'s mutate again, with at most three leases in all. Every
/// [update] builds its candidate on the document it read under the lock, so it
/// keeps what another writer filed. The lock is not a fence: the margin leaves
/// a put half the ttl to land, but one sent within it can still land after the
/// lock expired, so a write that would drop stored material is still refused,
/// and each write is read back and compared with what was written.
///
/// The lock needs an atServer from p3.13.0, the first to parse `:nc`. An
/// expired lock stops blocking at once from p3.16.5. Another enrollment of
/// the atSign cannot create or delete the lock record from p3.15.0, and a
/// connection with the atSign's legacy keys cannot from p3.19.0.
///
/// The document never holds the enrollment's APKAM private key: a passkey
/// enrollment derives the pair from the passkey and the atServer must not
/// keep it. This store is given that derived pair instead. Every document it
/// seals is stripped of the flat APKAM private key, every typed
/// `privateAuthentication` material and the pair's own public half, so what is
/// read back and compared is the stripped form. A candidate that holds active
/// private authentication material other than the pair (a rotation, a
/// retrofit) is refused with [AtServerAtKeysWriteException], never stripped
/// silently.
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
///
/// The store holds [atSign]'s document only: every call naming another atSign
/// throws [ArgumentError].
///
/// The store seals and opens through the two functions it is given, and
/// reaches nothing else of whatever holds the sealing key.
class AtServerAtKeysIo extends WrittenAtKeysIo {
  /// The store of [enrollmentId]'s document for [atSign] through [documents],
  /// sealed by [seal] and opened by [open], holding [apkamKeyPair]; a
  /// [restored] document is served by [read] without I/O. Each take of the
  /// lock lasts [lockTtl], and a write waits up to [lockWait] to take it,
  /// counted from when the atServer has let this store's own last lock go.
  ///
  /// Throws [ArgumentError] for a [lockTtl] under a millisecond or over
  /// [maxServerMutexTtl], or a [lockWait] that is not positive.
  AtServerAtKeysIo(
      {required EnrollmentDocumentStore documents,
      required String atSign,
      required Future<String> Function(Map<String, dynamic> document) seal,
      required Future<Map<String, dynamic>> Function(String record) open,
      required String enrollmentId,
      required ApkamKeyPair apkamKeyPair,
      AtKeys? restored,
      Duration lockTtl = const Duration(seconds: 10),
      Duration lockWait = const Duration(seconds: 15)})
      : _documents = documents,
        _atSign = atSign.toAtsign(),
        _seal = seal,
        _open = open,
        _enrollmentId = enrollmentId,
        _lockTtl = checkedServerMutexTtl(lockTtl, 'lockTtl'),
        _lockWait = lockWait > Duration.zero
            ? lockWait
            : throw ArgumentError.value(
                lockWait, 'lockWait', 'must be positive'),
        _publicKey = apkamKeyPair.publicKey,
        _private = base64Decode(apkamKeyPair.privateKey) {
    final seed = restored;
    if (seed != null && seed.atsign != null) {
      _requireStoreAtsign(seed.atsign.toString());
      _cache = jsonEncode(_stripped(seed));
    }
  }

  final EnrollmentDocumentStore _documents;
  final Atsign _atSign;
  final Future<String> Function(Map<String, dynamic> document) _seal;
  final Future<Map<String, dynamic>> Function(String record) _open;
  final String _enrollmentId;
  final String _publicKey;
  final Duration _lockTtl;
  final Duration _lockWait;
  final _random = Random();

  /// How many leases one write may take before it gives up.
  static const _leaseTakes = 3;

  /// The lease on the enrollment's lock this store last took.
  ServerMutexLease? _lease;

  /// How long the take of [_lease] took to be answered. The atServer made
  /// the lock record within that time, so the record outlives the lease by
  /// at most this much.
  Duration _leaseTook = Duration.zero;

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
  /// finishes whole, with the pair still held: [close] zeroes it only when the
  /// last call on the chain has settled.
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

  /// Completes when every write queued on this store so far has ended,
  /// whether it succeeded or failed. Never fails.
  Future<void> get settled => _tail;

  /// Zeroes the APKAM private key this store holds. Idempotent. A later read
  /// throws [StateError]; a later or queued write, flush or update throws
  /// [AtServerAtKeysWriteException] without touching the atServer.
  ///
  /// A write already running is not cut off: it finishes, and the key is
  /// zeroed right after it. Never waits, so a write that hangs cannot hold a
  /// stop; it holds the key in memory until it settles.
  void close() {
    _closed = true;
    _cache = null;
    if (_pending == 0) _release();
  }

  /// Whether any byte of the APKAM private key this store holds is non-zero.
  /// Reveals nothing about the key; tests use it to observe that [close]
  /// wipes it.
  @visibleForTesting
  bool get holdsPrivateKey => _private.any((b) => b != 0);

  void _release() {
    if (_released) return;
    _released = true;
    _private.fillRange(0, _private.length, 0);
    _cache = null;
  }

  /// The keys of [atsign]'s document with the derived APKAM pair filed. The
  /// first read of a store that was not seeded goes to the atServer; every
  /// later one is served from memory, as keys the caller may change.
  @override
  Future<AtKeys> read(String atsign) async {
    _requireStoreAtsign(atsign);
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
  /// String is an immutable copy of the key that cannot be wiped.
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
    _requireStoreAtsign(atsign);
    _requireOpen();
    _requireOwnAtsign(atsign, atKeys);
    atKeys.atsign ??= atsign.toAtsign();
    await _putLocked(atsign, () async {
      if (await _documents.get(atsign, _enrollmentId) != null) {
        throw AtKeysFileOverwriteException(
            'enrollment $_enrollmentId already has a @keys document; '
            'write only creates it');
      }
      return _document(atKeys);
    });
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) =>
      _serialized(() => _flush(atsign, atKeys));

  Future<void> _flush(Atsign atsign, AtKeys atKeys) async {
    final name = atsign.toString();
    _requireStoreAtsign(name);
    _requireOpen();
    _requireOwnAtsign(name, atKeys);
    atKeys.atsign ??= atsign;
    await _putLocked(name, () => _replacing(atsign, atKeys));
  }

  /// [atKeys] as the document to put in place of the stored one, refused when
  /// it drops anything stored.
  Future<Map<String, dynamic>> _replacing(Atsign atsign, AtKeys atKeys) async {
    final name = atsign.toString();
    final stored = await _documents.get(name, _enrollmentId);
    if (stored != null) {
      final existing = _stripped(await _decode(name, stored));
      try {
        assurance.validateMapUpdate(
            existing: existing, candidate: _document(atKeys), atsign: atsign);
      } on Object {
        _refused = true;
        rethrow;
      }
    }
    return _document(atKeys);
  }

  @override
  Future<void> update(
          Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) =>
      _serialized(() => _update(atsign, mutate));

  Future<void> _update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    final name = atsign.toString();
    _requireStoreAtsign(name);
    _requireOpen();
    await _putLocked(name, () async {
      final keys =
          _withPair(_stripped(await _decode(name, await _stored(name))), name);
      if (await mutate(keys) == false) return null;
      _requireOwnAtsign(name, keys);
      keys.atsign ??= atsign;
      return _replacing(atsign, keys);
    });
  }

  /// Whether the stored document holds everything [atKeys] holds. False when
  /// [atKeys] holds anything the stored document lacks; the store stays
  /// usable either way. Throws when there is no document or it cannot be
  /// opened.
  Future<bool> keepsAllOf(String atsign, AtKeys atKeys) async {
    _requireStoreAtsign(atsign);
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
    final keys = AtKeys.fromJson(await _open(document));
    keys.atsign ??= atsign.toAtsign();
    return keys;
  }

  /// [keys] as the document this store holds: always versioned and naming its
  /// atSign, so what is read back is the keys written, atSign included, and
  /// without the APKAM private key or the pair's public half.
  ///
  /// Never strips private authentication material that is not the pair: that
  /// refuses, and stops the store.
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

  /// Whether [keys] hold an APKAM private key, flat or active typed, other
  /// than the pair this store was given.
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
              m['status'] == 'active' &&
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
  /// pair's, and a second one would make the keys refuse), and without the
  /// empty key groups that leaves. Every enrollment entry is kept, with its
  /// namespaces, app and device names, even with no keys left, and the entries
  /// are ordered by enrollment id, so that stripping a stripped document, or
  /// one parsed back, changes nothing.
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
        kept.add({...enrollment, 'keys': groups});
      }
      kept.sort((a, b) =>
          (a['enrollmentId'] as String).compareTo(b['enrollmentId'] as String));
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

  /// Refuses [atsign] when it is not the atSign whose document this store
  /// holds. The store stays usable.
  void _requireStoreAtsign(String atsign) {
    if (atsign.toAtsign() != _atSign) {
      throw ArgumentError.value(atsign, 'atsign',
          'this key store holds the document of $_atSign only');
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

  /// Under a lease on the enrollment's lock, builds the document with
  /// [candidate], seals it and, while the lease leaves enough for a put, puts
  /// it and reads it back. A null candidate puts nothing.
  ///
  /// When the lease leaves too little by the time the document is sealed,
  /// puts nothing and starts again from a new lease, up to [_leaseTakes]
  /// leases.
  Future<void> _putLocked(
      String atsign, Future<Map<String, dynamic>?> Function() candidate) async {
    for (var takes = 1;; takes++) {
      final lease = await _leased(atsign);
      final written = await candidate();
      if (written == null) return;
      final sealed = await _seal(written);
      if (_leaves(lease)) {
        await _documents.put(atsign, _enrollmentId, sealed);
        return _verify(atsign, written);
      }
      if (takes == _leaseTakes) {
        throw AtServerAtKeysLockedException(
            'enrollment $_enrollmentId: the @keys lock '
            '${enrollmentLockKey(_enrollmentId, atsign)} had less than half '
            'its ttl left when the document was ready to put, $takes times, '
            'so nothing was put');
      }
    }
  }

  /// Whether [lease] has at least half the lock's ttl left, enough for a put.
  bool _leaves(ServerMutexLease lease) => lease.remaining >= _lockTtl ~/ 2;

  /// The lease this store holds while it leaves enough for a put, or a new
  /// one, taken once the atServer has let that lease's lock go and as soon as
  /// no other writer holds the lock, within [_lockWait] of that.
  Future<ServerMutexLease> _leased(String atsign) async {
    final held = _lease;
    if (held != null) {
      if (_leaves(held)) return held;
      await Future<void>.delayed(held.remaining + _leaseTook);
    }
    final waited = Stopwatch()..start();
    while (true) {
      final took = Stopwatch()..start();
      final lease =
          await _documents.tryLock(atsign, _enrollmentId, ttl: _lockTtl);
      if (lease != null) {
        _leaseTook = took.elapsed;
        return _lease = lease;
      }
      final left = _lockWait - waited.elapsed;
      if (left <= Duration.zero) {
        throw AtServerAtKeysLockedException(
            'enrollment $_enrollmentId: the @keys lock '
            '${enrollmentLockKey(_enrollmentId, atsign)} stayed held for '
            '$_lockWait, so nothing was put');
      }
      final pause = Duration(milliseconds: 250 + _random.nextInt(751));
      await Future<void>.delayed(pause < left ? pause : left);
    }
  }

  /// Reads back the document [written] was put as, and compares it.
  Future<void> _verify(String atsign, Map<String, dynamic> written) async {
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
