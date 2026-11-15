import 'package:at_client_wasm/src/keys/key_bytes_store.dart';

import 'key_bytes_store_contract.dart';

void main() {
  keyBytesStoreContract(
    'InMemoryKeyBytesStore',
    () async => InMemoryKeyBytesStore(),
  );
}
