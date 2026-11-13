import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'passkey_ceremony.dart';
import 'passkey_creation_options.dart';
import 'passkey_port.dart';
import 'passkey_request_options.dart';

Uint8List? _prfFirst(PublicKeyCredential credential) {
  final extensions = credential.getClientExtensionResults() as JSObject;
  final results = (extensions['prf'] as JSObject?)?['results'] as JSObject?;
  return (results?['first'] as JSArrayBuffer?)?.toDart.asUint8List();
}

/// A port that executes WebAuthn ceremonies through `package:web`.
class WebPasskeyPort implements PasskeyPort {
  /// Initializes the port with the relying party's [rpId] and [rpName].
  WebPasskeyPort({required this.rpId, required this.rpName});

  /// The relying party ID.
  final String rpId;

  /// The relying party name.
  final String rpName;

  /// Creates a discoverable passkey with the PRF extension enabled.
  @override
  Future<Uint8List> create({required String atSign}) async {
    final options =
        passkeyCreationOptions(rpId: rpId, rpName: rpName, atSign: atSign)
            .jsify() as CredentialCreationOptions;
    final credential =
        await passkeyCeremony(window.navigator.credentials.create(options));
    return credential.rawId.toDart.asUint8List();
  }

  /// Gets a passkey assertion and evaluates the PRF extension.
  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    final options = passkeyRequestOptions(
            rpId: rpId, evalInput: evalInput, allowCredential: allowCredential)
        .jsify() as CredentialRequestOptions;

    final credential =
        await passkeyCeremony(window.navigator.credentials.get(options));

    return (
      credentialId: credential.rawId.toDart.asUint8List(),
      prfFirst: _prfFirst(credential),
    );
  }
}
