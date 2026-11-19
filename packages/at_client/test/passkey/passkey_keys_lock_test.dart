import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show ApkamKeyPair, apkamKeyPairFromSeed;
import 'package:mocktail/mocktail.dart' show Fake, Mock;
import 'package:test/test.dart';

import '../support/custody_fakes.dart' show DerivedKeys;
import '../test_utils/recorded_logs.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';

String _b(String s) => base64Encode(utf8.encode(s));

/// An atServer holding one enrollment's document and the lock on it. A
/// create of the lock is refused while the last one is within its ttl, as
/// the create of an immutable record with a ttl is. Every command is logged
/// with the writer that sent it.
class _AtServer {
  String? document;
  DateTime? _lockedUntil;

  /// Every command, as `<writer> <command>`.
  final events = <String>[];

  /// Called with each event as it is logged.
  void Function(String event)? onEvent;

  /// Makes the next document put wait for it, signalling [putArrived].
  Completer<void>? holdPut;
  final putArrived = Completer<void>();

  /// Refuses every create of the lock, whatever its ttl.
  var lockHeld = false;

  /// Accepts puts without storing them.
  var dropPuts = false;

  /// Builds the lease a granted create returns.
  ServerMutexLease Function(AtKey key, Duration ttl) leaseOf =
      (key, ttl) => ServerMutexLease(key, DateTime.now().add(ttl));

  void log(String event) {
    events.add(event);
    onEvent?.call(event);
  }

  /// What [writer] sent, in order, without the writer's name.
  List<String> of(String writer) => [
        for (final e in events)
          if (e.startsWith('$writer ')) e.substring(writer.length + 1)
      ];
}

/// One writer's authenticated connection to an [_AtServer].
class _Connection implements EnrollmentDocumentStore {
  _Connection(this.server, this.writer);

  final _AtServer server;
  final String writer;

  @override
  Future<String?> get(String atSign, String enrollmentId) async {
    server.log('$writer get');
    await Future<void>.delayed(Duration.zero);
    return server.document;
  }

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    server.log('$writer put');
    final hold = server.holdPut;
    if (hold != null) {
      server.holdPut = null;
      server.putArrived.complete();
      await hold.future;
    }
    if (!server.dropPuts) server.document = document;
  }

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
      {required Duration ttl}) async {
    final now = DateTime.now();
    final until = server._lockedUntil;
    if (server.lockHeld || (until != null && now.isBefore(until))) {
      server.log('$writer lock refused');
      return null;
    }
    server._lockedUntil = now.add(ttl);
    server.log('$writer lock');
    return server.leaseOf(
        AtKey.fromString(enrollmentLockKey(enrollmentId, atSign)), ttl);
  }
}

/// A stopwatch that reads the elapsed time the test sets.
class _Clock extends Fake implements Stopwatch {
  @override
  Duration elapsed = Duration.zero;
}

/// A client the signing root holds and never calls while it files a private.
class _Client extends Mock implements AtClient {}

void main() {
  late _AtServer server;
  late DerivedKeys derived;
  late ApkamKeyPair pair;
  final logs = RecordedLogs();

  setUpAll(() async {
    logs.installOn();
    pair = await apkamKeyPairFromSeed(
        Uint8List.fromList(List.generate(32, (i) => i + 100)));
  });

  setUp(() async {
    server = _AtServer();
    derived = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
    final base = AtKeys.legacy(
        apkamPublicKey: _b('apkam-pub'),
        encryptionPublicKey: _b('enc-pub'),
        encryptionPrivateKey: _b('enc-priv'),
        selfEncryptionKey: _b('self-1'))
      ..atsign = _atSign.toAtsign();
    server.document =
        await derived.vault.seal(PasskeyRecordType.atkeys, base.toJson());
  });

  tearDown(() => derived.vault.close());

  AtServerAtKeysIo storeOf(String writer,
          {Duration lockTtl = const Duration(seconds: 1),
          Duration lockWait = const Duration(seconds: 5)}) =>
      AtServerAtKeysIo(
          documents: _Connection(server, writer),
          atSign: _atSign,
          seal: (d) => derived.vault.seal(PasskeyRecordType.atkeys, d),
          open: (r) => derived.vault.open(PasskeyRecordType.atkeys, r),
          enrollmentId: _eid,
          apkamKeyPair: pair,
          lockTtl: lockTtl,
          lockWait: lockWait);

  Future<void> addSymmetric(AtServerAtKeysIo io) =>
      io.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: _b('sym-a'));
        return true;
      });

  Future<void> addSigning(AtServerAtKeysIo io) =>
      io.update(_atSign.toAtsign(), (keys) {
        keys.fileSigningMaterial(
            enrollmentId: 'e9z9z9',
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: _b('sign-pub'),
            privateKey: _b('sign-priv'));
        return true;
      });

  Future<AtKeys> stored() async => AtKeys.fromJson(
      await derived.vault.open(PasskeyRecordType.atkeys, server.document!));

  test(
      'A write that finds the lock held waits, re-reads and keeps the other '
      'writer\'s change', () async {
    final hold = server.holdPut = Completer<void>();
    final otherWrite = addSymmetric(storeOf('other'));
    await server.putArrived.future;
    final selfActed = Completer<void>();
    server.onEvent = (e) {
      if (e.startsWith('self ') && !selfActed.isCompleted) selfActed.complete();
    };

    final selfWrite = addSigning(storeOf('self'));
    await selfActed.future;
    hold.complete();
    await Future.wait([otherWrite, selfWrite]);

    final self = server.of('self');
    final taken = self.indexOf('lock');
    expect(self.first, 'lock refused');
    expect(taken, greaterThan(0));
    expect(self.indexOf('put'), greaterThan(taken),
        reason: 'it writes only once it has taken the lock');
    expect(self.indexOf('get'), greaterThan(taken),
        reason: 'it reads the document after taking the lock');
    final document = await stored();
    expect(document.enrollmentSymmetricKey, isNotNull);
    expect(jsonEncode(document.toJson()), contains(_b('sign-priv')));
  });

  test(
      'A writer whose lock runs out before it puts takes the lock again and '
      're-reads', () async {
    final clocks = <_Clock>[];
    server.leaseOf = (key, ttl) {
      final clock = _Clock();
      clocks.add(clock);
      return ServerMutexLease.timed(key, DateTime.now().add(ttl), clock, ttl);
    };
    final io = storeOf('self', lockTtl: const Duration(milliseconds: 200));
    server.onEvent = (e) {
      if (e == 'self get' && clocks.length == 1) {
        clocks.single.elapsed = const Duration(milliseconds: 200);
      }
    };

    await addSymmetric(io);

    final self = server.of('self');
    final first = self.indexOf('lock');
    final second = self.indexOf('lock', first + 1);
    expect(second, greaterThan(first), reason: 'it takes the lock again');
    expect(self.sublist(first, second), isNot(contains('put')),
        reason: 'it puts nothing on the lease that ran out');
    final put = self.indexOf('put');
    expect(put, greaterThan(second));
    expect(self.sublist(second, put), contains('get'),
        reason: 'it re-reads the document before it puts');
    expect(clocks, hasLength(2));
    expect((await stored()).enrollmentSymmetricKey, isNotNull);
  });

  test(
      'A writer that cannot take the lock within its bound fails without '
      'writing', () async {
    server.lockHeld = true;
    final io = storeOf('self', lockWait: const Duration(milliseconds: 600));

    await expectLater(
        addSymmetric(io),
        throwsA(isA<AtServerAtKeysLockedException>().having((e) => e.message,
            'message', contains('atkeys-lock.$_eid.a.__e$_atSign'))));
    expect(server.of('self'), everyElement('lock refused'),
        reason: 'nothing was read or put');

    server.lockHeld = false;
    await addSymmetric(io);
    expect((await stored()).enrollmentSymmetricKey, isNotNull,
        reason: 'the store accepts a later write');
  });

  test(
      'a writer whose bound is shorter than a pause between takes gives up '
      'when its bound ends', () async {
    server.lockHeld = true;
    final io = storeOf('self', lockWait: const Duration(milliseconds: 50));
    final took = Stopwatch()..start();

    await expectLater(
        addSymmetric(io), throwsA(isA<AtServerAtKeysLockedException>()));

    expect(took.elapsed, lessThan(const Duration(milliseconds: 250)),
        reason: 'the last pause is cut to what is left of the bound, and a '
            'pause between takes is at least 250ms');
  });

  test('A writer waits out its own last lease before its bound starts',
      () async {
    final clocks = <_Clock>[];
    server.leaseOf = (key, ttl) {
      final clock = _Clock();
      clocks.add(clock);
      return ServerMutexLease.timed(key, DateTime.now().add(ttl), clock, ttl);
    };
    final io = storeOf('self', lockWait: const Duration(milliseconds: 50));
    await addSymmetric(io);
    const left = Duration(milliseconds: 300);
    clocks.single.elapsed = const Duration(seconds: 1) - left;
    server._lockedUntil = DateTime.now().add(left);

    await addSigning(io);

    expect(server.events.where((e) => !e.startsWith('self ')), isEmpty,
        reason: 'no other writer held the lock');
    expect(server.of('self').where((e) => e == 'lock'), hasLength(2),
        reason: 'it took the lock again rather than reuse the short lease');
    expect(jsonEncode((await stored()).toJson()), contains(_b('sign-priv')));
  });

  test('A write whose read-back differs stops the store', () async {
    final io = storeOf('self');
    server.dropPuts = true;
    await expectLater(
        addSymmetric(io), throwsA(isA<AtServerAtKeysWriteException>()));
    server.dropPuts = false;
    final sent = server.events.length;

    await expectLater(
        addSigning(io), throwsA(isA<AtServerAtKeysWriteException>()));

    expect(server.events.sublist(sent), isEmpty,
        reason: 'refused before anything is read or put');
  });

  test(
      'a write whose every lease runs out before its put gives up after '
      'three, putting nothing', () async {
    server.leaseOf = (key, ttl) => ServerMutexLease.timed(
        key, DateTime.now().add(ttl), _Clock()..elapsed = ttl, ttl);
    final io = storeOf('self', lockTtl: const Duration(milliseconds: 50));

    await expectLater(
        addSymmetric(io), throwsA(isA<AtServerAtKeysLockedException>()));

    expect(server.of('self').where((e) => e == 'lock'), hasLength(3));
    expect(server.of('self'), isNot(contains('put')));
    server.leaseOf =
        (key, ttl) => ServerMutexLease(key, DateTime.now().add(ttl));
    await addSymmetric(io);
    expect((await stored()).enrollmentSymmetricKey, isNotNull,
        reason: 'the store accepts a later write');
  });

  test(
      'a signing root filed while its lease runs out logs each retirement '
      'once', () async {
    final held = [
      for (var i = 1; i <= 2; i++)
        '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}$i'
    ];
    final seeded = (await stored())..atsign = _atSign.toAtsign();
    for (final slot in held) {
      seeded.addKey(CryptographicMaterial(
          keyId: slot,
          role: CryptographicMaterialRole.privateSigning,
          algorithm: PqSigningRoot.rootKeyAlgoToken,
          bytes: AtBytes(Uint8List.fromList(utf8.encode('held $slot'))),
          createdAt: DateTime.now().toUtc()));
    }
    server.document =
        await derived.vault.seal(PasskeyRecordType.atkeys, seeded.toJson());
    final clocks = <_Clock>[];
    server.leaseOf = (key, ttl) {
      final clock = _Clock();
      clocks.add(clock);
      return ServerMutexLease.timed(key, DateTime.now().add(ttl), clock, ttl);
    };
    server.onEvent = (e) {
      if (e == 'self get' && clocks.length == 1) {
        clocks.single.elapsed = const Duration(milliseconds: 200);
      }
    };
    final root = PqSigningRoot(_Client(),
        keysIo: storeOf('self', lockTtl: const Duration(milliseconds: 200)));
    logs.records.clear();

    expect(
        await root.store(_atSign, Uint8List.fromList(utf8.encode('fresh')),
            heldCorrespondence: const {}),
        isTrue);

    expect(server.of('self').where((e) => e == 'lock'), hasLength(2),
        reason: 'the lease ran out once, so the update ran twice');
    for (final slot in held) {
      expect(
          logs.records.where((r) => r.message
              .startsWith('Retired the signing root private in $slot for')),
          hasLength(1),
          reason: slot);
    }
  });

  test('a lease with under half its ttl left is not used for a put', () async {
    final clocks = <_Clock>[];
    server.leaseOf = (key, ttl) {
      final clock = _Clock();
      clocks.add(clock);
      return ServerMutexLease.timed(key, DateTime.now().add(ttl), clock, ttl);
    };
    final io = storeOf('self');
    server.onEvent = (e) {
      if (e == 'self get' && clocks.length == 1) {
        clocks.single.elapsed = const Duration(milliseconds: 501);
      }
    };

    await addSymmetric(io);

    final self = server.of('self');
    final first = self.indexOf('lock');
    final second = self.indexOf('lock', first + 1);
    expect(second, greaterThan(first),
        reason: 'a lease with under half its ttl left is not used for a put');
    expect(self.sublist(first, second), isNot(contains('put')));
    final put = self.indexOf('put');
    expect(put, greaterThan(second));
    expect(self.sublist(second, put), contains('get'),
        reason: 'it re-reads the document before it puts');
    expect((await stored()).enrollmentSymmetricKey, isNotNull);
  });

  group('a lease that served a write', () {
    late List<_Clock> clocks;
    late AtServerAtKeysIo io;

    setUp(() async {
      clocks = <_Clock>[];
      server.leaseOf = (key, ttl) {
        final clock = _Clock();
        clocks.add(clock);
        return ServerMutexLease.timed(key, DateTime.now().add(ttl), clock, ttl);
      };
      io = storeOf('self');
      await addSymmetric(io);
    });

    test('with half its ttl left serves the next write', () async {
      clocks.single.elapsed = const Duration(milliseconds: 500);
      await addSigning(io);
      expect(
          server.of('self').where((e) => e.startsWith('lock')), hasLength(1));
    });

    test('with under half its ttl left is not reused for the next write',
        () async {
      clocks.single.elapsed = const Duration(milliseconds: 501);
      await addSigning(io);
      final self = server.of('self');
      final secondPut = self.lastIndexOf('put');
      expect(self.sublist(self.indexOf('put') + 1, secondPut), contains('lock'),
          reason: 'a lease with under half its ttl left is not reused');
      expect(clocks, hasLength(2));
    });
  });

  test('a lease serves the writes that follow it while it lasts', () async {
    final io = storeOf('self', lockTtl: const Duration(seconds: 10));
    await addSymmetric(io);
    await addSigning(io);
    expect(server.of('self').where((e) => e == 'lock'), hasLength(1));
  });

  test('a lock take that throws fails the write and leaves the store usable',
      () async {
    final io = AtServerAtKeysIo(
        documents: _Throwing(_Connection(server, 'self')),
        atSign: _atSign,
        seal: (d) => derived.vault.seal(PasskeyRecordType.atkeys, d),
        open: (r) => derived.vault.open(PasskeyRecordType.atkeys, r),
        enrollmentId: _eid,
        apkamKeyPair: pair);

    await expectLater(addSymmetric(io), throwsA(isA<AtException>()));
    expect(server.events, isEmpty);
    await addSigning(io);
    expect(jsonEncode((await stored()).toJson()), contains(_b('sign-priv')));
  });
}

/// A connection whose first lock take throws, as a lost connection does.
class _Throwing implements EnrollmentDocumentStore {
  _Throwing(this._inner);

  final EnrollmentDocumentStore _inner;
  var _thrown = false;

  @override
  Future<String?> get(String atSign, String enrollmentId) =>
      _inner.get(atSign, enrollmentId);

  @override
  Future<void> put(String atSign, String enrollmentId, String document) =>
      _inner.put(atSign, enrollmentId, document);

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String enrollmentId,
      {required Duration ttl}) async {
    if (!_thrown) {
      _thrown = true;
      throw AtException('connection lost');
    }
    return _inner.tryLock(atSign, enrollmentId, ttl: ttl);
  }
}
