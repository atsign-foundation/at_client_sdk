import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// What an app reaches through `package:at_client_flutter` alone.
void main() {
  test('HiveAtClientStorage comes through package:at_client_flutter, as it did '
      'in 2.0.0-rc4', () {
    final storage = HiveAtClientStorage(
      atSign: '@alice',
      storagePath: '/nowhere',
    );

    expect(
      storage,
      isA<AtClientStorage>(),
      reason:
          'an app written against 2.0.0-rc4 builds its Hive store with '
          'this package as its only import',
    );
  });
}
