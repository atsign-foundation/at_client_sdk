import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtAuth extends Mock implements AtAuth {}

class MockKeychainAtKeysIo extends Mock implements KeychainAtKeysIo {}

class FakeAtAuthRequest extends Fake implements AtAuthRequest {}

class MockFileAtKeysIo extends Mock implements FileAtKeysIo {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAtAuth mockAtAuth;
  late MockKeychainAtKeysIo mockKeychainAtKeysIo;
  late MockFileAtKeysIo mockFileAtKeysIo;
  late AtKeys fakeAtKeys;
  Map<String, AtKeys> atKeysList = {};
  setUp(
    () {
      mockAtAuth = MockAtAuth();
      mockKeychainAtKeysIo = MockKeychainAtKeysIo();
      mockFileAtKeysIo = MockFileAtKeysIo();
      registerFallbackValue(FakeAtAuthRequest());
      registerFallbackValue(MockFileAtKeysIo());

      fakeAtKeys = AtKeys()
        ..apkamPrivateKey = AtBytes.fromString('dummykey')
        ..apkamPublicKey = AtBytes.fromString('dummykey')
        ..defaultEncryptionPrivateKey = AtBytes.fromString('dummykey')
        ..defaultEncryptionPublicKey = AtBytes.fromString('dummykey')
        ..defaultSelfEncryptionKey = AtBytes.fromString('dummykey')
        ..metadata = {'atsign': '@alice'};

      when(() => mockKeychainAtKeysIo.write(any(), any()))
          .thenAnswer((_) async => atKeysList[_.positionalArguments[0]] = fakeAtKeys);
      when(() => mockKeychainAtKeysIo.read(any())).thenAnswer((atSign) async {
        final result = atKeysList[atSign.positionalArguments[0]];
        if (result == null) {
          throw Exception('AtKeys not found for ${atSign.positionalArguments[0]}');
        }
        return result;
      });
    },
  );
  group('AuthService', () {
    test('assert authenticate() saves keys to keychain', () async {
      when(() => mockAtAuth.authenticate(any())).thenAnswer((_) async => AtAuthResponse('@alice')
        ..isSuccessful = true
        ..atAuthKeys = fakeAtKeys);
      when(() => mockFileAtKeysIo.read(any())).thenAnswer((_) async => fakeAtKeys);
      AuthService authService = AuthService(atAuth: mockAtAuth, keychainAtKeysIo: mockKeychainAtKeysIo);
      AtAuthRequest atAuthRequest = AtAuthRequest("@alice", mockFileAtKeysIo);

      //regardless of atKeysIo used in AtAuthRequest, keys should be saved to keychain
      AtAuthResponse _ = await authService.authenticate(atAuthRequest);
      var keys = await mockKeychainAtKeysIo.read('@alice');
      expect(keys.apkamPrivateKey, isNotNull);
      expect(keys.apkamPublicKey, isNotNull);
      expect(keys.defaultEncryptionPrivateKey, isNotNull);
      expect(keys.defaultEncryptionPublicKey, isNotNull);
    });

    test('assert onboard()', () {
      when(() => mockAtAuth.onboard(any(), any())).thenAnswer((_) async => AtOnboardingResponse('@alice')
        ..isSuccessful = true
        ..atAuthKeys = fakeAtKeys);
      AuthService authService = AuthService(atAuth: mockAtAuth, keychainAtKeysIo: mockKeychainAtKeysIo);
      AtOnboardingRequest atOnboardingRequest = AtOnboardingRequest("@alice", atKeysIo: mockFileAtKeysIo);

      //regardless of atKeysIo used in AtOnboardingRequest, keys should be saved to keychain
      expect(() async => await authService.onboard(atOnboardingRequest, 'cramSecret'), returnsNormally);
    });
  });
}
