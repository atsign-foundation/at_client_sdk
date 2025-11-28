import 'package:flutter/material.dart';
import 'package:at_client_flutter/src/widgets/atsign_rootdomain_dialog.dart';
import 'package:at_client_flutter/src/services/registrar_service.dart';
import 'package:at_client_flutter/src/widgets/registrar_cram_dialog.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_client_flutter/src/widgets/pkam_dialog.dart';
import 'package:at_client_flutter/src/widgets/cram_dialog.dart';
import 'package:at_client_flutter/src/widgets/file_picker.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart'; 
import 'package:at_auth/at_auth.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Flutter Demo',
      theme: theme,
      home: MyHomePage(),
    );
  }
}

/// The main home page of the example app
/// 
/// Demonstrates usage for common authentication and onboarding flows:
/// - Onboarding via Registrar
/// - Authentication via File
/// - Authentication via Keychain
/// 
/// Each flow is composed using the reusable widgets provided by at_client_flutter:
/// - AtSignSelectionDialog
/// - RegistrarCramDialog
/// - CramDialog
/// - PkamDialog
/// - AtKeysFileDialog
/// 
///  Generally, the flow is as follows:
///  1. Show AtSignSelectionDialog to create an AuthRequest (generic class for at_auth)
///    a. For onboarding, use AtOnboardingRequest
///    b. For authentication, use AtAuthRequest
///  2. Process authentication or onboarding
///    a. For onboarding via Registrar
///    b. For authentication via File or Keychain
///  3. Show CramDialog or PkamDialog to complete the process
///    a. returns AtOnboardingResponse or AtAuthResponse respectively
/// 
/// See the individual widgets for more details on their usage.
class MyHomePage extends StatelessWidget {

  final RegistrarService registrar = RegistrarService(
      registrarUrl: "my.atsign.com", 
      apiKey: "enter-your-api-key-here",
    );

  final KeychainStorage keychainStorage = KeychainStorage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Flutter Demo Home Page'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[ 

            ///1. Example of AtSignSelectionDialog usage
            ///  a. Get existing atSigns from keychain storage
            ///  b. Show AtSignSelectionDialog to select or input atSign and root domain
            ElevatedButton(onPressed: () async {
              // a. 
              List<String>? existingAtSigns = await keychainStorage.getAllAtsigns();
              // b.
              AuthRequest? authRequest = await AtSignSelectionDialog.show(
                context,
                existingAtSigns: existingAtSigns,
                // existingDomains: {'root.atsign.org': AtRootDomain.atsignDomain},
                themeData: Theme.of(context),
              );
            }, child: const Text("Show AtSign Selection Dialog")),

            const SizedBox(height: 20),

            ///2. Example of Registrar Cram Onboarding flow
            ///  a. Show AtSignSelectionDialog to select or input atSign and root domain
            ///  b. Show RegistrarCramDialog to get the cram key from registrar
            ///  c. Show CramDialog to complete onboarding with the cram key
            ElevatedButton(onPressed: () async {
              // a. Show AtSignSelectionDialog
              AuthRequest? authRequest = await AtSignSelectionDialog.show(
                context,
                themeData: Theme.of(context),
              );
              
              if(authRequest == null) {
                print('Onboarding cancelled / authRequest is null');
                return;
              }

              // b. Show RegistrarCramDialog 
              var cramKey = await RegistrarCramDialog.show(
                context,
                (authRequest as AtOnboardingRequest),
                registrar: registrar,
                themeData: Theme.of(context),
              );
              if(cramKey == null) {
                print('Onboarding cancelled / cramKey is null');
                return;
              }

              // c. Show CramDialog to complete onboarding
              var response = await CramDialog.show(
                context, 
                request: authRequest, 
                cramKey: cramKey
              );
            }, child: const Text("Registrar Cram Onboarding")), 

            const SizedBox(height: 20),

            ///3. Example of Authentication flow via AtKeysFile
            ///  a. Show AtSignSelectionDialog to select atSign for authentication
            ///  b. Show AtKeysFileDialog to pick the atKeys file from device storage
            ///  c. Show PkamDialog to complete authentication
            ElevatedButton(onPressed: () async {
              // a. Show AtSignSelectionDialog
              AuthRequest? authRequest = await AtSignSelectionDialog.show(
                context,
                themeData: Theme.of(context),
              );
              if(authRequest == null) {
                print('Authentication cancelled / authRequest is null');
                return;
              }
              // b. Show AtKeysFileDialog to pick atKey file
              var atKeysIo = await showDialog<FileAtKeysIo>(context: context, builder: (builder) {
                return AtKeysFileDialog(atsign: authRequest.atSign);
              });
              if(atKeysIo == null) {
                throw Exception('Authentication cancelled / atKeysIo is null');
              }
              var request = AtAuthRequest(
                authRequest.atSign,
                atKeysIo,
                rootDomain: authRequest.rootDomain,
              );
              // c. Show PkamDialog to complete authentication
              var response = await PkamDialog.show(
                context, 
                request: request,
              );
              print('Authentication response: $response');
            }, child: const Text("Authenticate via PkamDialog")), 


            const SizedBox(height: 20),

            ///4. Example of Authentication flow via Keychain
            ///  a. Get existing atSigns from keychain storage
            ///  b. Show AtSignSelectionDialog to select atSign for authentication
            ///     i. Ensure providing KeychainAtKeysIo for the AuthRequest
            ///  c. Show PkamDialog to complete authentication
            ElevatedButton(onPressed: () async {
              // a. get existing atSigns from keychain storage
              var atSigns = await keychainStorage.getAllAtsigns();
              if(atSigns == null || atSigns.isEmpty) {
                print('No atSigns found in keychain for authentication');
                return;
              }
              // b. Show AtSignSelectionDialog
              AuthRequest? request = await AtSignSelectionDialog.show(
                context,
                existingAtSigns: atSigns,
                themeData: Theme.of(context),
              );
              if(request == null) {
                print('Keychain authentication cancelled / request is null');
                return;
              }
              //  i) ensure providing KeychainAtKeysIo for the AuthRequest
              var authRequest = AtAuthRequest(
                request.atSign,
                KeychainAtKeysIo(),
                rootDomain: request.rootDomain,
              );
              // c. Show PkamDialog to complete authentication
              var response = await PkamDialog.show(
                context, 
                request: authRequest,
              );
              print('Keychain authentication response: $response');
            }, child: const Text("Keychain Authentication"))
          ]
        ),
      ),
    );
  }
}
