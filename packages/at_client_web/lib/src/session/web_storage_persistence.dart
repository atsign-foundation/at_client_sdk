import 'dart:js_interop';

import 'package:at_client/passkey.dart' show StoragePersistence;
import 'package:web/web.dart';

/// [StoragePersistence] over `navigator.storage.persist()`.
class WebStoragePersistence implements StoragePersistence {
  @override
  Future<bool> requestPersist() => window.navigator.storage
      .persist()
      .toDart
      .then((granted) => granted.toDart);
}
