import 'package:at_commons/at_commons.dart' show EnrollmentConstants;

/// Whether [enrollmentId] names the primary enrollment (`*:rw`), the one the
/// root PKAM keys authenticate as, rather than another APKAM enrollment: none,
/// or [EnrollmentConstants.primaryEnrollmentId].
///
/// The primary enrollment is treated as the atSign itself, so nothing
/// fetches, updates or lists an enrollment record for it, although an
/// atServer from 3.16.4 on holds one named `primary`.
bool isAtSignCredential(String? enrollmentId) =>
    enrollmentId == null ||
    enrollmentId.isEmpty ||
    enrollmentId == EnrollmentConstants.primaryEnrollmentId;
