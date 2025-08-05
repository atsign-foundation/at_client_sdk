/// The class holds details regarding an enrollment request, where the server notifies the approving app upon receiving a
/// request from the requesting app, seeking approval or denial.
///
/// The EnrollmentServerResponse includes the following fields:
///
///   - appName: The name of the app initiating the enrollment request.
///   - deviceName: The name of the device.
///   - namespace: This field determines the namespaces for granting access to view or write data based on permissions.
///   - encryptedAPKAMSymmetricKey: In the event of approval, the encryptedAPKAMSymmetricKey is used to encrypt the default
///                                 encryption private key and self-encryption key, facilitating the generation of the APKAM key pair.
class EnrollmentServerResponse {
  late String appName;
  late String deviceName;
  late Map<String, String> namespace;
  late String encryptedAPKAMSymmetricKey;
}
