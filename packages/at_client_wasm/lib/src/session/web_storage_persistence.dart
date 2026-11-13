import 'dart:js_interop';

import 'package:web/web.dart';

import 'passkey_custody.dart';

/// [StoragePersistence] over `navigator.storage.persist()`.
class WebStoragePersistence implements StoragePersistence {
  @override
  Future<bool> requestPersist() => window.navigator.storage
      .persist()
      .toDart
      .then((granted) => granted.toDart);
}
