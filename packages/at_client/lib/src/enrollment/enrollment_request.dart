import 'package:at_client/src/response/response.dart';
import 'package:at_commons/at_commons.dart';

class Enrollment {
  final int? _enrollmentId;
  final String? _appName;
  final String? _deviceName;
  final List<String> _namespaces;
  final int? _totp;
  final String? _aPKAMPublicKey;
  final EnrollOperationEnum _enrollOperationEnum;

  int? get enrollmentId => _enrollmentId;

  String? get appName => _appName;

  String? get deviceName => _deviceName;

  List<String> get namespaces => _namespaces;

  int? get totp => _totp;

  String? get aPKAMPublicKey => _aPKAMPublicKey;

  EnrollOperationEnum get enrollmentOperation => _enrollOperationEnum;

  Enrollment._builder(EnrollmentBuilder enrollmentBuilder)
      : _enrollmentId = enrollmentBuilder._enrollmentId,
        _appName = enrollmentBuilder._appName,
        _deviceName = enrollmentBuilder._deviceName,
        _namespaces = enrollmentBuilder._namespaces,
        _totp = enrollmentBuilder._totp,
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
  int? _enrollmentId;
  String? _appName;
  String? _deviceName;
  List<String> _namespaces = [];
  int? _totp;
  String? _aPKAMPublicKey;
  late EnrollOperationEnum _enrollmentOperationEnum;

  EnrollmentBuilder setEnrollmentId(int enrollmentId) {
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

  EnrollmentBuilder setNamespaces(List<String> namespaces) {
    _namespaces = namespaces;
    return this;
  }

  EnrollmentBuilder setTotp(int totp) {
    _totp = totp;
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
