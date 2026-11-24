import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

class _MockAtLookUp extends Mock implements AtLookUp {}

/// Catalogue: features/at_auth/self_enrollment_files_through_update.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/package_info'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getAll') {
            return {
              'appName': 'test',
              'packageName': 'test',
              'version': '1.0.0',
              'buildNumber': '1',
            };
          }
          return false;
        },
      );

  const atSign = '@alice';
  const namespaceKeyId = 'nskey.app_1.kid1';
  String b64(String s) => base64Encode(utf8.encode(s));

  /// The keychain's one entry, as a plain string the fake reads and writes.
  String? blob;
  late BiometricStorage biometricStorage;

  setUp(() {
    KeychainStorage.isWindows = false;
    blob = null;
    final file = _MockBiometricStorageFile();
    when(() => file.read()).thenAnswer((_) async => blob);
    when(() => file.write(any())).thenAnswer((invocation) async {
      blob = invocation.positionalArguments[0] as String;
    });
    biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => file);
  });

  KeychainAtKeysIo keychain() => KeychainAtKeysIo(
    keychainStorage: KeychainStorage(biometricStorage: biometricStorage),
  );

  /// Another writer's update filing an active namespace key private,
  /// atSign-scope, as at_client files one.
  Future<void> addNamespaceKey() =>
      keychain().update(atSign.toAtsign(), (keys) {
        keys.addKey(
          CryptographicMaterial(
            keyId: namespaceKeyId,
            role: CryptographicMaterialRole.privateDecapsulation,
            algorithm: CryptographicMaterialAlgorithm.xWing,
            bytes: AtBytes(Uint8List.fromList(List.filled(32, 7))),
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        return true;
      });

  /// An atServer that has [addNamespaceKey] run before it approves the
  /// self-enrollment's request, and confirms a revoke.
  _MockAtLookUp answeringAfterAnotherWriter() {
    final lookUp = _MockAtLookUp();
    when(
      () => lookUp.executeCommand(any(), auth: any(named: 'auth')),
    ).thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      if (command.startsWith('enroll:request:')) {
        await addNamespaceKey();
        return 'data:{"enrollmentId":"new-123","status":"approved"}';
      }
      if (command.startsWith('enroll:revoke:')) {
        return 'data:{"enrollmentId":"new-123","status":"revoked"}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    return lookUp;
  }

  group('A self-enrollment files its keys through update', () {
    test('A key another writer adds to the keychain while a self-enrollment '
        'waits on the atServer is kept', () async {
      await keychain().write(
        atSign,
        AtKeys.legacy(
          apkamPublicKey: b64('legacy-rsa-public'),
          apkamPrivateKey: b64('legacy-rsa-private'),
          encryptionPublicKey: b64('enc-public'),
          encryptionPrivateKey: b64('enc-private'),
          selfEncryptionKey: b64('self-key'),
          enrollmentId: 'legacy-1',
        ),
      );

      final response = await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
          session: AtAuthSession(
            atSign: atSign,
            rootDomain: const AtRootDomain('127.0.0.1', 1),
            atKeysIo: keychain(),
            enrollmentId: 'legacy-1',
          ),
          appName: 'selfapp',
          deviceName: 'selfdevice',
          namespaces: {'app_1': 'rw'},
        ),
        answeringAfterAnotherWriter(),
      );

      expect(response.enrollmentId, 'new-123');
      final after = await keychain().read(atSign);
      expect(
        after.getAtSignKey(
          namespaceKeyId,
          CryptographicMaterialRole.privateDecapsulation,
        ),
        isNotNull,
        reason: 'the key the other writer added is kept',
      );
      expect(
        after.getKey(
          'new-123',
          'auth:mldsa65:1',
          CryptographicMaterialRole.privateAuthentication,
        ),
        isNotNull,
      );
      expect(
        after.getKey(
          'new-123',
          'auth:mldsa65:1',
          CryptographicMaterialRole.publicAuthentication,
        ),
        isNotNull,
      );
    });
  });
}
