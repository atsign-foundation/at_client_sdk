import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_client_flutter/src/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtAuth extends Mock implements AtAuth {}

class MockAtKeysIo extends Mock implements FileAtKeysIo {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const atSign = '@flutterowned';
  late MockAtKeysIo mockAtKeysIo;
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('flutter_create_client_');
    mockAtKeysIo = MockAtKeysIo();
    when(() => mockAtKeysIo.read(any())).thenAnswer(
      (_) async => AtKeys()
        ..apkamPrivateKey = AtBytes.fromString('dummykey')
        ..apkamPublicKey = AtBytes.fromString('dummykey')
        ..defaultEncryptionPrivateKey = AtBytes.fromString('dummykey')
        ..defaultEncryptionPublicKey = AtBytes.fromString('dummykey')
        ..defaultSelfEncryptionKey = AtBytes.fromString('dummykey')
        ..metadata = {'atsign': atSign},
    );
    AtClientManager.getInstance().reset();
  });

  tearDown(() async {
    for (final c in List<AtClient>.from(
      AtClientImpl.atClientInstanceMap.values,
    )) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  /// Names a Hive location the client would fall back on, so a bundle that
  /// never reached it shows up as this directory being opened.
  AtClientPreference preference() =>
      AtClientPreference()..hiveStoragePath = '${dir.path}/never_opened';

  AtAuthSession session() => AtAuthSession(
    atSign: atSign,
    rootDomain: AtRootDomain.parse('root.atsign.wtf:64'),
    namespace: 'unit_test',
    atKeysIo: mockAtKeysIo,
  );

  test('the client holds the storage, and is filed but not made current',
      () async {
    final storage = InMemoryAtClientStorage(atSign: atSign);
    final client = await AuthService(
      atAuth: MockAtAuth(),
    ).createClient(session(), preference(), storage: storage);

    expect(
      storage.isHeldBy(client),
      isTrue,
      reason:
          'the bundle the app supplied is the one the client opened, so '
          'a Flutter app chooses its own backend and location',
    );
    expect(
      Directory('${dir.path}/never_opened').existsSync(),
      isFalse,
      reason:
          'and hiveStoragePath went unread, rather than the client '
          'quietly opening a Hive store of its own',
    );
    expect(client.getCurrentAtSign(), atSign);
    expect(
      AtClientImpl.atClientInstanceMap[atSign],
      same(client),
      reason:
          'AtClientImpl.create files every client it builds, this one '
          'included - so a later setCurrentAtSign for this atSign adopts '
          'THIS client rather than building its own. Asserting only that '
          'the manager has no current client passes before createClient is '
          'ever called, which is what made the previous version of this '
          'test vacuous',
    );
    expect(
      () => AtClientManager.getInstance().atClient,
      throwsStateError,
      reason:
          'the app owns this client; only fromAuthSession fills in the '
          'shared current-atSign client',
    );

    await client.stop();
    await storage.close();
  });

  test(
    'the session\'s root domain is destructured onto the preference',
    () async {
      final storage = InMemoryAtClientStorage(atSign: atSign);
      final pref = preference();
      final client = await AuthService(
        atAuth: MockAtAuth(),
      ).createClient(session(), pref, storage: storage);

      expect(
        pref.rootDomain,
        'root.atsign.wtf',
        reason:
            'the client resolves the atSign against the atDirectory the '
            'session authenticated against, not against the default',
      );
      expect(pref.rootPort, 64);

      await client.stop();
      await storage.close();
    },
  );
}
