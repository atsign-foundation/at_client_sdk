import 'package:at_client/src/storage/local_record_store.dart';

import 'local_record_store_contract.dart';

void main() {
  localRecordStoreContract(
      'InMemoryLocalRecordStore', () async => InMemoryLocalRecordStore());
}
