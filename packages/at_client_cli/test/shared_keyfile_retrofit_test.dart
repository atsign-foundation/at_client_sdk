import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtLookUp extends Mock implements AtLookupImpl {}

/// Self-retrofits of one keyfile by programs that open it through
/// [CliKeys.fileFor], as two instances of one program do, against an
/// atServer that approves each request after a delay.
///
/// Catalogue: features/at_client_cli/shared_keyfile_retrofit.feature
void main() {
  const atSign = '@alice';
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shared_keyfile_retrofit_');
    path = '${dir.path}/${atSign}_key.atKeys';
  });

  tearDown(() {
    retrofitSerializer = null;
    dir.deleteSync(recursive: true);
  });

  String randomKey() =>
      base64Encode(List.generate(32, (_) => Random.secure().nextInt(256)));

  /// A keyfile whose credential is the RSA key of enrollment legacy-1.
  AtKeys legacyKeys() => AtKeys.legacy(
      apkamPublicKey: randomKey(),
      apkamPrivateKey: randomKey(),
      encryptionPublicKey: randomKey(),
      encryptionPrivateKey: randomKey(),
      selfEncryptionKey: randomKey(),
      enrollmentId: 'legacy-1');

  test('Instances of a program sharing a keyfile retrofit it one at a time',
      () async {
    await FileAtKeysIo(filePath: (_) => path).write(atSign, legacyKeys());
    var requests = 0;
    var revokes = 0;
    _MockAtLookUp atServer() {
      final lookUp = _MockAtLookUp();
      when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((invocation) async {
        final command = invocation.positionalArguments.first as String;
        if (command.startsWith('enroll:request')) {
          final id = 'new-${++requests}';
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return 'data:${jsonEncode({
                'enrollmentId': id,
                'status': 'approved'
              })}';
        }
        if (command.startsWith('enroll:revoke')) {
          revokes++;
          return 'data:${jsonEncode({'status': 'revoked'})}';
        }
        throw StateError('the mocked atServer has no answer for: $command');
      });
      return lookUp;
    }

    /// One instance's retrofit: the enrollment it answers with, or why not.
    Future<String> instance() => AtEnrollment.create()
        .submit(
            AtSelfEnrollmentRequest(
                session: AtAuthSession(
                    atSign: atSign,
                    rootDomain: AtRootDomain.atsignDomain,
                    atKeysIo: CliKeys.fileFor(atSign, path: path),
                    enrollmentId: 'legacy-1'),
                appName: 'agent',
                deviceName: 'instance',
                namespaces: {'my_app': 'rw'}),
            atServer())
        .then((response) => response.enrollmentId,
            onError: (Object e) => 'threw: $e');

    final answers = await Future.wait([instance(), instance()]);

    expect(requests, 1,
        reason: 'one instance sends the self-enrollment request: $answers');
    expect(revokes, 0);
    expect(answers, ['new-1', 'new-1'],
        reason: 'the other waits and answers with the enrollment it wrote');
    expect(
        (await FileAtKeysIo(filePath: (_) => path).read(atSign))
            .resolveAuthenticatingEnrollment(),
        'new-1');
  });

  test('A retrofit serializer the program set itself is kept', () {
    Future<T> serial<T>(
            AtKeysIo keysIo, String atSign, Future<T> Function() action) =>
        action();
    final RetrofitSerializer own = serial;
    retrofitSerializer = own;

    CliKeys.fileFor(atSign, path: path);

    expect(retrofitSerializer, same(own));
  });
}
