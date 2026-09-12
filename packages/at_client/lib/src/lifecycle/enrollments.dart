import 'package:at_auth/at_auth.dart' show EnrollmentRequestDecision;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_commons.dart';

/// A passcode the atServer issued or accepted, and when it stops working.
class Passcode {
  final String value;
  final DateTime expiry;

  Passcode(this.value, this.expiry);

  bool get isExpired => DateTime.now().isAfter(expiry);

  @override
  String toString() => value;
}

/// This atSign's enrollments, managed through a client that authenticates as
/// one holding `__manage`: the roster, the decisions on it, and the passcodes
/// a new request has to quote.
///
/// ```dart
/// for (final request in await client.enrollments.pending()) { ... }
/// await client.enrollments.approve(request.enrollmentId!);
/// final otp = await client.enrollments.otp();
/// ```
///
/// Reached as `client.enrollments`. Approving here is the approval that
/// conveys: this atSign's secrets are sealed to the enrollee's key package
/// as well as wrapped under the legacy symmetric key, which an approval
/// issued below the client cannot do.
class Enrollments {
  final AtClient _client;

  Enrollments(this._client);

  /// How long a passcode from [otp] or [spp] stays valid when the caller
  /// states no expiry.
  static const Duration defaultPasscodeExpiry = Duration(minutes: 5);

  /// The roster, narrowed to [statuses] when given, and to an [app] or a
  /// [device] name when given.
  Future<List<Enrollment>> list(
      {List<EnrollmentStatus>? statuses, String? app, String? device}) {
    final params = EnrollmentListRequestParam()
      ..appName = app
      ..deviceName = device;
    if (statuses != null) params.enrollmentListFilter = statuses;
    return _service.fetchEnrollmentRequests(enrollmentListParams: params);
  }

  /// The requests awaiting a decision.
  Future<List<Enrollment>> pending() =>
      list(statuses: const [EnrollmentStatus.pending]);

  /// Approves [enrollmentId], conveying this atSign's secrets to the device
  /// it names. Throws [AtEnrollmentException] when no such request is
  /// awaiting approval.
  Future<void> approve(String enrollmentId) async {
    final request = (await list(statuses: const [
      EnrollmentStatus.pending,
      EnrollmentStatus.approved,
    ]))
        .where((e) => e.enrollmentId == enrollmentId)
        .firstOrNull;
    if (request == null) {
      throw AtEnrollmentException(
          '$_atSign has no enrollment $enrollmentId awaiting approval');
    }
    await _service.approve(EnrollmentRequestDecision.approved(
        enrollmentId: enrollmentId,
        // Empty when the request advertised a key package instead of wrapping
        // a key, which is what asks the approval to mint one.
        apkamSymmetricKey:
            AtBytes.fromString(request.encryptedAPKAMSymmetricKey ?? ''),
        atSign: _atSign));
  }

  /// Denies [enrollmentId]; the device it names never authenticates.
  Future<void> deny(String enrollmentId) =>
      _service.deny(EnrollmentRequestDecision.denied(enrollmentId, _atSign));

  /// Revokes [enrollmentId], closing its connections; [force] lets a client
  /// revoke the enrollment it is itself running as.
  Future<void> revoke(String enrollmentId, {bool force = false}) => _service
      .revoke(EnrollmentRequestDecision.revoked(enrollmentId, _atSign, force: force));

  /// A one-time passcode a new request may quote until [expiry] has passed.
  Future<Passcode> otp({Duration expiry = defaultPasscodeExpiry}) async {
    final response = await _client
        .getRemoteSecondary()!
        .executeCommand('otp:get:ttl:${expiry.inMilliseconds}\n', auth: true);
    if (response == null || !response.startsWith('data:')) {
      throw AtEnrollmentException(
          'the atServer issued no passcode for $_atSign: $response');
    }
    return Passcode(response.substring('data:'.length).trim(),
        DateTime.now().add(expiry));
  }

  /// Sets [passcode], six alphanumeric characters, as a passcode any number
  /// of requests may quote until [expiry] has passed.
  Future<Passcode> spp(String passcode,
      {Duration expiry = defaultPasscodeExpiry}) async {
    await _client.setSPP(passcode, expiry: expiry);
    return Passcode(passcode, DateTime.now().add(expiry));
  }

  String get _atSign => _client.getCurrentAtSign()!;

  EnrollmentService get _service {
    final service = _client.enrollmentService;
    if (service == null) {
      throw StateError('this client has no enrollment service wired, so it '
          'cannot manage enrollments');
    }
    return service;
  }
}

/// `client.enrollments`: the approving side of enrollment.
extension AtClientEnrollments on AtClient {
  Enrollments get enrollments => Enrollments(this);
}
