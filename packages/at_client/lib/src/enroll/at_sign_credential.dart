import 'package:at_commons/at_commons.dart' show EnrollmentConstants;

/// Whether [enrollmentId] names the atSign's own credential rather than an
/// APKAM enrollment: none, or [EnrollmentConstants.primaryEnrollmentId].
///
/// That credential has no enrollment record on a released atServer, so
/// nothing fetches, updates or lists one for it.
bool isAtSignCredential(String? enrollmentId) =>
    enrollmentId == null ||
    enrollmentId.isEmpty ||
    enrollmentId == EnrollmentConstants.primaryEnrollmentId;
