import 'package:example/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_auth/at_auth.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:at_utils/at_logger.dart' show AtSignLogger;

final namespace = 'at_client_flutter_example';
final AtSignLogger _logger = AtSignLogger(namespace);
final RegistrarService registrar = RegistrarService(
  registrarUrl: "my.atsign.com",
  apiKey: "plsprovideownapi",
);

final KeychainStorage keychainStorage = KeychainStorage();

/// Helper function to safely execute async operations with comprehensive error logging
Future<T?> _safeExecute<T>(
  String operationName,
  Future<T> Function() operation, {
  BuildContext? context,
  bool showErrorDialog = true,
}) async {
  try {
    _logger.info('Starting operation: $operationName');
    final result = await operation();
    _logger.info('Completed operation: $operationName');
    return result;
  } catch (e, stackTrace) {
    _logger.severe('ERROR in $operationName: $e');
    _logger.severe('Stack trace: $stackTrace');

    if (context != null && context.mounted && showErrorDialog) {
      _showErrorDialog(context, operationName, e, stackTrace);
    }

    return null;
  }
}

/// Show a detailed error dialog
void _showErrorDialog(
  BuildContext context,
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Error Occurred'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Operation: $operation'),
            const SizedBox(height: 8),
            Text('Error Type: ${error.runtimeType}'),
            const SizedBox(height: 8),
            const Text(
              'Details:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(error.toString()),
            const SizedBox(height: 8),
            const Text(
              'Stack Trace:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              stackTrace.toString(),
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// This method is an example of how an application creates their own customized onboarding flow
Future<void> onboard(BuildContext context) async {
  await _safeExecute('onboard', () async {
    _logger.info('Step 1: Showing AtSignSelectionDialog');
    AuthRequest? authRequest = await AtSignSelectionDialog.show(context);
    if (!context.mounted || authRequest == null) {
      _logger.warning(
        'User cancelled or context not mounted after AtSignSelectionDialog',
      );
      return;
    }

    _logger.info(
      'Step 2: Showing RegistrarCramDialog for ${authRequest.atSign}',
    );
    var cramKey = await RegistrarCramDialog.show(
      context,
      (authRequest as AtOnboardingRequest),
      registrar: registrar,
    );
    if (!context.mounted || cramKey == null) {
      _logger.warning(
        'User cancelled or context not mounted after RegistrarCramDialog',
      );
      return;
    }

    _logger.info('Step 3: Showing CramDialog to complete onboarding');
    var response = await CramDialog.show(
      context,
      request: authRequest,
      cramKey: cramKey,
    );
    if (response == null || !response.isSuccessful) {
      _logger.warning('CramDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 5: Setting up atClient instance');
    // 5. very important! now that we have authenticated, we can create an atClient instance
    var dir = await getApplicationSupportDirectory();
    _logger.info('Application support directory: ${dir.path}');

    var acp = AtClientPreference()
      ..rootDomain = authRequest.rootDomain.rootDomain
      ..rootPort = authRequest.rootDomain.rootPort
      ..namespace = namespace
      ..commitLogPath = dir.path
      ..hiveStoragePath = dir.path;

    _logger.info('Setting current atSign: ${response.atSign}');
    // make sure to use the atChops and atLookUp provided by the response as these are already authenticated.
    await AtClientManager.getInstance().setCurrentAtSign(
      response.atSign,
      namespace,
      enrollmentId: response.enrollmentId,
      acp,
      atChops: response.atChops,
      atLookUp: response.atLookUp,
    );

    _logger.info('Navigation to HomePage');
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }, context: context);
}

/// Login using an atSign stored in the keychain
Future<void> loginWithKeychain(BuildContext context) async {
  await _safeExecute('loginWithKeychain', () async {
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
    AuthRequest? request = await AtSignSelectionDialog.show(
      context,
      existingAtSigns: atSigns,
    );
    if (request == null) {
      _logger.warning('User cancelled AtSignSelectionDialog');
      return;
    }

    _logger.info(
      'Step 3: Creating AuthRequest with KeychainAtKeysIo for ${request.atSign}',
    );
    var authRequest = AtAuthRequest(
      request.atSign,
      atKeysIo: KeychainAtKeysIo(),
      rootDomain: request.rootDomain,
    );

    _logger.info('Step 4: Showing PkamDialog');
    var response = await PkamDialog.show(
      context,
      request: authRequest,
      backupKeys: [KeychainAtKeysIo()],
    );
    if (response == null || !response.isSuccessful) {
      _logger.warning('PkamDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 5: Setting up atClient');
    await _setupAtClient(context, authRequest, response);
  }, context: context);
}

/// Login using an atKeys file from the file system
Future<void> loginWithFile(BuildContext context) async {
  await _safeExecute('loginWithFile', () async {
    _logger.info('Step 1: Showing AtKeysFileDialog');
    FileAtKeysIo? atKeysIo = await AtKeysFileDialog.show(context);

    if (atKeysIo == null) {
      _logger.warning('User cancelled file selection');
      return;
    }

    _logger.info('Step 2: Processing selected file');
    var atSign = atKeysIo.getAtsign();
    _logger.info('Extracted atSign from filename: $atSign');

    _logger.info('Step 3: Creating AuthRequest with file-based AtKeysIo');
    var authRequest = AtAuthRequest(
      atSign,
      atKeysIo: atKeysIo,
      rootDomain: AtRootDomain.atsignDomain,
    );

    _logger.info('Step 4: Showing PkamDialog');
    var response = await PkamDialog.show(
      context,
      request: authRequest,
      backupKeys: [KeychainAtKeysIo()],
    );
    if (response == null || !response.isSuccessful) {
      _logger.warning('PkamDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 5: Setting up atClient');
    await _setupAtClient(context, authRequest, response);
  }, context: context);
}

Future<void> loginWithApkam(BuildContext context) async {
  await _safeExecute('loginWithApkam', () async {
    _logger.info('Step 1: Showing AtSignSelectionDialog');
    AuthRequest? request = await AtSignSelectionDialog.show(context);
    if (request == null) {
      _logger.warning('User cancelled AtSignSelectionDialog');
      return;
    }

    _logger.info('Step 2: Showing ApkamActivationDialog for ${request.atSign}');
    AtEnrollmentResponse? enrollmentResponse = await ApkamActivationDialog.show(
      context,
      atSign: request.atSign,
      rootDomain: request.rootDomain,
      appName: namespace,
      deviceName: 'default',
      namespaces: {namespace: 'rw'},
    );

    if (enrollmentResponse == null) {
      _logger.severe('Enrollment failed: enrollmentResponse is null');
      throw AtAuthenticationException(
        "Enrollment failed: enrollmentResponse is null",
      );
    }

    if (enrollmentResponse.atAuthKeys == null) {
      _logger.severe('Enrollment failed: atAuthKeys missing');
      throw AtAuthenticationException('Enrollment failed: atAuthKeys missing');
    }

    _logger.info('Step 3: Creating AuthRequest with atAuthKeys');
    AtAuthRequest authRequest = AtAuthRequest(
      request.atSign,
      atAuthKeys: enrollmentResponse.atAuthKeys!,
      rootDomain: request.rootDomain,
    );
    _logger.info('Step 4: Showing PkamDialog');
    var response = await PkamDialog.show(
      context,
      request: authRequest,
      backupKeys: [KeychainAtKeysIo()],
    );
    if (response == null || !response.isSuccessful) {
      _logger.warning('PkamDialog failed or user cancelled');
      return;
    }

    _logger.info('Step 5: Setting up atClient');
    await _setupAtClient(context, authRequest, response);
  }, context: context);
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
  }, context: context);
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
    String? outputPath = await FilePicker.platform.saveFile(
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

/// Helper method to set up the atClient instance and navigate to home page
Future<void> _setupAtClient(
  BuildContext context,
  AtAuthRequest authRequest,
  AuthResponse response,
) async {
  _logger.info('Setting up atClient for ${response.atSign}');

  var dir = await getApplicationSupportDirectory();
  _logger.info('Using directory: ${dir.path}');

  var acp = AtClientPreference()
    ..rootDomain = authRequest.rootDomain.rootDomain
    ..rootPort = authRequest.rootDomain.rootPort
    ..namespace = namespace
    ..commitLogPath = dir.path
    ..hiveStoragePath = dir.path;

  _logger.info('AtClientPreference configured:');
  _logger.info('  - rootDomain: ${acp.rootDomain}');
  _logger.info('  - rootPort: ${acp.rootPort}');
  _logger.info('  - namespace: ${acp.namespace}');
  if (response.enrollmentId == null) {
    _logger.warning("EnrollmentId is null");
  }
  // Make sure to use the atChops and atLookUp provided by the response
  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    namespace,
    acp,
    enrollmentId: response.enrollmentId,
    atChops: response.atChops,
    atLookUp: response.atLookUp,
  );

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
  }, context: context);
}
