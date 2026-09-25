import 'dart:typed_data';

import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:test/test.dart';

class FakePasskeyPort implements PasskeyPort {
  String? lastCreateAtSign;
  Uint8List? lastCreateEvalInput;
  Uint8List? lastGetEvalInput;
  Uint8List? lastGetAllowCredential;

  Uint8List? resultPrfFirst;
  Uint8List resultCredentialId = Uint8List.fromList([1, 2, 3]);

  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput}) async {
    lastCreateAtSign = atSign;
    lastCreateEvalInput = evalInput;
    return (credentialId: resultCredentialId, prfFirst: resultPrfFirst);
  }

  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    lastGetEvalInput = evalInput;
    lastGetAllowCredential = allowCredential;
    return (credentialId: resultCredentialId, prfFirst: resultPrfFirst);
  }
}

void main() {
  group('PasskeyKek', () {
    test('prfEvalInput is stable and differs per atSign', () async {
      final inputAlice = await prfEvalInput('@alice');
      final inputAlice2 = await prfEvalInput('@alice');
      final inputBob = await prfEvalInput('@bob');

      expect(inputAlice, inputAlice2);
      expect(inputAlice, isNot(inputBob));
    });

    test('register passes correct inputs and returns PrfSecret', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));

      final kek = PasskeyKek(port);
      final result = await kek.register('@alice');

      expect(port.lastCreateAtSign, '@alice');
      expect(port.lastCreateEvalInput, await prfEvalInput('@alice'));

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

    test('unlock passes correct inputs and returns PrfSecret', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(32, (i) => i));

      final kek = PasskeyKek(port);
      final credId = Uint8List.fromList([4, 5, 6]);
      final result = await kek.unlock('@alice', credentialId: credId);

      expect(port.lastGetEvalInput, await prfEvalInput('@alice'));
      expect(port.lastGetAllowCredential, credId);

      expect(result.credentialId, port.resultCredentialId);
      expect(result.secret.output, port.resultPrfFirst);
    });

    test('unlock throws PrfUnavailableException on null prf', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = null;

      final kek = PasskeyKek(port);
      expect(kek.unlock('@alice'), throwsA(isA<PrfUnavailableException>()));
    });

    test('unlock throws PrfUnavailableException on 31 bytes', () async {
      final port = FakePasskeyPort();
      port.resultPrfFirst = Uint8List.fromList(List.generate(31, (i) => i));

      final kek = PasskeyKek(port);
      expect(kek.unlock('@alice'), throwsA(isA<PrfUnavailableException>()));
    });
  });
}
