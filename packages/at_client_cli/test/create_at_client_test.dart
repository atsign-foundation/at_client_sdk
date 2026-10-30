import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' show deleteStorage;
import 'package:test/test.dart';

import 'keyfile_helpers.dart';
import 'lifecycle_rig.dart';

/// [createAtClient] as a program outside at_client_cli calls it.
///
/// Catalogue: features/at_client_cli/create_at_client.feature
void main() {
  AtSignLogger.root_level = 'SHOUT';
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('create_at_client_'));

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    deleteStorage();
    dir.deleteSync(recursive: true);
  });

  test(
      'A program written against at_onboarding_cli 2.0.0-rc8 compiles unchanged',
      () {
    final Future<AtClient> Function({
      required String atSign,
      String? atKeysFilePath,
      String? rootDomain,
      String? passPhrase,
      PqPosture? posture,
      bool waitForPqStartup,
      int maxConnectAttempts,
    }) rc8Shape = createAtClient;
    expect(identical(rc8Shape, createAtClient), isTrue);
  });

  test('A client still offline after its connect attempts is stopped',
      () async {
    const atSign = '@createoffline';
    final keysPath = '${dir.path}/keys/key.atKeys';
    await FileAtKeysIo(filePath: (_) => keysPath)
        .write(atSign, randomLegacyKeys());

    await expectLater(
        createAtClient(
            atSign: atSign,
            atKeysFilePath: keysPath,
            rootDomain: '127.0.0.1:${await refusedPort()}',
            posture: PqPosture.legacy,
            waitForPqStartup: false,
            maxConnectAttempts: 1),
        throwsA(isA<UnAuthenticatedException>().having((e) => e.message,
            'message', contains('Failed to connect within 1 attempts'))));
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'the client it opened is stopped');
  });
}
