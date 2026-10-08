import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_path_provider.dart';

class MockAtClient extends Mock implements AtClient {}

/// An app passing no storage gets a Hive store this package chooses, where an
/// app that set `hiveStoragePath` to its support directory already keeps one.
void main() {
  late Directory support;
  setUp(() {
    support = Directory.systemTemp.createTempSync('app_support_');
    PathProviderPlatform.instance = FakePathProvider(support.path);
  });
  tearDown(() => support.deleteSync(recursive: true));

  MockAtClient clientOf(String atSign) {
    final client = MockAtClient();
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.enrollmentId).thenReturn(null);
    return client;
  }

  test('storage the app passes is used as it is', () async {
    final passed = HiveAtClientStorage(
      atSign: '@alice',
      storagePath: support.path,
    );
    expect(
      await storageOrDefault('@alice', AtClientPreference(), passed),
      same(passed),
    );
  });

  test('with none passed, Hive in the app support directory', () async {
    final storage = await storageOrDefault('Alice', AtClientPreference(), null);
    expect(
      storage,
      isA<HiveAtClientStorage>()
          .having((s) => s.storagePath, 'storagePath', support.path)
          .having((s) => s.atSign, 'atSign', '@alice')
          .having((s) => s.closedByClient, 'closedByClient', isTrue),
    );
  });

  test('hiveStoragePath still wins while it is set', () async {
    final elsewhere = '${support.path}/elsewhere';
    // ignore: deprecated_member_use
    final preference = AtClientPreference()..hiveStoragePath = elsewhere;
    final storage = await storageOrDefault('@alice', preference, null);
    expect(
      storage,
      isA<HiveAtClientStorage>().having(
        (s) => s.storagePath,
        'storagePath',
        elsewhere,
      ),
    );
  });

  test('no store when the preference asks for none', () async {
    // ignore: deprecated_member_use
    final preference = AtClientPreference()..isLocalStoreRequired = false;
    expect(await storageOrDefault('@alice', preference, null), isNull);
  });

  test('a store kept in the support directory is found', () async {
    // NOTE: written as at_client's own default writes it for an app that set
    // hiveStoragePath to its support directory.
    final before = HiveAtClientStorage(
      atSign: '@alice',
      storagePath: support.path,
      closedByClient: true,
    );
    await before.attach(clientOf('@alice'));
    await before.keyStore.put('phone.wavi@alice', AtData()..data = 'kept');
    await before.close();

    final after = (await storageOrDefault(
      'alice',
      AtClientPreference(),
      null,
    ))!;
    addTearDown(after.close);
    await after.attach(clientOf('@alice'));

    expect(
      (await after.keyStore.get('phone.wavi@alice'))?.data,
      'kept',
      reason: 'upgrading must not leave an app with an empty store',
    );
  });
}
