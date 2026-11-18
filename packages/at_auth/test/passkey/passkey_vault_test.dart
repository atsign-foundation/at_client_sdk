import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/passkey_fakes.dart';

const _doc = {'selfEncryptionKey': 'self'};

void main() {
  late SpyRecordSealer spy;
  late BytesRecordSealer bytesSealer;
  late Uint8List authSeed;
  late PasskeyVault vault;

  setUp(() async {
    final derived = await const BytesPasskeyKeyDeriver().derive(
        PrfSecret(Uint8List.fromList(List.generate(32, (i) => i))), '@alice');
    bytesSealer = derived.sealer as BytesRecordSealer;
    spy = SpyRecordSealer(bytesSealer);
    authSeed = derived.authSeed;
    vault = PasskeyVault((
      lookupHex: derived.lookupHex,
      ns: derived.ns,
      authSeed: authSeed,
      sealer: spy,
    ), atSign: '@alice');
  });

  test('exposes the record id and pointer namespace', () {
    expect(vault.lookupHex,
        '562dd8ceae1d04851c10847fea609250dc0c74d92af520a4ab96565bfea6c4b6');
    expect(vault.ns,
        '10781e72da94f814194f90c4c40d75d7b0b029d06253d40a610b0ad977b2d620');
  });

  test('holds its atSign in canonical form, and seals for it', () async {
    final derived = await const BytesPasskeyKeyDeriver().derive(
        PrfSecret(Uint8List.fromList(List.generate(32, (i) => i))), '@alice');
    final spelt = PasskeyVault(derived, atSign: '@Alice');
    addTearDown(spelt.close);

    expect(spelt.atSign, '@alice');
    expect(
        await vault.open(PasskeyRecordType.atkeys,
            await spelt.seal(PasskeyRecordType.atkeys, _doc)),
        _doc);
  });

  test('seals and opens records through its sealer', () async {
    final record = await vault.seal(PasskeyRecordType.atkeys, _doc);
    expect(spy.sealCalls, 1);
    expect(await vault.open(PasskeyRecordType.atkeys, record), _doc);
  });

  test('gives the auth seed to the caller and leaves it intact', () async {
    final expected = Uint8List.fromList(authSeed);
    Uint8List? seen;
    final result = await vault.withAuthSeed((seed) async {
      seen = Uint8List.fromList(seed);
      return 7;
    });
    expect(result, 7);
    expect(seen, expected);
    expect(authSeed, expected);
  });

  test('a second withAuthSeed sees the same seed', () async {
    final expected = Uint8List.fromList(authSeed);
    final seen = <Uint8List>[];
    await vault
        .withAuthSeed((seed) async => seen.add(Uint8List.fromList(seed)));
    await vault
        .withAuthSeed((seed) async => seen.add(Uint8List.fromList(seed)));
    expect(seen, [expected, expected]);
  });

  test('a throwing callback leaves the seed usable', () async {
    final expected = Uint8List.fromList(authSeed);
    await expectLater(
        vault.withAuthSeed((_) async => throw FormatException('boom')),
        throwsFormatException);
    expect(authSeed, expected);
    Uint8List? seen;
    await vault.withAuthSeed((seed) async => seen = Uint8List.fromList(seed));
    expect(seen, expected);
  });

  test('close wipes the auth seed and closes the sealer once', () {
    vault.close();
    expect(authSeed, everyElement(0));
    expect(spy.closeCalls, 1);
  });

  test('wipeAuthSeed zeroes the seed, refuses the seed and keeps sealing',
      () async {
    vault.wipeAuthSeed();
    vault.wipeAuthSeed();
    expect(authSeed, everyElement(0));
    expect(spy.closeCalls, 0);
    await expectLater(vault.withAuthSeed((_) async {}), throwsStateError);
    final sealed = await vault.seal(PasskeyRecordType.atkeys, {'k': 1});
    expect(await vault.open(PasskeyRecordType.atkeys, sealed), {'k': 1});
    vault.close();
    expect(spy.closeCalls, 1);
  });

  test('close wipes the sealer key bytes', () {
    expect(bytesSealer.keyBytes, isNot(everyElement(0)));
    vault.close();
    expect(bytesSealer.keyBytes, everyElement(0));
  });

  test('a closed test sealer refuses to seal or open', () async {
    final sealer = BytesRecordSealer(Uint8List(32)..fillRange(0, 32, 7));
    final iv = Uint8List(12);
    final sealed = await sealer.seal(iv, [1, 2, 3], const []);
    sealer.close();
    await expectLater(sealer.seal(iv, [1, 2, 3], const []), throwsStateError);
    await expectLater(sealer.open(iv, sealed, const []), throwsStateError);
  });

  test('close twice does not close the sealer twice', () {
    vault.close();
    vault.close();
    expect(spy.closeCalls, 1);
  });

  test('use after close throws StateError', () async {
    vault.close();
    await expectLater(
        vault.seal(PasskeyRecordType.atkeys, _doc), throwsStateError);
    await expectLater(
        vault.open(PasskeyRecordType.atkeys, '{}'), throwsStateError);
    var ran = false;
    await expectLater(vault.withAuthSeed((_) async {
      ran = true;
      return 1;
    }), throwsStateError);
    expect(ran, isFalse);
  });

  group('authSeed length', () {
    for (final length in [31, 33]) {
      test('a $length-byte auth seed is rejected', () {
        expect(
            () => PasskeyVault((
                  lookupHex: 'a' * 64,
                  ns: 'b' * 64,
                  authSeed: Uint8List(length),
                  sealer: spy,
                ), atSign: '@alice'),
            throwsArgumentError);
      });
    }
  });

  group('close while withAuthSeed is in flight', () {
    test('lets the use finish with the intact seed, then wipes and closes once',
        () async {
      final expected = Uint8List.fromList(authSeed);
      final started = Completer<void>();
      final release = Completer<void>();
      Uint8List? seenBefore;
      Uint8List? seenAfter;
      final use = vault.withAuthSeed((seed) async {
        started.complete();
        await release.future;
        seenAfter = Uint8List.fromList(seed);
        return 5;
      });
      await started.future;
      seenBefore = Uint8List.fromList(authSeed);

      vault.close();
      expect(spy.closeCalls, 0);
      expect(authSeed, expected);
      await expectLater(vault.withAuthSeed((_) async => 1), throwsStateError);
      await expectLater(
          vault.seal(PasskeyRecordType.atkeys, _doc), throwsStateError);

      release.complete();
      expect(await use, 5);
      expect(seenBefore, expected);
      expect(seenAfter, expected);
      expect(authSeed, everyElement(0));
      expect(spy.closeCalls, 1);

      vault.close();
      expect(spy.closeCalls, 1);
    });

    test('a use that throws still lets the deferred close happen', () async {
      final release = Completer<void>();
      final use = vault.withAuthSeed((_) async {
        await release.future;
        throw FormatException('boom');
      });
      vault.close();
      expect(spy.closeCalls, 0);
      release.complete();
      await expectLater(use, throwsFormatException);
      expect(authSeed, everyElement(0));
      expect(spy.closeCalls, 1);
    });
  });

  group('wipeAuthSeed while withAuthSeed is in flight', () {
    test('leaves the seed whole for the running use, then zeroes it', () async {
      final expected = Uint8List.fromList(authSeed);
      final started = Completer<void>();
      final release = Completer<void>();
      Uint8List? seenAfterWipe;
      final use = vault.withAuthSeed((seed) async {
        started.complete();
        await release.future;
        seenAfterWipe = Uint8List.fromList(seed);
        return 5;
      });
      await started.future;

      vault.wipeAuthSeed();
      expect(authSeed, expected);
      await expectLater(vault.withAuthSeed((_) async => 1), throwsStateError);

      release.complete();
      expect(await use, 5);
      expect(seenAfterWipe, expected);
      expect(authSeed, everyElement(0));
      expect(spy.closeCalls, 0);
    });

    test('zeroes the seed when a use that throws ends', () async {
      final release = Completer<void>();
      final use = vault.withAuthSeed((_) async {
        await release.future;
        throw FormatException('boom');
      });
      vault.wipeAuthSeed();
      expect(authSeed, isNot(everyElement(0)));
      release.complete();
      await expectLater(use, throwsFormatException);
      expect(authSeed, everyElement(0));
    });
  });
}
