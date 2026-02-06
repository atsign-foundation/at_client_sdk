import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
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

/// This method is an example of how an application creates their own customized authentication flow
/// Using the provided widgets in this library, you can create your own flow for authentication like this
/// This is one of many different ways of logging in.
/// This combines two methods into one.
Future<void> login(BuildContext context) async {
  // a. get existing atSigns from keychain storage
  var atSigns = await keychainStorage.getAllAtsigns();
  // b. Show AtSignSelectionDialog
  AuthRequest? request = await AtSignSelectionDialog.show(
    context,
    existingAtSigns: atSigns,
  );
  if (request == null) return;
  //  ensure providing KeychainAtKeysIo for the AuthRequest
  var authRequest = AtAuthRequest(
    request.atSign,
    atKeysIo: KeychainAtKeysIo(),
    rootDomain: request.rootDomain,
  );
  // if there was nothing in the keychain, we need to authenticate via AtKeys File
  // or, if the atsign wasn't in the keychain
  if (atSigns.isEmpty || !atSigns.contains(request.atSign)) {
    authRequest.atKeysIo = await AtKeysFileDialog.show(context);
  }
  // c. Show PkamDialog to complete authentication
  var response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;
  // d. very important! now that we have authenticated, we can create an atClient instance
  var dir = await getApplicationSupportDirectory();
  var acp = AtClientPreference()
    ..rootDomain = authRequest.rootDomain.rootDomain
    ..rootPort = authRequest.rootDomain.rootPort
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
