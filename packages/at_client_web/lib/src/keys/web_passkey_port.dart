import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart'
    show
        PasskeyAssertion,
        PasskeyCreation,
        PasskeyPort,
        UnknownCredentialSignal;
import 'package:web/web.dart';

import 'passkey_ceremony.dart';
import 'passkey_creation_options.dart';
import 'passkey_request_options.dart';

/// The PRF `first` result of [credential] as bytes of its own, or null when
/// the authenticator returned none.
///
/// The browser's ArrayBuffer is overwritten with zeroes once copied.
Uint8List? prfFirstOf(PublicKeyCredential credential) {
  final extensions = credential.getClientExtensionResults() as JSObject;
  final results = (extensions['prf'] as JSObject?)?['results'] as JSObject?;
  final first = results?['first'] as JSArrayBuffer?;
  if (first == null) return null;
  final copy = Uint8List.fromList(first.toDart.asUint8List());
  (globalContext['Uint8Array'] as JSFunction)
      .callAsConstructor<JSObject>(first)
      .callMethod('fill'.toJS, 0.toJS);
  return copy;
}

/// What the create ceremony's `prf` extension result says: true when
/// `enabled` is true or a `first` result is present, false when `enabled` is
/// false, null when the extension result is absent.
bool? prfEnabledOf(PublicKeyCredential credential) {
  final extensions = credential.getClientExtensionResults() as JSObject;
  final prf = extensions['prf'] as JSObject?;
  if (prf == null) return null;
  final first = prfFirstOf(credential);
  if (first != null) {
    first.fillRange(0, first.length, 0);
    return true;
  }
  final enabled = prf['enabled'];
  return enabled.isA<JSBoolean>() ? (enabled as JSBoolean).toDart : null;
}

/// A port that executes WebAuthn ceremonies through `package:web`.
class WebPasskeyPort implements PasskeyPort, UnknownCredentialSignal {
  /// Initializes the port with the relying party's [rpId] and [rpName].
  WebPasskeyPort({required this.rpId, required this.rpName});

  /// The relying party ID.
  final String rpId;

  /// The relying party name.
  final String rpName;

  /// Creates a discoverable passkey with the PRF extension enabled.
  @override
  Future<PasskeyCreation> create(
      {required String atSign,
      required DateTime enrolledAt,
      required String deviceName}) async {
    final options = passkeyCreationOptions(
            rpId: rpId,
            rpName: rpName,
            atSign: atSign,
            enrolledAt: enrolledAt,
            deviceName: deviceName)
        .jsify() as CredentialCreationOptions;
    final credential =
        await passkeyCeremony(window.navigator.credentials.create(options));
    return (
      credentialId: credential.rawId.toDart.asUint8List(),
      prfEnabled: prfEnabledOf(credential),
    );
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
      prfFirst: prfFirstOf(credential),
    );
  }

  /// Tells the browser that [credentialId] no longer belongs to an account, so
  /// it can drop the passkey, through
  /// `PublicKeyCredential.signalUnknownCredential`.
  ///
  /// Does nothing in a browser without that call, and a refused or failing
  /// signal is ignored: the passkey is then left for the user to delete.
  @override
  Future<void> signalUnknownCredential(Uint8List credentialId) async {
    try {
      final credential = globalContext['PublicKeyCredential'] as JSObject?;
      if (credential == null || !credential.has('signalUnknownCredential')) {
        return;
      }
      final options = {
        'rpId': rpId,
        'credentialId': base64Url.encode(credentialId).replaceAll('=', ''),
      }.jsify();
      final result = credential.callMethod<JSAny?>(
          'signalUnknownCredential'.toJS, options);
      if (result.isA<JSPromise>()) await (result as JSPromise).toDart;
    } on Object {
      // The signal is a best effort.
    }
  }
}
