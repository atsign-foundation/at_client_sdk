enum EnrollmentStatus { pending, approved, denied, revoked, expired }

EnrollmentStatus getEnrollStatusFromString(String value) {
  switch (value) {
    case 'approved':
      return EnrollmentStatus.approved;
    case 'denied':
      return EnrollmentStatus.denied;
    case 'pending':
      return EnrollmentStatus.pending;
    case 'revoked':
      return EnrollmentStatus.revoked;
    case 'expired':
      return EnrollmentStatus.expired;
    default:
      throw ArgumentError('Unknown enroll status string: $value');
  }
}
