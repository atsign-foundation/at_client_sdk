import 'dart:io';

import 'package:at_client/memory.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/default_storage.dart';
import 'package:test/test.dart';

import 'storage_contract.dart' show FakeClient;

/// The storage a client opens when it is given none, and what the client
/// reads about it before and after it opens.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('default_storage_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('its location is read without creating the directory', () {
    final dir = '${root.path}/not/there/yet';

    defaultStorageLocation('@alice', dir);

    expect(Directory(dir).existsSync(), isFalse,
        reason: 'reading where a store would go must not make it');
  });

  test('the location read beforehand is the open store\'s own', () async {
    final dir = '${root.path}/store';
    final storage = defaultStorageFor('@alice', dir) as AtClientStorageBase;
    addTearDown(storage.close);
    await storage.attach(FakeClient('@alice', 'e1'));

    expect(defaultStorageLocation('@alice', dir), storage.location,
        reason: 'a second client on this store is refused by its location, '
            'so the two must agree');
  });

  test('its persistence bundle is answered for it and for nothing else',
      () async {
    final storage = defaultStorageFor('@alice', '${root.path}/store');
    addTearDown(storage.close);
    await storage.attach(FakeClient('@alice', 'e1'));
    final other = InMemoryAtClientStorage(atSign: '@bob');
    addTearDown(other.close);
    await other.attach(FakeClient('@bob', 'e1'));

    expect(defaultStorageBundle(storage), isNotNull);
    expect(defaultStorageBundle(other), isNull);
    expect(defaultStorageBundle(null), isNull);
  });
}
