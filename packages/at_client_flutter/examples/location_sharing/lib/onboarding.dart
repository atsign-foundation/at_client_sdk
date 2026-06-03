import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'services/location_sharing_service.dart';

const _namespace = LocationSharingService.namespaceSuffix;
final _log = AtSignLogger('location_sharing');
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

  await _setupAtClient(authRequest, response);
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

  await _setupAtClient(authRequest, response);
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

  await _setupAtClient(authRequest, response);
  return true;
}

Future<void> logout() async {
  AtClientManager.getInstance().reset();
}

Future<void> _setupAtClient(
  AtAuthRequest authRequest,
  AuthResponse response,
) async {
  final dir = await getApplicationSupportDirectory();
  final acp = AtClientPreference()
    ..rootDomain = authRequest.rootDomain.rootDomain
    ..rootPort = authRequest.rootDomain.rootPort
    ..namespace = _namespace
    ..commitLogPath = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    _namespace,
    acp,
    enrollmentId: response.enrollmentId,
    atChops: response.atChops,
    atLookUp: response.atLookUp,
  );
  _log.info('atClient ready for ${response.atSign}');
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
