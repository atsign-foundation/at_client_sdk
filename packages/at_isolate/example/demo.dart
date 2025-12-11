import 'dart:io' show exit;

import 'package:args/args.dart' show ArgParser;
import 'package:at_auth/at_auth.dart';
import 'package:at_isolate/at_isolate.dart';

void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption("root",
          abbr: 'r', help: 'root domain to use', mandatory: false)
      ..addOption('keysFilePath',
          abbr: 'k', help: 'Path of .atKeys file', mandatory: true);
    final argRes = parser.parse(args);
    final atSign = argRes["atsign"];
    final root = argRes.wasParsed("root")
        ? AtRootDomain.parse(argRes["root"])
        : AtRootDomain.atsignDomain;
    final atKeys = await FileAtKeysIo(filePath: (_) => argRes['keysFilePath'])
        .read(atSign);
    AtClient client = await IsolatedAtClient.spawn(atSign, root, atKeys);

    print("Got a client, and it's running in an isolate!");

    final keys = await client.getKeys();
    int i = 0;
    for (var k in keys) {
      print(k.toString());
      if (i++ >= 10) break;
    }
  } catch (e) {
    print("oops: $e");
    exit(1);
  }
}
