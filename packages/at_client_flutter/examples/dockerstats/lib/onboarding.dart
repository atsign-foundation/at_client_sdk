import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'services/dockerstats_service.dart';

const _namespace = applicationNamespace;
final _log = AtSignLogger('dockerstats');
final KeychainStorage _keychain = KeychainStorage();

Future<bool> loginWithKeychain(BuildContext context) async {
  final atSigns = await _keychain.getAllAtsigns();
  if (!context.mounted) return false;
  if (atSigns.isEmpty) {
    _snack(context, 'No atSigns in keychain. Onboard one first.');
    return false;
  }

  final request = await AtSignSelectionDialog.show(
    context,
    existingAtSigns: atSigns,
  );
  if (request == null || !context.mounted) return false;

  final authRequest = AtAuthRequest(
    request.atSign,
    atKeysIo: KeychainAtKeysIo(),
    rootDomain: request.rootDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  final session = response?.session;
  if (session == null) return false;

  await _setupAtClient(session);
  return true;
}

Future<bool> loginWithFile(BuildContext context) async {
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return false;

  final authRequest = AtAuthRequest(
    atKeysIo.getAtsign(),
    atKeysIo: atKeysIo,
    rootDomain: AtRootDomain.atsignDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  final session = response?.session;
  if (session == null) return false;

  await _setupAtClient(session);
  return true;
}

Future<bool> loginWithApkam(BuildContext context) async {
  final request = await AtSignSelectionDialog.show(context);
  if (request == null || !context.mounted) return false;

  final enrollmentResponse = await ApkamActivationDialog.show(
    context,
    atSign: request.atSign,
    rootDomain: request.rootDomain,
    appName: _namespace,
    deviceName: 'default',
    namespaces: {_namespace: 'rw'},
    // Where this enrollment's keys land. The enrolled app holds the only
    // copy, so the destination is the app's choice; at_auth writes the
    // completed keyset there once the approval releases it.
    atKeysIo: KeychainAtKeysIo(),
  );
  final enrolled = enrollmentResponse?.session;
  if (enrolled == null || !context.mounted) return false;

  final authRequest = AtAuthRequest(
    request.atSign,
    atKeysIo: enrolled.atKeysIo,
    rootDomain: request.rootDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  final session = response?.session;
  if (session == null) return false;

  await _setupAtClient(session);
  return true;
}

Future<void> logout() async {
  AtClientManager.getInstance().reset();
}

/// Every flow here hands authentication a key source, so it always answers
/// with a session — and the client rebuilds its own connection from the
/// session's source rather than adopting auth's live objects.
Future<void> _setupAtClient(AtAuthSession session) async {
  final dir = await getApplicationSupportDirectory();
  final acp = AtClientPreference()
    ..namespace = _namespace
    ..fetchOfflineNotifications = false;
  // closedByClient: the app picks the backend and the location, and the client
  // still closes the store when it stops, so there is nothing to tear down.
  final storage = HiveAtClientStorage(
    atSign: session.atSign,
    storagePath: dir.path,
    closedByClient: true,
  );

  await AtClientManager.getInstance().fromAuthSession(
    session,
    acp,
    storage: storage,
  );
  _log.info('atClient ready for ${session.atSign}');
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
