import 'dart:async' show FutureOr;

import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart' show AtKeysIo;
import 'package:at_commons/at_commons.dart';

/// The BaseEnrollmentRequest class encapsulates shared fields between the InitialEnrollmentRequest and EnrollmentRequest.
///
/// The [FirstEnrollmentRequest] is used when the app is onboarded for the first time. The request is sent to the server
/// via the CRAM authenticated connection and is auto approved.
///
/// The [EnrollmentRequest] is used by the other apps to authenticate. This request is sent to the server and subsequently
/// notified to apps with access to the "__manage" namespace. Upon approval, the requesting app is authenticated and granted
/// authorization to access the specified namespaces in the request. Conversely, if the request is disapproved, the requesting
/// app is denied login access.
abstract class EnrollmentRequest {
  String atSign;
  String appName;
  String deviceName;
  final EnrollOperationEnum enrollOperation = EnrollOperationEnum.request;
  String? apkamPublicKey;
  AtRootDomain rootDomain;

  EnrollmentRequest(
      {required this.atSign,
      required this.appName,
      required this.deviceName,
      this.apkamPublicKey,
      this.rootDomain = const AtRootDomain("root.atsign.org", 64)});
}

/// The [EnrollmentRequest] is used by the apps to submit enrollment request for APKAM keys which provides .atKeys specific to
/// an application with restricted access to the namespaces. The application can access only the namespaces which are specified
/// in the enrollment request. If the namespace has Read-Write access then the application is allowed to create/update the data,
/// otherwise, if the namespace has only Read access then the application is allowed to read the data, but cannot create/update
/// the data.
///
/// This request is sent to the server and subsequently notified to apps with access to the "__manage" namespace. Upon approval, the requesting app is authenticated and granted
/// authorization to access the specified namespaces in the request. Conversely, if the request is disapproved, the requesting
/// app is denied login access.
class AtEnrollmentRequest extends EnrollmentRequest {
  /// The authenticated session of the app submitting this enrollment request.
  ///
  /// When supplied, it is the source of the request's [atSign] and [rootDomain],
  /// and its [AtAuthSession.atKeysIo] is where the newly enrolled app's keys are
  /// persisted and handed back on the [AtEnrollmentResponse.session] after
  /// approval. Prefer this over the deprecated `atSign`/`rootDomain` params.
  final AtAuthSession? session;

  Map<String, String> namespaces;
  String? encryptedAPKAMSymmetricKey;
  String otp;
  Duration? apkamKeysExpiryDuration;

  /// Builds the opaque metadata stored verbatim on this enrollment's record.
  ///
  /// Called once, after the APKAM keypair for this request has been generated
  /// and before the request is sent, with an [AtKeysIo] holding that keypair.
  /// Whatever it returns is attached to the request unchanged; at_auth never
  /// inspects it.
  ///
  /// The callback is how a caller contributes material that must be **signed
  /// by the new APKAM key** — the secret-sharing key package is the first such
  /// case. That cannot be built by the caller beforehand, because the keypair
  /// does not exist until this request is being assembled, and it cannot be
  /// added afterwards, because the metadata is only ever written by the
  /// request that creates the record.
  ///
  /// The keys it receives carry **no `enrollmentId`**: the atServer assigns
  /// that in its response to this request. Anything the callback builds must
  /// therefore be valid without one.
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? metadataBuilder;

  AtEnrollmentRequest({
    this.session,
    @Deprecated('Provide `session` instead; its atSign is used.')
    String? atSign,
    @Deprecated('Provide `session` instead; its rootDomain is used.')
    AtRootDomain? rootDomain,
    required super.appName,
    required super.deviceName,
    @Deprecated('Provide `session` instead; it contains a AtKeysIo to use.')
    super.apkamPublicKey,
    required this.otp,
    required this.namespaces,
    @Deprecated('Provide `session` instead; it contains a AtKeysIo to use.')
    this.encryptedAPKAMSymmetricKey,
    this.apkamKeysExpiryDuration,
    this.metadataBuilder,
  }) : super(
          atSign: session?.atSign ??
              atSign ??
              (throw ArgumentError(
                  'AtEnrollmentRequest requires a `session` (or the deprecated `atSign`)')),
          rootDomain:
              session?.rootDomain ?? rootDomain ?? AtRootDomain.atsignDomain,
        );
}

/// The FirstEnrollmentRequest represents an enrollment request when onboarding (activating) an atSign.
///
/// Upon submitting the [FirstEnrollmentRequest], an APKAM key pair and an encryption key pair are generated, and an enrollment
/// request is sent to the server. The server assigns the "__manage" namespace, which has access to all namespaces and serves as
/// the administrator app responsible for approving subsequent enrollment requests.
///
/// ```dart
/// Example on submitting FirstEnrollmentRequest
///   FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
///               appName: 'wavi',
///               deviceName: 'iphone',
///               apkamPublicKey: 'dummy-apkam-public key', // Generated by the system
///               encryptedDefaultEncryptionPrivateKey: 'dummy-encrypted-private-key', // Generated by the system and encrypted by the APKAM symmetric key
///               encryptedDefaultSelfEncryptionKey: 'dummy-self-encryption-key'); // Generated by the system and encrypted by the APKAM symmetric key);
///```
/// Two pair of RSA key pairs one for authentication which is called APKAM keys and other for shared data encryption
/// which is called encryption key pair. Two AES keys pairs self data encryption and APKAM encryption key.
///
/// The APKAM public key is stored in the secondary server. The default encryption private key and self encryption keys are
/// encrypted with the APKAM symmetric key and stored into the server.

class FirstEnrollmentRequest extends EnrollmentRequest {
  FirstEnrollmentRequest(
      {required super.atSign,
      required super.appName,
      required super.deviceName,
      required super.apkamPublicKey});
}
