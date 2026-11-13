import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:flutter/material.dart';

import 'services/location_sharing_service.dart';

const _namespace = LocationSharingService.namespaceSuffix;
final KeychainStorage _keychain = KeychainStorage();

/// Fast re-login for an atSign this device has already onboarded.
Future<AtClient?> loginWithKeychain(BuildContext context) async {
  final atSigns = await _keychain.getAllAtsigns();
  if (!context.mounted) return null;
  if (atSigns.isEmpty) {
    _snack(context, 'No atSigns in keychain. Onboard one first.');
    return null;
  }

  final selection = await AtSignSelectionDialog.show(
    context,
    existingAtSigns: atSigns,
  );
  if (selection == null || !context.mounted) return null;

  return PkamDialog.show(
    context,
    atSign: selection.atSign,
    rootDomain: selection.rootDomain,
    keys: KeychainAtKeysIo(),
    preference: _preference(),
  );
}

/// First-launch path: open an atSign from its `.atKeys` file, then back the
/// keys up to the keychain so the next login can use [loginWithKeychain].
Future<AtClient?> loginWithFile(BuildContext context) async {
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return null;

  final atSign = atKeysIo.getAtsign();
  if (!context.mounted) return null;
  return PkamDialog.show(
    context,
    atSign: atSign,
    keys: atKeysIo,
    preference: _preference(),
    backupKeys: [KeychainAtKeysIo()],
  );
}

AtClientPreference _preference() =>
    AtClientPreference()..namespace = _namespace;

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
