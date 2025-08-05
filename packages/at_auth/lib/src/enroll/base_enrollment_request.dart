import 'package:at_auth/at_auth.dart';
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
abstract class BaseEnrollmentRequest {
  String appName;
  String deviceName;
  final EnrollOperationEnum enrollOperation = EnrollOperationEnum.request;
  String? apkamPublicKey;

  BaseEnrollmentRequest(
      {required this.appName, required this.deviceName, this.apkamPublicKey});
}
