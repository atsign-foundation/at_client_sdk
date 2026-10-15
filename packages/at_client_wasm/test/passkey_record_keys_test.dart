import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart' show InvalidAtSignException;

import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:test/test.dart';

class FakePasskeyPort implements PasskeyPort {
  String? lastCreateAtSign;
  Uint8List? lastCreateEvalInput;
  Uint8List? lastGetEvalInput;
  Uint8List? lastGetAllowCredential;

  Uint8List? resultPrfFirst;
  Uint8List? resultUserHandle;
  Uint8List resultCredentialId = Uint8List.fromList([1, 2, 3]);

  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput}) async {
    lastCreateAtSign = atSign;
    lastCreateEvalInput = evalInput;
    return (credentialId: resultCredentialId, prfFirst: resultPrfFirst);
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    lastGetEvalInput = evalInput;
    lastGetAllowCredential = allowCredential;
    return (
      credentialId: resultCredentialId,
      prfFirst: resultPrfFirst,
      userHandle: resultUserHandle,
    );
  }
}

void main() {
  final p = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));

  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  group('recordPrfSalt', () {
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
    test('register passes the constant salt and returns PrfSecret', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));

      final kek = PasskeyKek(port);
      final result = await kek.register('@alice');

      expect(port.lastCreateAtSign, '@alice');
      expect(port.lastCreateEvalInput, await recordPrfSalt());

      expect(result.credentialId, port.resultCredentialId);
      expect(result.secret.output, port.resultPrfFirst);
    });

    test('register throws PrfUnavailableException on null prf', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = null;

      final kek = PasskeyKek(port);
      expect(kek.register('@alice'), throwsA(isA<PrfUnavailableException>()));
    });

    test('register throws PrfUnavailableException on 31 bytes', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(31, (i) => i));

      final kek = PasskeyKek(port);
      expect(kek.register('@alice'), throwsA(isA<PrfUnavailableException>()));
    });

    test('unlock passes the constant salt and returns PrfSecret', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));

      final kek = PasskeyKek(port);
      final credId = Uint8List.fromList([4, 5, 6]);
      final result = await kek.unlock(credentialId: credId);

      expect(port.lastGetEvalInput, await recordPrfSalt());
      expect(port.lastGetAllowCredential, credId);

      expect(result.credentialId, port.resultCredentialId);
      expect(result.secret.output, port.resultPrfFirst);
    });

    test('unlock throws PrfUnavailableException on null prf', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = null;

      final kek = PasskeyKek(port);
      expect(kek.unlock(), throwsA(isA<PrfUnavailableException>()));
    });

    test('register names the passkey user with the canonical atSign', () async {
      final port = FakePasskeyPort()
        ..resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));
      await PasskeyKek(port).register('Ali.ce');
      expect(port.lastCreateAtSign, '@alice');
    });

    test('register refuses an atSign longer than 64 UTF-8 bytes', () async {
      final port = FakePasskeyPort()
        ..resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));
      expect(PasskeyKek(port).register('@${'🐱' * 16}'), throwsArgumentError);
      expect(port.lastCreateAtSign, isNull);
      await PasskeyKek(port).register('@${'a' * 55}');
      expect(port.lastCreateAtSign, '@${'a' * 55}');
    });

    test('unlock without a credentialId asks for any discoverable passkey',
        () async {
      final port = FakePasskeyPort()
        ..resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));
      await PasskeyKek(port).unlock();
      expect(port.lastGetAllowCredential, isNull);
    });

    group('unlock reads the atSign from userHandle', () {
      final cases = <String, (List<int>?, String?)>{
        'a canonical handle': (utf8.encode('@alice'), '@alice'),
        'a non-canonical handle': (utf8.encode('Alice'), '@alice'),
        'no handle': (null, null),
        'a handle that is not UTF-8': ([0xff, 0xfe], null),
        'a handle that is not an atSign': (utf8.encode('@al ice'), null),
      };
      for (final MapEntry(key: name, value: (handle, atSign))
          in cases.entries) {
        test(name, () async {
          final port = FakePasskeyPort()
            ..resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i))
            ..resultUserHandle =
                handle == null ? null : Uint8List.fromList(handle);
          expect((await PasskeyKek(port).unlock()).atSign, atSign);
        });
      }
    });

    test('unlock throws PrfUnavailableException on 31 bytes', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(31, (i) => i));

      final kek = PasskeyKek(port);
      expect(kek.unlock(), throwsA(isA<PrfUnavailableException>()));
    });
  });
}
