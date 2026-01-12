import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';

/// put_and_get_example.dart
///
/// <br/>
/// - Create an atClient
/// - store some private data
/// - fetch it back as it is stored
/// - fetch it back and decrypt it
Future<void> main(List<String> args) async {
  final ArgParser parser = CLIBase.createArgsParser(
      namespace: 'example', addLegacyRootDomainArg: false);
  try {
    AtClient atClient =
        (await CLIBase.fromCommandLineArgs(args, parser: parser)).atClient;

    String example = 'put_and_get_example';
    AtKey id = AtKey()
      ..namespace = atClient.getPreferences()!.namespace!
      ..key = example
      ..sharedBy = atClient.getCurrentAtSign()
      ..metadata = (Metadata()..ttl = 5000); // ttl 5 seconds

    // Store it. Will talk direct to the remote atServer rather than use the
    // local datastore, so we don't have to wait for a local-to-atServer sync
    // to complete.
    PutRequestOptions pro = PutRequestOptions()..useRemoteAtServer = true;
    await atClient.put(id, 'hello, world', putRequestOptions: pro);

    var scanResult =
        (await atClient.getAtKeys(regex: example, useRemoteAtServer: true));
    print("Stored to: $scanResult");

    print('Fetching $id');

    // Fetch it via atProtocol llookup command
    var asStored =
        (await atClient.getRemoteSecondary()!.executeCommand('llookup:$id\n'))!
            .replaceFirst(RegExp(r'^data:'), '');
    print('As stored: $asStored');

    // Fetch it via atClient
    GetRequestOptions gro = GetRequestOptions()..useRemoteAtServer = true;
    print(
        "Decrypted: ${(await atClient.get(id, getRequestOptions: gro)).value}");

    await atClient.delete(id,
        deleteRequestOptions: DeleteRequestOptions()..useRemoteAtServer = true);
    exit(0);
  } catch (e, st) {
    print(e);
    if (e is ArgumentError || e is FormatException) {
      print(parser.usage);
    } else {
      print('Stack Trace:\n$st');
    }
    exit(1);
  }
}
