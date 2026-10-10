import 'package:at_commons/at_commons.dart' show EnrollmentConstants;

/// Whether [enrollmentId] names the atSign's own credential rather than an
/// APKAM enrollment: none, or [EnrollmentConstants.primaryEnrollmentId].
///
/// That credential is treated as the atSign itself, never as an enrollment,
/// so nothing fetches, updates or lists an enrollment record for it, although
/// an atServer from 3.16.4 on holds one named `primary`.
bool isAtSignCredential(String? enrollmentId) =>
    enrollmentId == null ||
    enrollmentId.isEmpty ||
    enrollmentId == EnrollmentConstants.primaryEnrollmentId;
