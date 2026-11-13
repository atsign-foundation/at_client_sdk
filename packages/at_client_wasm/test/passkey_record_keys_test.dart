import 'dart:typed_data';

import 'package:at_commons/at_commons.dart' show InvalidAtSignException;

import 'package:at_client_wasm/src/keys/passkey_port.dart';
import 'package:at_client_wasm/src/keys/prf_support.dart';
import 'package:at_client_wasm/src/keys/passkey_record_keys.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:test/test.dart';

class FakePasskeyPort implements PasskeyPort {
  final calls = <String>[];
  String? lastCreateAtSign;
  Uint8List? lastGetEvalInput;
  Uint8List? lastGetAllowCredential;

  Uint8List? resultPrfFirst;
  Uint8List resultCredentialId = Uint8List.fromList([1, 2, 3]);

  @override
  Future<Uint8List> create({required String atSign}) async {
    calls.add('create');
    lastCreateAtSign = atSign;
    return resultCredentialId;
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    calls.add('get');
    lastGetEvalInput = evalInput;
    lastGetAllowCredential = allowCredential;
    return (credentialId: resultCredentialId, prfFirst: resultPrfFirst);
  }
}

/// A [PrfEnvironment] with a settable clock, capability answer and miss flag.
class FakePrfEnvironment implements PrfEnvironment {
  bool? capability;
  DateTime? missAt;
  var clock = DateTime.utc(2026, 11, 13);

  @override
  Future<bool?> clientCapabilityPrf() async => capability;

  @override
  DateTime? missRecordedAt() => missAt;

  @override
  void recordMiss(DateTime at) => missAt = at;

  @override
  DateTime now() => clock;
}

/// SHA-256 of `atsign:keys:lookup:v1`; changing it re-keys every passkey.
final _pinnedPrfSalt = Uint8List.fromList(const [
  0xe5,
  0x83,
  0x0b,
  0x40,
  0x9d,
  0xb0,
  0xe5,
  0x03,
  0xaf,
  0x40,
  0xc2,
  0x54,
  0x59,
  0x8c,
  0x41,
  0xbf,
  0x4e,
  0x6a,
  0xd6,
  0x62,
  0x7f,
  0xf1,
  0x85,
  0xd3,
  0x11,
  0xa9,
  0xf4,
  0x46,
  0x38,
  0x3e,
  0xa6,
  0x20,
]);

void main() {
  final p = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));

  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  group('recordPrfSalt', () {
    test('the PRF eval input is the pinned literal', () async {
      expect(await recordPrfSalt(), _pinnedPrfSalt);
    });

    test('is SHA-256 of atsign:keys:lookup:v1', () async {
      expect(hex(await recordPrfSalt()),
          'e5830b409db0e503af40c254598c41bf4e6ad6627ff185d311a9f446383ea620');
    });
  });

  group('RecordKeys.derive', () {
    test('matches the HKDF-SHA256 golden vectors for @alice', () async {
      final keys = await RecordKeys.derive(p, '@alice');
      expect(keys.lookupHex,
          '7086a5038ed92fcd20309c479df67581a64cf9f8caf802ef81e7ecec8e4272fe');
      expect(hex(keys.kek),
          '338114674b5a98898fe30e20b4e29e96907ac6ec58b615bc0a298e759cd520b0');
    });

    test('matches the HKDF-SHA256 golden vectors for @bob', () async {
      final keys = await RecordKeys.derive(p, '@bob');
      expect(keys.lookupHex,
          'e3fff7ad835de533d15ce0a883f78103d831b96f21195292ec1d49eb88777cca');
      expect(hex(keys.kek),
          '77b8149219d7e3daf54e13a5deeced55f0f09b99ba470d2fabc9e93c1c953de3');
    });

    test('lookupHex is 64 lowercase hex and kek is 32 bytes', () async {
      final keys = await RecordKeys.derive(p, '@alice');
      expect(keys.lookupHex, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(keys.kek, hasLength(32));
    });

    test('the lookup and kek labels give different outputs', () async {
      final keys = await RecordKeys.derive(p, '@alice');
      expect(keys.lookupHex, isNot(hex(keys.kek)));
    });

    test('derives the 32-byte ML-DSA auth seed for @alice', () async {
      final keys = await RecordKeys.derive(p, '@alice');
      expect(keys.authSeed, hasLength(32));
      expect(hex(keys.authSeed),
          'b0e85850ef5407a914408bc6ccdc6a32baeb6446127275414199179a2cf79fc6');
    });

    test('the auth seed differs from the lookup id and the kek', () async {
      final keys = await RecordKeys.derive(p, '@alice');
      expect(hex(keys.authSeed), isNot(keys.lookupHex));
      expect(keys.authSeed, isNot(keys.kek));
    });

    test('the auth seed is unrelated across atSigns', () async {
      final alice = await RecordKeys.derive(p, '@alice');
      final bob = await RecordKeys.derive(p, '@bob');
      expect(alice.authSeed, isNot(bob.authSeed));
    });

    test('the auth seed is the same for every spelling of the atSign',
        () async {
      final canonical = await RecordKeys.derive(p, '@alice');
      final spelled = await RecordKeys.derive(p, '@Ali.ce');
      expect(spelled.authSeed, canonical.authSeed);
    });

    test('canonicalizes the atSign before deriving', () async {
      final canonical = await RecordKeys.derive(p, '@alice');
      for (final variant in ['@Alice', 'alice', 'ALICE', '@ali.ce']) {
        final keys = await RecordKeys.derive(p, variant);
        expect(keys.lookupHex, canonical.lookupHex, reason: variant);
        expect(keys.kek, canonical.kek, reason: variant);
      }
    });

    test('rejects an invalid atSign', () {
      expect(RecordKeys.derive(p, '@al ice'),
          throwsA(isA<InvalidAtSignException>()));
    });
  });

  group('PasskeyKek', () {
    final prf = Uint8List.fromList(List.generate(32, (i) => i));

    test('register creates, then reads the PRF from a get with the salt',
        () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      final result = await PasskeyKek(port).register('@alice');

      expect(port.calls, ['create', 'get']);
      expect(port.lastCreateAtSign, '@alice');
      expect(port.lastGetEvalInput, await recordPrfSalt());
      expect(port.lastGetAllowCredential, port.resultCredentialId);
      expect(result.credentialId, port.resultCredentialId);
      expect(result.secret.output, prf);
    });

    test('register throws PrfUnavailableException on null prf', () async {
      final port = FakePasskeyPort()..resultPrfFirst = null;
      expect(PasskeyKek(port).register('@alice'),
          throwsA(isA<PrfUnavailableException>()));
    });

    test('register throws PrfUnavailableException on 31 bytes', () async {
      final port = FakePasskeyPort()
        ..resultPrfFirst = Uint8List.fromList(List.generate(31, (i) => i));
      expect(PasskeyKek(port).register('@alice'),
          throwsA(isA<PrfUnavailableException>()));
    });

    test('unlock passes the constant salt and returns PrfSecret', () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      final credId = Uint8List.fromList([4, 5, 6]);
      final result = await PasskeyKek(port).unlock(credentialId: credId);

      expect(port.lastGetEvalInput, _pinnedPrfSalt);
      expect(port.lastGetAllowCredential, credId);
      expect(result.credentialId, port.resultCredentialId);
      expect(result.secret.output, prf);
    });

    test('unlock throws PrfUnavailableException on null prf', () async {
      final port = FakePasskeyPort()..resultPrfFirst = null;
      expect(
          PasskeyKek(port).unlock(), throwsA(isA<PrfUnavailableException>()));
    });

    test('unlock throws PrfUnavailableException on 31 bytes', () async {
      final port = FakePasskeyPort()
        ..resultPrfFirst = Uint8List.fromList(List.generate(31, (i) => i));
      expect(
          PasskeyKek(port).unlock(), throwsA(isA<PrfUnavailableException>()));
    });

    test('register names the passkey user with the canonical atSign', () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await PasskeyKek(port).register('Ali.ce');
      expect(port.lastCreateAtSign, '@alice');
    });

    test('unlock without a credentialId asks for any discoverable passkey',
        () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await PasskeyKek(port).unlock();
      expect(port.lastGetAllowCredential, isNull);
    });

    test('a PRF miss on get records the miss for the capability fallback',
        () async {
      final env = FakePrfEnvironment();
      final port = FakePasskeyPort()..resultPrfFirst = null;
      await expectLater(
          PasskeyKek(port, prfSupport: PrfSupport(env)).register('@alice'),
          throwsA(isA<PrfUnavailableException>()));
      expect(env.missAt, env.clock);
    });

    test('register refuses before any ceremony when PRF is unsupported',
        () async {
      final env = FakePrfEnvironment()..capability = false;
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await expectLater(
          PasskeyKek(port, prfSupport: PrfSupport(env)).register('@alice'),
          throwsA(isA<PrfUnavailableException>().having(
              (e) => e.message, 'message', contains('supported browser'))));
      expect(port.calls, isEmpty);
    });
  });
}
