class BackendService {
  static final BackendService _singleton = BackendService._internal();

  BackendService._internal();

  factory BackendService.getInstance() {
    return _singleton;
  }
  String? _email;
  String? _otp;

  set setEmail(String? email) {
    _email = email;
  }

  set setOtp(String? otp) {
    _otp = otp;
  }

  String? get getEmail => _email;
  String? get getOtp => _otp;
}
