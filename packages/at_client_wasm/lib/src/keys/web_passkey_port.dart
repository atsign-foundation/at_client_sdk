import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'passkey_port.dart';

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

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

  /// Creates a discoverable passkey and evaluates the PRF extension.
  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput}) async {
    final challenge = _randomBytes(32);

    final options = {
      'publicKey': {
        'challenge': challenge,
        'rp': {'id': rpId, 'name': rpName},
        'user': {
          'id': utf8.encode(atSign),
          'name': atSign,
          'displayName': atSign
        },
        'pubKeyCredParams': [
          {'type': 'public-key', 'alg': -7},
          {'type': 'public-key', 'alg': -257}
        ],
        'authenticatorSelection': {
          'residentKey': 'required',
          'userVerification': 'required'
        },
        'extensions': {
          'prf': {
            'eval': {'first': evalInput}
          }
        }
      }
    }.jsify() as CredentialCreationOptions;

    final credential =
        await _ceremony(window.navigator.credentials.create(options));
    final credentialId = credential.rawId.toDart.asUint8List();

    return (credentialId: credentialId, prfFirst: _prfFirst(credential));
  }

  /// Gets a passkey assertion and evaluates the PRF extension.
  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    final challenge = _randomBytes(32);

    final allowCredentialsList = allowCredential == null
        ? []
        : [
            {
              'type': 'public-key',
              'id': allowCredential,
            }
          ];

    final options = {
      'publicKey': {
        'challenge': challenge,
        'rpId': rpId,
        'userVerification': 'required',
        'allowCredentials': allowCredentialsList,
        'extensions': {
          'prf': {
            'eval': {'first': evalInput}
          }
        }
      }
    }.jsify() as CredentialRequestOptions;

    final credential =
        await _ceremony(window.navigator.credentials.get(options));
    final credentialId = credential.rawId.toDart.asUint8List();

    return (credentialId: credentialId, prfFirst: _prfFirst(credential));
  }
}

/// Awaits [request], rethrowing any rejection or null result as a
/// [PasskeyCeremonyException].
Future<PublicKeyCredential> _ceremony(JSPromise<Credential?> request) async {
  final Credential? credential;
  try {
    credential = await request.toDart;
  } catch (e) {
    throw PasskeyCeremonyException('$e');
  }
  if (credential == null) {
    throw PasskeyCeremonyException('no credential returned');
  }
  return credential as PublicKeyCredential;
}
