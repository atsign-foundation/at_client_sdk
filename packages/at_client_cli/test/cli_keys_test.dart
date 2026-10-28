import 'dart:io';

import 'package:at_client/hive.dart';
import 'package:at_client_cli/at_client_cli.dart';
import 'package:test/test.dart';

void main() {
  final home = Platform.environment['HOME']!;
  const atSign = '@alice';

  group('Given an atSign and no path', () {
    test('when its keyfile is asked for, then it is the home keys folder\'s',
        () {
      final keys = CliKeys.fileFor('alice');

      expect(keys.filePath!(atSign), '$home/.atsign/keys/@alice_key.atKeys');
      expect(keys.passPhrase, isNull);
    });

    test(
        'when its store is asked for, then it is under storage/<atSign>/'
        '<program>/single, and the client closes it', () {
      final store =
          CliKeys.storageFor(atSign, program: 'my_app') as HiveAtClientStorage;

      expect(store.storagePath, '$home/.atsign/storage/@alice/my_app/single');
      expect(store.closedByClient, isTrue);
    });

    test(
        'when CLIBase names no storage dir, then its store is the one CliKeys '
        'names for its namespace', () {
      final cli = CLIBase(
          atSign: atSign,
          nameSpace: 'my_app',
          rootDomain: 'root.atsign.org',
          homeDir: home);
      final store =
          CliKeys.storageFor(atSign, program: 'my_app') as HiveAtClientStorage;

      expect(cli.localStoragePathToUse, store.storagePath);
    });
  });

  group('Given a path', () {
    test(
        'when its keyfile is asked for, then it is there, under the passphrase',
        () {
      final keys =
          CliKeys.fileFor(atSign, path: '/keys/a.atKeys', passPhrase: 'secret');

      expect(keys.filePath!(atSign), '/keys/a.atKeys');
      expect(keys.passPhrase, 'secret');
    });

    test('when its store is asked for, then it is there', () {
      final store = CliKeys.storageFor(atSign,
          program: 'my_app',
          id: 'run1',
          path: '/stores/alice') as HiveAtClientStorage;

      expect(store.storagePath, '/stores/alice');
    });
  });

  test('Given an id, when the store is asked for, then the id names its folder',
      () {
    final store = CliKeys.storageFor(atSign, program: 'my_app', id: 'run1')
        as HiveAtClientStorage;

    expect(store.storagePath, '$home/.atsign/storage/@alice/my_app/run1');
  });
}
