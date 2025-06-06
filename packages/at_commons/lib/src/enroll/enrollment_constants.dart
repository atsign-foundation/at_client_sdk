import 'package:at_commons/at_commons.dart';

class EnrollmentConstants {
  static const String enrollManageNamespace = '__manage';
  static const String enrollmentKeyPattern = 'new.enrollments';
  static const String enrollmentsRegex =
      '\\.new\\.enrollments\\.${EnrollmentConstants.enrollManageNamespace}@';
  static const String regexForPEK =
      '.*\\.${AtConstants.defaultEncryptionPrivateKey}\\.${EnrollmentConstants.enrollManageNamespace}@';
  static const String regexForEnrollmentKey =
      '^[^\\.]+\\.${EnrollmentConstants.enrollmentKeyPattern}\\.${EnrollmentConstants.enrollManageNamespace}@';
  static const String regexForSEK =
      '.*\\.${AtConstants.defaultSelfEncryptionKey}\\.${EnrollmentConstants.enrollManageNamespace}@';
  static const String pkamNamespace = '__pkams';
  static const String globalNamespace = '__global';
  static const String allNamespaces = '*';
  static const String perEnrollmentApproved = 'a.__e';
  static const String perEnrollmentRevoked = 'r.__e';
  static const String perEnrollmentDeleted = 'd.__e';
  static const String regexForPerEnrollmentNamespaces =
      '\\.(?<EnId>[^\\.]+)\\.[ard]\\.__e@';
}
