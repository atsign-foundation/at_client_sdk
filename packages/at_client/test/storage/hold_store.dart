import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';

import 'storage_contract.dart';

/// Holds a Hive store open at the path it is given: prints `held` once it is
/// open, and closes it when its stdin closes.
Future<void> main(List<String> args) async {
  final store = HiveAtClientStorage(
      atSign: '@holder'.toAtsign(), storagePath: args.single);
  await store.attach(FakeClient('@holder', 'e1'));
  stdout.writeln('held');
  await stdin.drain<void>();
  await store.close();
}
