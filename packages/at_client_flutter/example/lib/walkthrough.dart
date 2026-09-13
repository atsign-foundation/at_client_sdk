import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:example/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

final namespace = 'at_client_flutter_example';
final AtSignLogger _logger = AtSignLogger(namespace);
final RegistrarService registrar = RegistrarService(
  registrarUrl: "my.atsign.com",
  apiKey: "477b-876u-bcez-c42z-6a3d",
);

final KeychainStorage keychainStorage = KeychainStorage();

/// Helper function to safely execute async operations with comprehensive error logging
Future<T?> _safeExecute<T>(
  String operationName,
  Future<T> Function() operation,
) async {
  try {
    _logger.info('Starting operation: $operationName');
    final result = await operation();
    _logger.info('Completed operation: $operationName');
    return result;
  } catch (e, stackTrace) {
    _logger.severe('ERROR in $operationName: $e');
    _logger.severe('Stack trace: $stackTrace');
    return null;
  }
}

/// This method is an example of how an application creates their own customized onboarding flow
Future<void> onboard(BuildContext context) async {
  await _safeExecute('onboard', () async {
    _logger.info('Step 1: Showing AtSignSelectionDialog');
    final selection = await AtSignSelectionDialog.show(context);
    if (!context.mounted || selection == null) {
      _logger.warning(
        'User cancelled or context not mounted after AtSignSelectionDialog',
      );
      return;
    }

    _logger.info('Step 2: Showing RegistrarCramDialog for ${selection.atSign}');
    var cramKey = await RegistrarCramDialog.show(
      context,
      selection.atSign,
      registrar: registrar,
    );
    if (!context.mounted || cramKey == null) {
      _logger.warning(
        'User cancelled or context not mounted after RegistrarCramDialog',
      );
      return;
    }

    final storage = await _storage(selection.atSign);
    if (!context.mounted) return;

    _logger.info('Step 3: Showing CramDialog to complete onboarding');
    // The activation writes the atSign's first keys to the keychain and
    // opens a client on them; the app owns that client.
    final client = await CramDialog.show(
      context,
      atSign: selection.atSign,
      rootDomain: selection.rootDomain,
      cramKey: cramKey,
      preference: _preference(),
      storage: storage,
    );
    if (client == null) {
      _logger.warning('CramDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 4: Making the client current');
    await _adopt(context, client);
  });
}

/// Authenticate using an atSign stored in the keychain
Future<void> authenticateWithKeychain(BuildContext context) async {
  await _safeExecute('authenticateWithKeychain', () async {
    _logger.info('Step 1: Loading atSigns from keychain');
    var atSigns = await keychainStorage.getAllAtsigns();
    _logger.info('Found ${atSigns.length} atSigns in keychain: $atSigns');

    if (atSigns.isEmpty) {
      _logger.warning('No atSigns found in keychain');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No atSigns found in keychain. Please onboard first.',
            ),
          ),
        );
      }
      return;
    }

    _logger.info('Step 2: Showing AtSignSelectionDialog with existing atSigns');
    final selection = await AtSignSelectionDialog.show(
      context,
      existingAtSigns: atSigns,
    );
    if (selection == null) {
      _logger.warning('User cancelled AtSignSelectionDialog');
      return;
    }

    final storage = await _storage(selection.atSign);
    if (!context.mounted) return;

    _logger.info('Step 3: Showing PkamDialog, opening on the keychain');
    final client = await PkamDialog.show(
      context,
      atSign: selection.atSign,
      rootDomain: selection.rootDomain,
      keys: KeychainAtKeysIo(),
      preference: _preference(),
      storage: storage,
    );
    if (client == null) {
      _logger.warning('PkamDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 4: Making the client current');
    await _adopt(context, client);
  });
}

/// Authenticate using an atKeys file from the file system
Future<void> authenticateWithFile(BuildContext context) async {
  await _safeExecute('authenticateWithFile', () async {
    _logger.info('Step 1: Showing AtKeysFileDialog');
    FileAtKeysIo? atKeysIo = await AtKeysFileDialog.show(context);

    if (atKeysIo == null) {
      _logger.warning('User cancelled file selection');
      return;
    }

    _logger.info('Step 2: Processing selected file');
    final atSign = atKeysIo.getAtsign();
    _logger.info('Extracted atSign from filename: $atSign');

    final storage = await _storage(atSign);
    if (!context.mounted) return;

    _logger.info('Step 3: Showing PkamDialog, opening on the file');
    // backupKeys: the file's keys are copied into the keychain once the
    // client is open, so the next login can come from the keychain.
    final client = await PkamDialog.show(
      context,
      atSign: atSign,
      keys: atKeysIo,
      preference: _preference(),
      storage: storage,
      backupKeys: [KeychainAtKeysIo()],
    );
    if (client == null) {
      _logger.warning('PkamDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 4: Making the client current');
    await _adopt(context, client);
  });
}

Future<void> authenticateWithApkam(BuildContext context) async {
  await _safeExecute('authenticateWithApkam', () async {
    _logger.info('Step 1: Showing AtSignSelectionDialog');
    final selection = await AtSignSelectionDialog.show(context);
    if (selection == null) {
      _logger.warning('User cancelled AtSignSelectionDialog');
      return;
    }

    final storage = await _storage(selection.atSign);
    if (!context.mounted) return;

    _logger.info(
      'Step 2: Showing ApkamActivationDialog for ${selection.atSign}',
    );
    // The dialog submits the enrollment request, waits for an enrolled client
    // to approve it, and hands back the client that opens on the approved
    // keys. Those keys are filed in the keychain, which is also where a
    // request submitted earlier for this app and device is resumed from.
    final client = await ApkamActivationDialog.show(
      context,
      atSign: selection.atSign,
      rootDomain: selection.rootDomain,
      appName: namespace,
      deviceName: 'default',
      namespaces: {namespace: 'rw'},
      preference: _preference(),
      keys: KeychainAtKeysIo(),
      storage: storage,
    );
    if (client == null) {
      _logger.warning('ApkamActivationDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 3: Making the client current');
    await _adopt(context, client);
  });
}

Future<void> exportKeys(BuildContext context) async {
  await _safeExecute('exportKeys', () async {
    _logger.info('Checking if atClient is initialized');

    final atsign = AtClientManager.getInstance().atClient.getCurrentAtSign()!;
    _logger.info('Exporting keys for: $atsign');

    final filePath = await _openFileSaveDialog(
      suggestedFileName: '${atsign}_key.atKeys',
      fileExtension: '.atKeys',
      allowedExtensions: ['atKeys'],
    );

    if (filePath == null) {
      _logger.warning('User cancelled file save dialog');
      return;
    }

    _logger.info('Selected save path: $filePath');
    FileAtKeysIo atKeysIo = FileAtKeysIo(filePath: (_) => filePath);

    _logger.info('Retrieving keys from keychain');
    var atKeys = await keychainStorage.getAtsign(atsign);

    if (atKeys == null) {
      _logger.severe('No keys found in keychain for $atsign');
      throw Exception('No keys found in keychain for $atsign');
    }

    _logger.info('Writing keys to file');
    atKeysIo.write(atsign, atKeys);
    _logger.info('Keys exported successfully');

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Keys exported to $filePath')));
    }
  });
}

/// Opens a file save dialog and returns the selected file path.
Future<String?> _openFileSaveDialog({
  String? suggestedFileName,
  String? fileExtension,
  List<String>? allowedExtensions,
}) async {
  try {
    _logger.info('Opening file save dialog');
    // Open save file dialog
    String? outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save File',
      fileName: suggestedFileName ?? 'document.txt',
      type: FileType.custom,
      allowedExtensions: allowedExtensions ?? ['txt', 'pdf', 'json'],
    );

    // User cancelled the dialog
    if (outputPath == null) {
      _logger.info('User cancelled file save dialog');
      return null;
    }

    // Ensure the file has the correct extension if specified
    if (fileExtension != null && !outputPath.endsWith(fileExtension)) {
      outputPath = '$outputPath$fileExtension';
      _logger.info('Added extension to path: $outputPath');
    }

    return outputPath;
  } catch (e, stackTrace) {
    _logger.severe('Error opening file save dialog: $e');
    _logger.severe('Stack trace: $stackTrace');
    return null;
  }
}

AtClientPreference _preference() => AtClientPreference()..namespace = namespace;

/// Where this app keeps [atSign]'s local store. closedByClient: this app
/// picks the location and the client still closes the store when it stops,
/// so there is nothing to tear down.
Future<HiveAtClientStorage> _storage(String atSign) async {
  var dir = await getApplicationSupportDirectory();
  _logger.info('Application support directory: ${dir.path}');
  return HiveAtClientStorage(
    atSign: atSign,
    storagePath: dir.path,
    closedByClient: true,
  );
}

/// Every dialog hands back a client the app owns. This app keeps one current
/// client in [AtClientManager], since its pages read it from there, then
/// navigates to the home page.
Future<void> _adopt(BuildContext context, AtClient client) async {
  _logger.info('Making the client for ${client.getCurrentAtSign()} current');
  AtClientManager.getInstance().use(client);

  if (context.mounted) {
    _logger.info('Navigating to HomePage');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  } else {
    _logger.warning('Context not mounted, skipping navigation');
  }
}

/// remove all atsigns from the keychain
Future<void> clearAllAtsigns() async {
  await _safeExecute('clearAllAtsigns', () async {
    _logger.info('Clearing all atSigns from keychain');
    await keychainStorage.deleteAllAtKeysData();
    _logger.info('All atSigns cleared successfully');
  });
}

/// This is an example of writing your own dialog to remove an atsign from the keychain
Future<void> removeAtsign(BuildContext context) async {
  await _safeExecute('removeAtsign', () async {
    _logger.info('Getting all atSigns for removal dialog');
    var items = await keychainStorage.getAllAtsigns();
    _logger.info('Found ${items.length} atSigns: $items');

    if (items.isEmpty) {
      _logger.warning('No atSigns to remove');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No atSigns found in keychain')),
        );
      }
      return;
    }

    String? atsign = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select an atSign to clear'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                return ListTile(
                  title: Text(items[index]),
                  onTap: () {
                    Navigator.pop(context, items[index]);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (atsign != null) {
      _logger.info('Removing atSign: $atsign');
      await keychainStorage.removeAtsignFromKeychain(atsign);
      _logger.info('atSign removed successfully');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $atsign from keychain')),
        );
      }
    } else {
      _logger.info('User cancelled atSign removal');
    }
  });
}
