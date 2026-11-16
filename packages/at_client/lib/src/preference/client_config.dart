import 'package:at_auth/at_auth.dart' show AtEnrollment, clientConfigFor;
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:at_client/src/version.dart';

/// The SDK every authenticating `from:` at_client sends names.
const String atClientSdkName = 'atsign.dart.at_client';

/// The clientConfig an authenticating `from:` of at_client carries: the app
/// [particulars] name, at_client as the SDK, and at_client's version as
/// `version`.
///
/// What [particulars] leave unset at_auth fills: the program file's name and
/// "unknown".
Map<String, String> clientConfigOf(AtClientParticulars? particulars) =>
    clientConfigFor(
        appName: particulars?.appName,
        appVersion: particulars?.appVersion,
        sdkName: atClientSdkName,
        sdkVersion: packageVersion,
        version: packageVersion);

/// An enrollment whose approval handshake's `from:` carries
/// [clientConfigOf] [particulars]: the one way at_client builds an
/// [AtEnrollment].
AtEnrollment enrollmentFor(AtClientParticulars? particulars) =>
    AtEnrollment.create(clientConfig: clientConfigOf(particulars));
