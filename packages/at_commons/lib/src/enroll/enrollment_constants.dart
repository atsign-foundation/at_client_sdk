import 'package:at_commons/at_commons.dart';

class EnrollmentConstants {
  static const String enrollManageNamespace = '__manage';
  static const String enrollmentKeyPattern = 'new.enrollments';
  /// Matches an enrollment record. Server-side only: never synced to a client.
  static const String enrollmentsRegex =
      '\\.new\\.enrollments\\.${EnrollmentConstants.enrollManageNamespace}@';
  /// Matches an enrollment's encryption private key. Server-side only: fetched
  /// by `keys:get` at enrollment time, never synced.
  static const String regexForPEK =
      '.*\\.${AtConstants.defaultEncryptionPrivateKey}\\.${EnrollmentConstants.enrollManageNamespace}@';
  /// Matches an enrollment record by its bare key name. Server-side only: a
  /// client reads these through `enroll:fetch` and `enroll:list`.
  static const String regexForEnrollmentKey =
      '^[^\\.]+\\.${EnrollmentConstants.enrollmentKeyPattern}\\.${EnrollmentConstants.enrollManageNamespace}@';
  /// Matches an enrollment's self-encryption key. Server-side only: fetched by
  /// `keys:get` at enrollment time, never synced.
  static const String regexForSEK =
      '.*\\.${AtConstants.defaultSelfEncryptionKey}\\.${EnrollmentConstants.enrollManageNamespace}@';
  static const String pkamNamespace = '__pkams';
  static const String globalNamespace = '__global';
  static const String allNamespaces = '*';
  static const String perEnrollmentApproved = 'a.__e';
  static const String perEnrollmentRevoked = 'r.__e';
  static const String perEnrollmentDeleted = 'd.__e';
  /// Matches a key in an enrollment's reserved namespace, capturing the id as
  /// `EnId`.
  ///
  /// The id is anchored at a dot, a colon or the start of the key; all three
  /// are needed, and the atServer refuses foreign writes on this match.
  static const String regexForPerEnrollmentNamespaces =
      '(?:^|[.:])(?<EnId>[^.:]+)\\.[ard]\\.__e@';
}
