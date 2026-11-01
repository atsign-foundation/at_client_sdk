import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:flutter/material.dart';

import 'services/todos_service.dart';

const _namespace = TodosService.namespaceSuffix;
final _log = AtSignLogger('todos');
final KeychainStorage _keychain = KeychainStorage();

Future<bool> loginWithKeychain(BuildContext context) async {
  final atSigns = await _keychain.getAllAtsigns();
  if (!context.mounted) return false;
  if (atSigns.isEmpty) {
    _snack(context, 'No atSigns in keychain. Onboard one first.');
    return false;
  }

  final selection = await AtSignSelectionDialog.show(
    context,
    existingAtSigns: atSigns,
  );
  if (selection == null || !context.mounted) return false;
  if (!context.mounted) return false;
  final client = await PkamDialog.show(
    context,
    atSign: selection.atSign,
    rootDomain: selection.rootDomain,
    keys: KeychainAtKeysIo(),
    preference: todosPreference(),
  );
  if (client == null) return false;

  _adopt(client);
  return true;
}

Future<bool> loginWithFile(BuildContext context) async {
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return false;

  final atSign = atKeysIo.getAtsign();
  if (!context.mounted) return false;
  // backupKeys: the file's keys are copied into the keychain once the client
  // is open, so the next login can come from the keychain.
  final client = await PkamDialog.show(
    context,
    atSign: atSign,
    keys: atKeysIo,
    preference: todosPreference(),
    backupKeys: [KeychainAtKeysIo()],
  );
  if (client == null) return false;

  _adopt(client);
  return true;
}

Future<bool> loginWithApkam(BuildContext context) async {
  final selection = await AtSignSelectionDialog.show(context);
  if (selection == null || !context.mounted) return false;
  if (!context.mounted) return false;
  // The dialog submits the enrollment request, waits for an enrolled client
  // to approve it, and hands back the client that opens on the approved
  // keys. Those keys are filed in the keychain, which is also where a request
  // submitted earlier for this app and device is resumed from.
  final client = await ApkamActivationDialog.show(
    context,
    atSign: selection.atSign,
    rootDomain: selection.rootDomain,
    appName: _namespace,
    deviceName: 'default',
    namespaces: {_namespace: 'rw'},
    preference: todosPreference(),
    keys: KeychainAtKeysIo(),
  );
  if (client == null) return false;

  _adopt(client);
  return true;
}

/// Stops the current client, which this app owns, then clears it, so a
/// sign-in that follows meets no client still live for the old atSign.
Future<void> logout() async {
  final manager = AtClientManager.getInstance();
  await manager.atClient.stop();
  manager.reset();
}

/// The preference this app's client runs under: post-quantum, in the
/// namespace the CLI todos example shares todos in.
AtClientPreference todosPreference() =>
    AtClientPreference(posture: PqPosture.pqActive)..namespace = _namespace;

/// Every dialog hands back a client the app owns. This app keeps one current
/// client in [AtClientManager], since its screens read it from there.
void _adopt(AtClient client) {
  AtClientManager.getInstance().use(client);
  _log.info('atClient ready for ${client.getCurrentAtSign()}');
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
