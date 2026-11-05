import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_path_provider.dart';

/// The CRAM and PKAM dialogs reach a client through [AtsignFlows], which
/// opens this package's default store for an app that passes none.
void main() {
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('app_support_');
    PathProviderPlatform.instance = FakePathProvider(support.path);
  });

  tearDown(() async {
    for (final client in List<AtClient>.from(
      AtClientImpl.atClientInstanceMap.values,
    )) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    support.deleteSync(recursive: true);
  });

  String encoded(String text) => base64Encode(utf8.encode(text));

  group('Given an app that passes no storage and sets no hiveStoragePath', () {
    test("when AtsignFlows.open runs, then the client's store opens in the app "
        'support directory', () async {
      const atSign = '@flowsopen';
      final keys = InMemoryAtKeysIo.holding(
        atSign,
        AtKeys.legacy(
          apkamPublicKey: encoded('apkam-public'),
          apkamPrivateKey: encoded('apkam-private'),
          encryptionPublicKey: encoded('encryption-public'),
          encryptionPrivateKey: encoded('encryption-private'),
          selfEncryptionKey: encoded('self'),
        ),
      );

      try {
        await const AtsignFlows().open(
          atSign,
          keys: keys,
          preference: AtClientPreference(),
        );
      } on Object {
        // NOTE: what happens once the store is open is not under test.
      }

      final queue = File(
        '${support.path}/syncqueue_${AtUtils.getShaForAtSign(atSign)}.hive',
      );
      expect(
        queue.existsSync(),
        isTrue,
        reason:
            'given no storage, the client opens Hive where an app that '
            'followed at_client_mobile\'s examples keeps its store',
      );
    });

    test('when AtsignFlows.activate runs, then it reaches the atServer rather '
        'than being refused for want of storage', () async {
      var connectionsAsked = 0;

      await expectLater(
        const AtsignFlows().activate(
          '@flowsactivate',
          cramSecret: 'secret',
          keys: InMemoryAtKeysIo(),
          preference: AtClientPreference(),
          lookUps:
              ({
                required String atSign,
                required AtRootDomain rootDomain,
                required AtAuthenticator? authenticator,
                SecondaryAddressFinder? secondaryAddressFinder,
              }) {
                connectionsAsked++;
                throw StateError('the atServer was asked for');
              },
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        connectionsAsked,
        1,
        reason:
            'refused for want of storage, the activation never asks for '
            'its connection',
      );
    });
  });
}
