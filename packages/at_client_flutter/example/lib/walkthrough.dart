import 'package:example/main.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_auth/at_auth.dart';
import 'package:path/path.dart' as path;
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

/// This method is an example of how an application creates their own customized onboarding flow
/// Using the provided widgets in this library, you can create your own flow for onboarding like this
/// This is the default and suggested method of implementing the onboarding flow and can be copy and pasted into your application
Future<void> onboard(BuildContext context) async {
  // a. Show AtSignSelectionDialog
  AuthRequest? authRequest = await AtSignSelectionDialog.show(context);
  if (!context.mounted || authRequest == null) return;
  // b. Show RegistrarCramDialog
  var cramKey = await RegistrarCramDialog.show(
    context,
    (authRequest as AtOnboardingRequest),
    registrar: registrar,
  );
  if (!context.mounted || cramKey == null) return;
  // c. Show CramDialog to complete onboarding
  var response = await CramDialog.show(
    context,
    request: authRequest,
    cramKey: cramKey,
  );
  if (response == null || !response.isSuccessful) return;

  // d. very important! now that we have authenticated, we can create an atClient instance
  var dir = await getApplicationSupportDirectory();
  var acp = AtClientPreference()
    ..rootDomain = authRequest.rootDomain.rootDomain
    ..rootPort = authRequest.rootDomain.rootPort
    ..namespace = namespace
    ..commitLogPath = dir.path
    ..hiveStoragePath = dir.path;
  // make sure to use the atChops and atLookUp provided by the response as these are already authenticated.
  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    namespace,
    acp,
    atChops: response.atChops,
    atLookUp: response.atLookUp,
  );
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (context) => const HomePage()),
  );
}

/// Login using an atSign stored in the keychain
/// This method authenticates using existing keychain credentials
Future<void> loginWithKeychain(BuildContext context) async {
  // a. Load existing atSigns from keychain
  var atSigns = await keychainStorage.getAllAtsigns();

  if (atSigns.isEmpty) {
    // No atSigns in keychain, fallback to file login
    _logger.warning('No atSigns found in keychain');
    return;
  }

  // b. Show AtSignSelectionDialog with existing atSigns
  AuthRequest? request = await AtSignSelectionDialog.show(
    context,
    existingAtSigns: atSigns,
  );
  if (request == null) return;

  // c. Create AuthRequest with KeychainAtKeysIo
  var authRequest = AtAuthRequest(
    request.atSign,
    atKeysIo: KeychainAtKeysIo(),
    rootDomain: request.rootDomain,
  );

  // d. Show PkamDialog to complete authentication
  var response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;

  // e. Create atClient instance
  await _setupAtClient(context, authRequest, response);
}

/// Login using an atKeys file from the file system
/// This method prompts the user to select an atKeys file for authentication
Future<void> loginWithFile(BuildContext context) async {
  // b. Show AtKeysFileDialog to select the atKeys file
  FileAtKeysIo atKeysIo = (await AtKeysFileDialog.show(context))!;

  var filepath = atKeysIo.filePath!('');
  var name = path.basenameWithoutExtension(filepath);
  var atSign = name.split('_').first;

  // c. Create AuthRequest with file-based AtKeysIo
  var authRequest = AtAuthRequest(
    atSign,
    atKeysIo: atKeysIo,
    rootDomain: AtRootDomain.atsignDomain,
  );

  // d. Show PkamDialog to complete authentication
  var response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;

  // e. Create atClient instance
  await _setupAtClient(context, authRequest, response);
}

Future<void> loginWithApkam(BuildContext context) async {
  // a. Show AtSignSelectionDialog with existing atSigns
  AuthRequest? request = await AtSignSelectionDialog.show(context);
  if (request == null) return;

  AtEnrollmentResponse? enrollmentResponse = await ApkamActivationDialog.show(
    context,
    atSign: request.atSign,
    rootDomain: request.rootDomain,
    appName: namespace,
    deviceName: 'default',
    namespaces: {namespace: 'rw'},
  );

  if (enrollmentResponse == null || enrollmentResponse.atAuthKeys == null) {
    throw AtAuthenticationException("Enrollment Failed");
  }

  // b. Create AuthRequest with KeychainAtKeysIo
  var authRequest = AtAuthRequest(
    request.atSign,
    atAuthKeys: enrollmentResponse.atAuthKeys!,
    rootDomain: request.rootDomain,
  );

  // d. Show PkamDialog to complete authentication
  var response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;

  // e. Create atClient instance
  await _setupAtClient(context, authRequest, response);
}

Future<void> exportKeys(BuildContext context) async {
  // Get the file path from the save dialog
  if (AtClientManager.getInstance().atClient == null) return;
  final atsign = AtClientManager.getInstance().atClient.getCurrentAtSign()!;
  final filePath = await _openFileSaveDialog(
    suggestedFileName: '${atsign}_key.atKeys',
    fileExtension: '.atKeys',
    allowedExtensions: ['atKeys'],
  );

  if (filePath == null) return;

  FileAtKeysIo atKeysIo = FileAtKeysIo(filePath: (_) => filePath);
  var atKeys = await keychainStorage.getAtsign(atsign);
  atKeysIo.write(atsign!, atKeys!);
}

/// Opens a file save dialog and returns the selected file path.
/// Returns null if the user cancels the dialog.
Future<String?> _openFileSaveDialog({
  String? suggestedFileName,
  String? fileExtension,
  List<String>? allowedExtensions,
}) async {
  try {
    // Open save file dialog
    String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save File',
      fileName: suggestedFileName ?? 'document.txt',
      type: FileType.custom,
      allowedExtensions: allowedExtensions ?? ['txt', 'pdf', 'json'],
    );

    // User cancelled the dialog
    if (outputPath == null) {
      return null;
    }

    // Ensure the file has the correct extension if specified
    if (fileExtension != null && !outputPath.endsWith(fileExtension)) {
      outputPath = '$outputPath$fileExtension';
    }

    return outputPath;
  } catch (e) {
    print('Error opening file save dialog: $e');
    return null;
  }
}

/// Helper method to set up the atClient instance and navigate to home page
Future<void> _setupAtClient(
  BuildContext context,
  AtAuthRequest authRequest,
  dynamic response,
) async {
  var dir = await getApplicationSupportDirectory();
  var acp = AtClientPreference()
    ..rootDomain = authRequest.rootDomain.rootDomain
    ..rootPort = authRequest.rootDomain.rootPort
    ..namespace = namespace
    ..commitLogPath = dir.path
    ..hiveStoragePath = dir.path;

  // Make sure to use the atChops and atLookUp provided by the response
  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    namespace,
    acp,
    atChops: response.atChops,
    atLookUp: response.atLookUp,
  );

  if (context.mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  }
}

/// remove all atsigns from the keychain
Future<void> clearAllAtsigns() async {
  await keychainStorage.deleteAllAtKeysData();
}

/// This is an example of writing your own dialog to remove an atsign from the keychain
Future<void> removeAtsign(BuildContext context) async {
  var items = await keychainStorage.getAllAtsigns();
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
  keychainStorage.removeAtsignFromKeychain(atsign!);
}
