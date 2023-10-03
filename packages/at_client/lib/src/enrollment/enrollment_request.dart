import 'package:at_client/src/response/response.dart';
import 'package:at_commons/at_commons.dart';

class Enrollment {
  final String? _enrollmentId;
  final String? _appName;
  final String? _deviceName;
  final Map<String, String> _namespaces;
  final String? _otp;
  final String? _aPKAMPublicKey;
  String? encryptedDefaultEncryptedPrivateKey;
  String? encryptedDefaultSelfEncryptionKey;
  final EnrollOperationEnum _enrollOperationEnum;

  String? get enrollmentId => _enrollmentId;

  String? get appName => _appName;

  String? get deviceName => _deviceName;

  Map<String, String> get namespaces => _namespaces;

  String? get otp => _otp;

  String? get aPKAMPublicKey => _aPKAMPublicKey;

  EnrollOperationEnum get enrollmentOperation => _enrollOperationEnum;

  Enrollment._builder(EnrollmentBuilder enrollmentBuilder)
      : _enrollmentId = enrollmentBuilder._enrollmentId,
        _appName = enrollmentBuilder._appName,
        _deviceName = enrollmentBuilder._deviceName,
        _namespaces = enrollmentBuilder._namespaces,
        _otp = enrollmentBuilder._otp,
        _aPKAMPublicKey = enrollmentBuilder._aPKAMPublicKey,
        _enrollOperationEnum = enrollmentBuilder._enrollmentOperationEnum;

  static EnrollmentBuilder request() {
    EnrollmentBuilder enrollmentBuilder = EnrollmentBuilder();
    enrollmentBuilder._enrollmentOperationEnum = EnrollOperationEnum.request;
    return enrollmentBuilder;
  }

  static EnrollmentBuilder approve() {
    EnrollmentBuilder enrollmentBuilder = EnrollmentBuilder();
    enrollmentBuilder._enrollmentOperationEnum = EnrollOperationEnum.approve;
    return enrollmentBuilder;
  }

  static EnrollmentBuilder deny() {
    EnrollmentBuilder enrollmentBuilder = EnrollmentBuilder();
    enrollmentBuilder._enrollmentOperationEnum = EnrollOperationEnum.deny;
    return enrollmentBuilder;
  }
}

class EnrollmentBuilder {
  String? _enrollmentId;
  String? _appName;
  String? _deviceName;
  Map<String, String> _namespaces = {};
  String? _otp;
  String? _aPKAMPublicKey;
  late EnrollOperationEnum _enrollmentOperationEnum;

  EnrollmentBuilder setEnrollmentId(String enrollmentId) {
    _enrollmentId = enrollmentId;
    return this;
  }

  EnrollmentBuilder setAppName(String appName) {
    _appName = appName;
    return this;
  }

  EnrollmentBuilder setDeviceName(String deviceName) {
    _deviceName = deviceName;
    return this;
  }

  EnrollmentBuilder setNamespaces(Map<String, String> namespaces) {
    _namespaces = namespaces;
    return this;
  }

  EnrollmentBuilder setTotp(String otp) {
    _otp = otp;
    return this;
  }

  EnrollmentBuilder setAPKAMPublicKey(String aPKAMPublicKey) {
    _aPKAMPublicKey = aPKAMPublicKey;
    return this;
  }

  Enrollment build() {
    return Enrollment._builder(this);
  }
}

class EnrollmentResponse {
  String? enrollmentId;
  String? enrollStatus;
  bool isError = false;
  String? errorDescription;
}
