@TestOn('browser')
library;

import 'package:at_client_wasm/src/session/web_storage_persistence.dart';
import 'package:test/test.dart';

void main() {
  test('requestPersist answers whether the browser granted persistence',
      () async {
    expect(await WebStoragePersistence().requestPersist(), isA<bool>());
  });
}
