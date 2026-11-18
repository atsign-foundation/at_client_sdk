import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:mocktail/mocktail.dart' show Fake;
import 'package:test/test.dart';

import '../support/custody_fakes.dart' show DerivedKeys;

const _atSign = '@alice';
const _eid = 'eid1';

/// Documents in memory; a put waits for [hold] when one is set.
class _Docs implements EnrollmentDocumentStore {
  final records = <String, String>{};
  Completer<void>? hold;

  @override
  Future<String?> get(String atSign, String enrollmentId) async =>
      records[enrollmentId];

  @override
  Future<void> put(String atSign, String enrollmentId, String document) async {
    await hold?.future;
    records[enrollmentId] = document;
  }
}

/// A client whose stop, shared by every caller as a real client's is, reports
/// `stopped` on its connection and then runs [onStop]. With [stopError] set
/// its stop throws that at once, before reporting anything, as an app's own
/// client may.
class _Client extends Fake implements AtClient {
  @override
  final connection = AtConnection(
      atSign: _atSign, attempt: (_) async => AtConnectionState.online());

  /// How many stops ran.
  var stops = 0;
  Future<void> Function()? onStop;
  Object? stopError;
  Future<void>? _stopping;

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    stops++;
    if (stopError case final e?) throw e;
    await connection.close();
    await onStop?.call();
  }
}

/// A store that counts its closes.
class _Store extends AtServerAtKeysIo {
  _Store(
      {required super.documents,
      required super.vault,
      required super.enrollmentId,
      required super.apkamKeyPair});

  var closes = 0;

  @override
  void close() {
    closes++;
    super.close();
  }
}

/// One passkey's vault, a store over it holding a document, and a client.
class _Rig {
  _Rig._(this.vault, this.heldSeed, this.docs, this.store);

  static Future<_Rig> build() async {
    final vault = (await DerivedKeys.derive(
            Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign))
        .vault;
    final pair = await vault.withAuthSeed(apkamKeyPairFromSeed);
    late Uint8List heldSeed;
    await vault.withAuthSeed((seed) async => heldSeed = seed);
    final docs = _Docs();
    final store = _Store(
        documents: docs, vault: vault, enrollmentId: _eid, apkamKeyPair: pair);
    await store.write(
        _atSign,
        AtKeys.legacy(
            encryptionPublicKey: 'ZW5jLXB1Yg==',
            encryptionPrivateKey: 'ZW5jLXByaXY=',
            selfEncryptionKey: 'c2VsZg==')
          ..atsign = _atSign.toAtsign());
    return _Rig._(vault, heldSeed, docs, store);
  }

  final PasskeyVault vault;

  /// The vault's auth seed itself, which closing the vault zeroes.
  final Uint8List heldSeed;
  final _Docs docs;
  final _Store store;
  final client = _Client();

  /// An update of the document, which waits on [docs]' hold when one is set.
  Future<void> update() => store.update(_atSign.toAtsign(), (keys) {
        keys.fileLegacyMaterial(apkamSymmetricKey: 'c3ltbWV0cmlj');
        return true;
      });

  Future<bool> vaultOpen() async {
    try {
      await vault.seal(PasskeyRecordType.atkeys, {'a': 1});
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> expectVaultClosed() async {
    await expectLater(
        vault.seal(PasskeyRecordType.atkeys, {'a': 1}), throwsStateError);
    await expectLater(
        vault.open(PasskeyRecordType.atkeys, '{}'), throwsStateError);
    expect(heldSeed.every((b) => b == 0), isTrue, reason: 'seed zeroed');
  }
}

void main() {
  late _Rig rig;

  setUp(() async => rig = await _Rig.build());

  test('Stopping a passkey session stops its client and then closes its vault',
      () async {
    final session = PasskeySession(rig.client, rig.store, rig.vault);
    bool? openWhileStopping;
    rig.client.onStop = () async => openWhileStopping = await rig.vaultOpen();

    await session.stop();

    expect(rig.client.stops, 1);
    expect(openWhileStopping, isTrue);
    await rig.expectVaultClosed();
    expect(rig.store.closes, 1);
  });

  test('Stopping the session\'s client directly closes the vault too',
      () async {
    PasskeySession(rig.client, rig.store, rig.vault);
    final finishing = Completer<void>();
    rig.client.onStop = () => finishing.future;

    final stopping = rig.client.stop();
    await pumpEventQueue();
    expect(rig.client.connection.current.cause, AtConnectionCause.stopped);
    expect(await rig.vaultOpen(), isTrue,
        reason: 'open until the client has stopped');
    finishing.complete();
    await stopping;
    await pumpEventQueue();

    await rig.expectVaultClosed();
    expect(rig.store.closes, 1);
  });

  test(
      'A @keys write queued when the client stops ends before the vault closes',
      () async {
    rig.docs.hold = Completer<void>();
    final session = PasskeySession(rig.client, rig.store, rig.vault);
    final writing = rig.update();
    await pumpEventQueue();
    var stopped = false;
    final stopping = session.stop().whenComplete(() => stopped = true);
    await pumpEventQueue();

    expect(stopped, isFalse);
    expect(await rig.vaultOpen(), isTrue);
    rig.docs.hold!.complete();
    await writing;
    await stopping;
    await rig.expectVaultClosed();

    final stuck = await _Rig.build();
    stuck.docs.hold = Completer<void>();
    final bounded = PasskeySession(stuck.client, stuck.store, stuck.vault,
        settleWithin: const Duration(milliseconds: 100));
    unawaited(stuck.update().then((_) {}, onError: (Object _) {}));
    await pumpEventQueue();
    final clock = Stopwatch()..start();
    await bounded.stop().timeout(const Duration(seconds: 5));
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    await stuck.expectVaultClosed();
  });

  test(
      'Stopping the session closes the vault even when stopping the client '
      'fails', () async {
    final error = StateError('stop failed');
    rig.client.stopError = error;
    final session = PasskeySession(rig.client, rig.store, rig.vault);

    await expectLater(session.stop(), throwsA(same(error)));

    await rig.expectVaultClosed();
  });

  test('Stopping a session a second time does nothing', () async {
    final session = PasskeySession(rig.client, rig.store, rig.vault);
    await session.stop();

    await session.stop();

    expect(rig.client.stops, 1);
    expect(rig.store.closes, 1);
  });

  test('a second stop after one that threw throws nothing', () async {
    rig.client.stopError = StateError('stop failed');
    final session = PasskeySession(rig.client, rig.store, rig.vault);
    await expectLater(session.stop(), throwsStateError);

    await session.stop();

    expect(rig.client.stops, 1);
  });

  test('a client stop that never ends keeps the vault open only to the bound',
      () async {
    PasskeySession(rig.client, rig.store, rig.vault,
        settleWithin: const Duration(milliseconds: 100));
    rig.client.onStop = () => Completer<void>().future;

    unawaited(rig.client.stop());
    await pumpEventQueue();
    expect(await rig.vaultOpen(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    await rig.expectVaultClosed();
  });

  test('a session over a client already stopped closes its vault at once',
      () async {
    await rig.client.stop();

    PasskeySession(rig.client, rig.store, rig.vault);
    await pumpEventQueue();

    await rig.expectVaultClosed();
  });
}
