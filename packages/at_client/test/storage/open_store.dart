import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';

import 'storage_contract.dart';

/// Opens a Hive store at the path it is given and prints what happened:
/// `opened`, or the refusal's type and location, then exits at once.
Future<void> main(List<String> args) async {
  final store = HiveAtClientStorage(
      atSign: '@holder'.toAtsign(), storagePath: args.single);
  try {
    await store.attach(FakeClient('@holder', 'e2'));
    stdout.writeln('opened');
  } on AtStorageInUseException catch (e) {
    stdout.writeln('AtStorageInUseException ${e.location}');
  } catch (e) {
    stdout.writeln('${e.runtimeType}');
  }
  await stdout.flush();
  exit(0);
}
