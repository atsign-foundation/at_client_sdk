import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/enrollment/enrollment_info.dart';

/// The [AtAuthService] class handles the onboarding, authentication, and enrollment submission for an atSign.
/// For a new atSign, use the [onboard] method to activate it.
///
/// For logging in to an existing atSign, use the [authenticate] method.
///
/// To implement an application-level authentication mechanism and restrict access to a designated namespace,
/// use the [enroll] method to submit an enrollment.
abstract class AtAuthService {
  /// This method is used to authenticate an atSign into the app.
  /// The user have to supply the atKeys file (which contains keys for authentication). Otherwise, if
  /// the atSign is logged-in previously, then the details are fetched in the KeyChain Manager and authentication is
  /// performed.
  ///
  /// If the authentication is successful, then an instance of AtClient is initialized for performing the SDK operations.
  /// ```dart
  ///  final String atSign = '@alice'; // Represents the atSign to onboard.
  ///  final AtClientPreferences atClientPreferences = AtClientPreferences();
  ///
  ///  AtAuthService atAuthService = AtClientMobile.authService(atSign, atClientPreferences);
  ///  AtAuthRequest atAuthRequest = AtAuthRequest(_atSign)
  ///       ..atKeysFilePath = atOnboardingPreference.atKeysFilePath // The path to .atKeys file
  ///       ..enrollmentId = enrollmentId // Represents an enrollmentId for APKAM authentication.
  ///       ..authMode = atOnboardingPreference.authMode // Represents the type of authentication. Defaults to keysFile.
  ///       ..rootDomain = atOnboardingPreference.rootDomain // Represents the root server domain. Defaults to 'root.atsign.org'
  ///       ..rootPort = atOnboardingPreference.rootPort; // Represents the root server port. Defaults to '64'
  ///
  /// AtAuthResponse atAuthResponse = atAuthService.authenticate(atAuthRequest);
  ///```
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest);

  /// Checks whether the provided atSign has been onboarded.
  /// Returns true if the atSign is onboarded; otherwise, returns false.
  /// ```dart
  ///  final String atSign = '@alice'; // Represents the atSign to onboard.
  ///  final String cramKey = 'abc123'; // Represents the key used for CRAM Authentication which is fetched from the QR code.
  ///  final AtClientPreferences atClientPreferences = AtClientPreferences();
  ///  AtAuthService atAuthService = AtClientMobile.authService(atSign, atClientPreferences);
  ///
  ///  AtAuthService atAuthService = AtClientMobile.isOnboarded(atSign);
  ///  ```
  Future<bool> isOnboarded(String atSign);

  /// This method activates an atSign for the first time, pairing it with the application used for onboarding.
  ///
  /// Performs one-time CRAM (Challenge-Response Authentication Mechanism) authentication and sets up RSA keys pairs
  /// for future interactions.
  ///
  /// Upon successful CRAM Authentication, an RSA key pair is generated for PKAM authentication (Public Key Authentication Mechanism).
  /// Another RSA key pair and AES Key is generated for the data encryption.
  ///
  /// The generated keys are stored into the key-chain manager and are populated into the AtOnboardingResponse.atAuthKeys
  /// which should be securely stored for the subsequent login.
  ///
  /// ```dart
  ///  final String atSign = '@alice'; // Represents the atSign to onboard.
  ///  final String cramKey = 'abc123'; // Represents the key used for CRAM Authentication which is fetched from the QR code.
  ///  final AtClientPreferences atClientPreferences = AtClientPreferences();
  ///
  ///  AtAuthService atAuthService = AtClientMobile.authService(atSign, atClientPreferences);
  ///  AtOnboardingRequest atOnboardingRequest = AtOnboardingRequest(atSign);
  ///  AtOnboardingResponse atOnboardingResponse = atAuthService.onboard(atOnboardingRequest, cramSecret: cramKey);
  /// ```
  /// Sets [AtOnboardingResponse.isSuccessful] to true if onboard process is completed successfully; else set to false.
  ///
  /// Throws [AtException] if an invalid CRAM Secret is set.
  ///
  /// Throws [AtAuthenticationException] if [AtOnboardingResponse.atAuthKeys] is not populated with generated
  /// RSA key pairs and AES key.
  Future<AtOnboardingResponse> onboard(AtOnboardingRequest atOnboardingRequest,
      {String? cramSecret});

  /// After successfully onboarding an atSign, the atKeys file is obtained, providing credentials with full access to
  /// all namespaces. However, for more precise access control in alignment with specific app requirements, users can
  /// request a new key pair with limited access for a particular application using the APKAM (Application Public Key Authentication Mechanism).
  /// This restricted key pair will only provide access to a defined set of namespaces, as specified in the [EnrollmentRequest.namespaces].
  ///
  /// To initiate an enrollment request, the user must first retrieve the OTP from the server or use the previously
  /// set semi-permanent passcode (SPP). Subsequently, the user needs to supply the "appName," "deviceName," "namespaces,"
  /// and "OTP/SPP" before submitting the enrollment request.
  ///
  /// Once the submitted enrollment is approved by the admin app, a new key pair is generated with restricted access
  /// based on the specified namespaces.
  ///
  /// Following the submission of an enrollment request, any subsequent enrollment requests cannot be made until the
  /// completion of the preceding enrollment.
  ///
  /// ```dart
  ///  final String atSign = '@alice'; // Represents the atSign to enroll.
  ///  final AtClientPreferences atClientPreferences = AtClientPreferences();
  ///  AtAuthService atAuthService = AtClientMobile.authService(atSign, atClientPreferences);
  ///  EnrollmentRequest enrollmentRequest = EnrollmentRequest(
  ///          appName: 'wavi',
  ///          deviceName: 'my-device',
  ///          namespaces: {'wavi': 'rw'},
  ///          apkamPublicKey: 'dummy_public_key',
  ///          otp: 'ABC123',
  ///          encryptedAPKAMSymmetricKey: 'enc_apkam_sym_key');
  ///
  ///  String enrollmentId = atAuthService.enroll(enrollmentRequest);
  /// ```
  ///
  /// Returns a [Future] representing EnrollmentId.
  ///
  /// Throws an [InvalidRequestException] if a new enrollment is submitted while there is already a pending enrollment.
  Future<AtEnrollmentResponse> enroll(EnrollmentRequest enrollmentRequest);

  /// Provides the final enrollment status.
  ///
  /// [EnrollmentStatus.approved] signifies successful approval of the enrollment,
  /// allowing the user to utilize the enrollment ID for APKAM authentication.
  ///
  /// [EnrollmentStatus.denied] indicates that the enrollment ID is not eligible for
  /// APKAM authentication.
  Future<EnrollmentStatus> getFinalEnrollmentStatus();

  /// Returns enrollment request data
  ///
  /// Returns null if no enrollment request found
  Future<EnrollmentInfo?> getSentEnrollmentRequest();
}
