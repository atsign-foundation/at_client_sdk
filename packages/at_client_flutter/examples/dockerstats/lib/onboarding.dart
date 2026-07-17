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
  if (response == null || !response.isSuccessful) return false;

  await _setupAtClient(response.session!, reuse: true);
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
  if (response == null || !response.isSuccessful) return false;

  await _setupAtClient(response.session!, reuse: true);
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
  );
  if (enrollmentResponse?.atAuthKeys == null || !context.mounted) return false;

  final authRequest = AtAuthRequest(
    request.atSign,
    atAuthKeys: enrollmentResponse!.atAuthKeys!,
    rootDomain: request.rootDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return false;

  await _setupAtClient(response.session!, reuse: true);
  return true;
}

Future<void> logout() async {
  AtClientManager.getInstance().reset();
}

Future<void> _setupAtClient(AtAuthSession session, {bool reuse = false}) async {
  final dir = await getApplicationSupportDirectory();
  final acp = AtClientPreference()
    ..namespace = _namespace
    ..commitLogPath = dir.path
    ..hiveStoragePath = dir.path
    ..fetchOfflineNotifications = false;

  // Hand the client the session, not auth's live AtChops. Passing [reuse] lets
  // the client adopt auth's already-authenticated AtLookUp so it skips a second
  // PKAM handshake; omit it to have the client open its own fresh connection.
  await AtClientManager.getInstance().setFromAuthSession(
    session,
    acp,
    reuse: reuse,
  );
  _log.info('atClient ready for ${session.atSign}');
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
