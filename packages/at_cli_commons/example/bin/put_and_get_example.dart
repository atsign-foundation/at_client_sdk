import 'dart:io';

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
  try {
    AtClient atClient = (await CLIBase.fromCommandLineArgs(args)).atClient;

    String example = 'put_and_get_example';
    AtKey id = AtKey()
      ..namespace = atClient.getPreferences()!.namespace!
      ..key = example
      ..sharedBy = atClient.getCurrentAtSign();

    // Store it. Will talk direct to the remote atServer rather than use the
    // local datastore, so we don't have to wait for a local-to-atServer sync
    // to complete.
    PutRequestOptions pro = PutRequestOptions()..useRemoteAtServer = true;
    await atClient.put(id, 'hello, world', putRequestOptions: pro);

    var scanResult = (await atClient
            .getRemoteSecondary()!
            .executeCommand('scan $example\n'))!
        .replaceFirst(RegExp(r'^data:'), '');
    print("Stored to: $scanResult");

    print('Fetching $id');

    // Fetch it direct from remote
    var asStored =
        (await atClient.getRemoteSecondary()!.executeCommand('llookup:$id\n'))!
            .replaceFirst(RegExp(r'^data:'), '');
    print('As stored: $asStored');

    // Fetch it from local
    print("Decrypted: ${(await atClient.get(id)).value}");

    exit(0);
  } catch (e) {
    print(e);
    print(CLIBase.argsParser.usage);
  }
}
