import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_details.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollmentBase _atEnrollmentImpl;
  late final AtSignLogger _logger;

  // temporarily cache enrollmentDetails until we store in local secondary
  EnrollmentDetails? _enrollmentDetails;

  EnrollmentServiceImpl(this._atClient, this._atEnrollmentImpl) {
    _logger =
        AtSignLogger('EnrollmentService (${_atClient.getCurrentAtSign()})');
  }

  @override
  Future<List<PendingEnrollmentRequest>> fetchEnrollmentRequests(
      {EnrollListRequestParam? enrollmentListRequest}) async {
    // enrollmentListRequestParams for now is not  used
    // A server side enhancement request is created. https://github.com/atsign-foundation/at_server/issues/1748
    // On implementation of this enhancement/feature, the enrollListRequestParam object can be made use of
    EnrollVerbBuilder enrollBuilder = EnrollVerbBuilder()
      ..operation = EnrollOperationEnum.list
      ..appName = enrollmentListRequest?.appName
      ..deviceName = enrollmentListRequest?.deviceName;

    var response = await _atClient
        .getRemoteSecondary()
        ?.executeCommand(enrollBuilder.buildCommand(), auth: true);

    return _formatEnrollListResponse(response);
  }

  String extractEnrollmentId(String enrollmentKey) {
    return enrollmentKey.split('.')[0];
  }

  List<PendingEnrollmentRequest> _formatEnrollListResponse(response) {
    response = response?.replaceFirst('data:', '');
    Map<String, dynamic> enrollRequests = jsonDecode(response!);
    List<PendingEnrollmentRequest> enrollRequestsFormatted = [];
    for (MapEntry enrollmentRequest in enrollRequests.entries) {
      PendingEnrollmentRequest enrollmentRequestResponse =
          PendingEnrollmentRequest.fromJSON(enrollmentRequest.value);
      enrollmentRequestResponse.enrollmentId =
          extractEnrollmentId(enrollmentRequest.key);
      enrollRequestsFormatted.add(enrollmentRequestResponse);
    }
    return enrollRequestsFormatted;
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.approve(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.deny(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }

  @override
  Future<bool> isAuthorized(String key, VerbBuilder verbBuilder) async {
    // if there is no enrollment, return true
    var enrollmentId = _atClient.enrollmentId;
    _enrollmentDetails ??= await getEnrollmentDetails();
    if (enrollmentId == null ||
        _enrollmentDetails == null ||
        _isReservedKey(key)) {
      return true;
    }
    if (_enrollmentDetails!.enrollmentStatus != EnrollmentStatus.approved) {
      _logger.warning(
          'Enrollment state for $enrollmentId is ${_enrollmentDetails!.enrollmentStatus}');
      return false;
    }
    final enrollNamespaces = _enrollmentDetails!.namespaces;
    var keyNamespace = AtKey.fromString(key).namespace;
    _logger.finer('enrollNamespaces:$enrollNamespaces');
    _logger.finer('keyNamespace:$keyNamespace');
    // * denotes access to all namespaces.
    final access = enrollNamespaces.containsKey('*')
        ? enrollNamespaces['*']
        : enrollNamespaces[keyNamespace];
    _logger.finer('access:$access');

    _logger.shout(
        'Verb builder: $verbBuilder, keyNamespace: $keyNamespace, access: $access');

    if (access == null) {
      return false;
    }
    if (keyNamespace == null && enrollNamespaces.containsKey('*')) {
      if (_isReadAllowed(verbBuilder, access) ||
          _isWriteAllowed(verbBuilder, access)) {
        return true;
      }
      return false;
    }
    return _isReadAllowed(verbBuilder, access) ||
        _isWriteAllowed(verbBuilder, access);
  }

  @visibleForTesting
  Future<EnrollmentDetails> getEnrollmentDetails() async {
    var enrollmentId = _atClient.enrollmentId;
    if (enrollmentId == null) {
      throw AtEnrollmentException(
          'Enrollment ID is not set for the current client');
    }

    var serverEnrollmentKey =
        '$enrollmentId.new.enrollments.__manage${_atClient.getCurrentAtSign()}';
    _logger.finer('serverEnrollmentKey: $serverEnrollmentKey');
    //#TODO improvement - store enrollment details on local secondary after auth is success.Remove call to server.
    var response = await _atClient
        .getRemoteSecondary()
        ?.executeCommand('llookup:$serverEnrollmentKey\n', auth: true);
    if (response == null || response.isEmpty || response == 'data:null') {
      throw AtKeyNotFoundException(
          'Enrollment key for enrollmentId: $enrollmentId not found in server');
    }
    response = response.replaceFirst('data:', '');
    var enrollJson = jsonDecode(response);
    _enrollmentDetails = EnrollmentDetails();
    _enrollmentDetails!.appName = enrollJson[AtConstants.appName];
    _enrollmentDetails!.deviceName = enrollJson[AtConstants.deviceName];
    _enrollmentDetails!.namespaces = enrollJson[AtConstants.apkamNamespaces];
    _enrollmentDetails!.enrollmentStatus =
        getEnrollStatusFromString(enrollJson['approval']['state']);
    return _enrollmentDetails!;
  }

  bool _isReadAllowed(VerbBuilder verbBuilder, String access) {
    return (verbBuilder is LLookupVerbBuilder ||
            verbBuilder is LookupVerbBuilder ||
            verbBuilder is ScanVerbBuilder) &&
        (access == 'r' || access == 'rw');
  }

  bool _isWriteAllowed(VerbBuilder verbBuilder, String access) {
    return (verbBuilder is UpdateVerbBuilder ||
            verbBuilder is DeleteVerbBuilder ||
            verbBuilder is NotifyVerbBuilder ||
            verbBuilder is NotifyAllVerbBuilder ||
            verbBuilder is NotifyRemoveVerbBuilder) &&
        access == 'rw';
  }

  bool _isReservedKey(String? atKey) {
    return atKey == null
        ? false
        : AtKey.getKeyType(atKey) == KeyType.reservedKey;
  }
}
