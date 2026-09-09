import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('at_client_hive_'));
  tearDown(() => dir.deleteSync(recursive: true));

  runStorageContract('hive',
      (atSign) => HiveAtClientStorage(atSign: atSign, storagePath: dir.path));
}
