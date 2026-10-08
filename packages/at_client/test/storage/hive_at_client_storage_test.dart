import 'dart:io';

import 'package:at_client/hive.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('at_client_hive_'));
  tearDown(() => dir.deleteSync(recursive: true));

  runStorageContract('hive',
      (atSign) => HiveAtClientStorage(atSign: atSign, storagePath: dir.path),
      breakOpen: (atSign) =>
          unreadable('${dir.path}/${AtUtils.getShaForAtSign(atSign)}.hive'));
}
