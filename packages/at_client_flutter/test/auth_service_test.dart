import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtAuth extends Mock implements AtAuth {}

class MockKeychainAtKeysIo extends Mock implements KeychainAtKeysIo {}

class FakeAtKeys extends Fake implements AtKeys {}

class FakeAtAuthRequest extends Fake implements AtAuthRequest {}

class MockFileAtKeysIo extends Mock implements FileAtKeysIo {}

class FakeAtOnboardingRequest extends Fake implements AtOnboardingRequest {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAtAuth mockAtAuth;
  late MockKeychainAtKeysIo mockKeychainAtKeysIo;
  late MockFileAtKeysIo mockFileAtKeysIo;
  late AtKeys fakeAtKeys;
  Map<String, AtKeys> atKeysList = {};
  setUp(() {
    mockAtAuth = MockAtAuth();
    mockKeychainAtKeysIo = MockKeychainAtKeysIo();
    mockFileAtKeysIo = MockFileAtKeysIo();
    registerFallbackValue(FakeAtAuthRequest());
    registerFallbackValue(MockFileAtKeysIo());
    registerFallbackValue(FakeAtKeys());
    registerFallbackValue(FakeAtOnboardingRequest());

    fakeAtKeys = AtKeys()
      ..apkamPrivateKey = AtBytes.fromString('dummykey')
      ..apkamPublicKey = AtBytes.fromString('dummykey')
      ..defaultEncryptionPrivateKey = AtBytes.fromString('dummykey')
      ..defaultEncryptionPublicKey = AtBytes.fromString('dummykey')
      ..defaultSelfEncryptionKey = AtBytes.fromString('dummykey')
      ..metadata = {'atsign': '@alice'};

    when(() => mockKeychainAtKeysIo.write(any(), any())).thenAnswer(
      (args) async => atKeysList[args.positionalArguments[0]] = fakeAtKeys,
    );
    when(() => mockKeychainAtKeysIo.read(any())).thenAnswer((atSign) async {
      return fakeAtKeys;
    });
  });
  group('AuthService', () {
    test(
      'assert authenticate() backs up the keys it authenticated with',
      () async {
        when(() => mockAtAuth.authenticate(any())).thenAnswer(
          (_) async => AtAuthResponse('@alice')
            ..isSuccessful = true
            ..session = AtAuthSession(
              atSign: '@alice',
              rootDomain: AtRootDomain.atsignDomain,
              atKeysIo: mockFileAtKeysIo,
              enrollmentId: 'enroll-1',
            ),
        );
        when(
          () => mockFileAtKeysIo.read(any()),
        ).thenAnswer((_) async => fakeAtKeys);
        AuthService authService = AuthService(atAuth: mockAtAuth);
        AtAuthRequest atAuthRequest = AtAuthRequest(
          "@alice",
          atKeysIo: mockFileAtKeysIo,
        );

        await authService.authenticate(
          atAuthRequest,
          backupKeys: [mockKeychainAtKeysIo],
        );

        // What the keychain double was HANDED, not what it was stubbed to
        // answer: `read` here returns fakeAtKeys whatever happened, so
        // asserting on it passed with the backup path deleted.
        expect(
          atKeysList['@alice'],
          same(fakeAtKeys),
          reason:
              'a backup is a copy of what was authenticated with, read '
              'back through the source the session carries',
        );
      },
    );

    test('assert onboard()', () {
      when(() => mockAtAuth.onboard(any(), any())).thenAnswer(
        (_) async => AtOnboardingResponse('@alice')
          ..isSuccessful = true
          ..session = AtAuthSession(
            atSign: '@alice',
            rootDomain: AtRootDomain.atsignDomain,
            atKeysIo: mockFileAtKeysIo,
            enrollmentId: 'enroll-1',
          ),
      );
      AuthService authService = AuthService(atAuth: mockAtAuth);
      AtOnboardingRequest atOnboardingRequest = AtOnboardingRequest(
        "@alice",
        signingAlgoType: SigningAlgoType.rsa2048,
        atKeysIo: mockFileAtKeysIo,
      );

      //regardless of atKeysIo used in AtOnboardingRequest, keys should be saved to keychain
      expect(
        () async =>
            await authService.onboard(atOnboardingRequest, 'cramSecret'),
        returnsNormally,
      );
    });
  });
}
