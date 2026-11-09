import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_commons/at_commons.dart';
import 'package:http/http.dart' as http;

const _apiBase = '/api/app/v4';

/// The most bytes a registrar response body may hold before
/// [RegistrarFailure.responseTooLarge] is thrown.
const _maxResponseBytes = 64 * 1024;

/// The result of [RegistrarAdminService.registerAtsign].
///
/// A super key may add a prefix or postfix to the requested name, so
/// [registeredAtsign] can differ from [requestedAtsign] and is not knowable
/// in advance. Callers must activate as [registeredAtsign], never
/// [requestedAtsign].
class RegisteredAtsign {
  /// The Atsign that was asked for.
  final Atsign requestedAtsign;

  /// The Atsign the registrar actually registered, read from the cramkey it
  /// returned.
  final Atsign registeredAtsign;
  final String cramKey;

  const RegisteredAtsign({
    required this.requestedAtsign,
    required this.registeredAtsign,
    required this.cramKey,
  });
}

/// The result of [RegistrarAdminService.generateAtSignDeleteToken].
class DeleteTokenResult {
  final String token;
  final List<dynamic> atSigns;
  final List<dynamic> skippedAtSigns;

  const DeleteTokenResult({
    required this.token,
    required this.atSigns,
    required this.skippedAtSigns,
  });
}

/// The result of [RegistrarAdminService.deleteAtSigns].
class DeleteAtSignsResult {
  final List<dynamic> deleted;
  final List<dynamic> failed;

  const DeleteAtSignsResult({required this.deleted, required this.failed});
}

/// The v4 `/manage-atsigns/` delete flow, which requires a Super API key.
///
/// Kept apart from [RegistrarService] on purpose: [RegistrarService] ships in
/// client apps (re-exported by `at_client_flutter`, WASM-safe), so putting
/// delete methods on it would encourage compiling a super key into a mobile
/// or web bundle, where it can be extracted. Build this service only in code
/// that holds the super key already, such as an admin tool or backend.
class RegistrarAdminService {
  final String registrarUrl;
  final String _superApiKey;

  /// The super API key this service was constructed with.
  @Deprecated(
      'Will be removed in at_auth 5.0.0; nothing should read the super key back.')
  String get superApiKey => _superApiKey;

  /// How long a single registrar request may take before it fails with
  /// [RegistrarFailure.timeout].
  final Duration requestTimeout;

  late final http.Client _http;

  RegistrarAdminService({
    required this.registrarUrl,
    required String superApiKey,
    this.requestTimeout = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : _superApiKey = superApiKey {
    if (_superApiKey.trim().isEmpty) {
      throw AtException(
          'Registrar super API key is required and cannot be empty.');
    }
    _validateRegistrarUrl(registrarUrl);
    _http = httpClient ?? http.Client();
  }

  static void _validateRegistrarUrl(String registrarUrl) {
    if (registrarUrl.trim().isEmpty) {
      throw ArgumentError.value(
          registrarUrl, 'registrarUrl', 'must not be empty');
    }
    if (registrarUrl.contains('/')) {
      throw ArgumentError.value(registrarUrl, 'registrarUrl',
          'must be a bare host, optionally with a port, with no scheme and no path');
    }
    final hostAndPort = registrarUrl.split(':');
    if (hostAndPort.length > 2 || hostAndPort.first.isEmpty) {
      throw ArgumentError.value(registrarUrl, 'registrarUrl',
          'must be a bare host, optionally followed by ":<port>"');
    }
    if (hostAndPort.length == 2 && int.tryParse(hostAndPort[1]) == null) {
      throw ArgumentError.value(
          registrarUrl, 'registrarUrl', 'port must be numeric');
    }
  }

  Future<http.Response> _manageAtsignsRequest(Map<String, dynamic> data) =>
      _adminRequest(RegistrarApiEndpoint.manageAtsigns, data);

  Future<http.Response> _adminRequest(
    RegistrarApiEndpoint endpoint,
    Map<String, dynamic> data,
  ) async {
    final url = Uri.https(registrarUrl, "$_apiBase${endpoint.path}");
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = _superApiKey
      ..body = jsonEncode(data);

    final http.StreamedResponse streamed;
    try {
      streamed = await _http.send(request).timeout(requestTimeout);
    } on TimeoutException {
      throw RegistrarException(
        'Registrar request timed out after $requestTimeout.',
        endpoint: endpoint.path,
        reason: RegistrarFailure.timeout,
      );
    }

    final bodyBytes = <int>[];
    try {
      await for (final chunk in streamed.stream.timeout(requestTimeout)) {
        bodyBytes.addAll(chunk);
        if (bodyBytes.length > _maxResponseBytes) {
          throw RegistrarException(
            'Registrar response exceeded $_maxResponseBytes bytes.',
            endpoint: endpoint.path,
            statusCode: streamed.statusCode,
            reason: RegistrarFailure.responseTooLarge,
          );
        }
      }
    } on TimeoutException {
      throw RegistrarException(
        'Registrar request timed out after $requestTimeout.',
        endpoint: endpoint.path,
        reason: RegistrarFailure.timeout,
      );
    }

    if (streamed.statusCode == 401 || streamed.statusCode == 403) {
      throw RegistrarException(
        'Registrar super-API-key authentication failed on ${endpoint.path}: '
        'the key is either invalid, missing, or lacks the privilege the '
        'endpoint requires. status=${streamed.statusCode}',
        endpoint: endpoint.path,
        statusCode: streamed.statusCode,
        reason: RegistrarFailure.authentication,
      );
    }

    return http.Response.bytes(bodyBytes, streamed.statusCode,
        headers: streamed.headers, reasonPhrase: streamed.reasonPhrase);
  }

  /// Parses a raw cramkey of the form `@registeredAtsign:key` into the
  /// [Atsign] the registrar actually registered and the bare key.
  ///
  /// `:` is reserved in an Atsign (`at_commons`' `Atsign`), so splitting at
  /// the first `:` always separates the Atsign from the key, however long
  /// a prefix or postfix the registrar added to it.
  (Atsign, String) _parseCramKey(
    String rawCramkey, {
    required String endpoint,
    required int statusCode,
  }) {
    if (!rawCramkey.startsWith('@')) {
      throw RegistrarException(
        'Failed to register an Atsign: cramkey does not start with "@".',
        endpoint: endpoint,
        statusCode: statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final colonIndex = rawCramkey.indexOf(':');
    if (colonIndex < 0) {
      throw RegistrarException(
        'Failed to register an Atsign: cramkey has no ":" separator.',
        endpoint: endpoint,
        statusCode: statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final atsignPart = rawCramkey.substring(0, colonIndex);
    final keyPart = rawCramkey.substring(colonIndex + 1);
    if (keyPart.isEmpty) {
      throw RegistrarException(
        'Failed to register an Atsign: cramkey has no key after its ":".',
        endpoint: endpoint,
        statusCode: statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final Atsign registeredAtsign;
    try {
      registeredAtsign = Atsign(atsignPart);
    } on InvalidAtSignException {
      throw RegistrarException(
        'Failed to register an Atsign: cramkey names an invalid Atsign.',
        endpoint: endpoint,
        statusCode: statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    return (registeredAtsign, keyPart);
  }

  /// Registers [atsign] with the super API key and returns its CRAM key.
  ///
  /// The registrar may register a different Atsign than the one requested
  /// (a super key can add a prefix or postfix); the result's
  /// `registeredAtsign` is the one to activate, read from the registrar's
  /// cramkey, never the one requested.
  ///
  /// ```dart
  /// final admin = RegistrarAdminService(
  ///   registrarUrl: 'my.registrar.example',
  ///   superApiKey: superApiKey,
  /// );
  /// final registered = await admin.registerAtsign(atsign: '@alice'.toAtsign());
  /// ```
  Future<RegisteredAtsign> registerAtsign({required Atsign atsign}) async {
    final endpointPath = RegistrarApiEndpoint.registerAtsign.path;
    final res = await _adminRequest(
      RegistrarApiEndpoint.registerAtsign,
      {
        'operation': RegisterOperation.register.wireValue,
        'atSign': atsign,
        'startatServer': 'true',
      },
    );
    if (res.statusCode != 200) {
      throw RegistrarException(
        'Failed to register an Atsign: unexpected status.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.unexpectedStatus,
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      throw RegistrarException(
        'Failed to register an Atsign: response body is not valid JSON.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    if (decoded is! Map) {
      throw RegistrarException(
        'Failed to register an Atsign: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final status = decoded['status'];
    if (status == 'error') {
      throw RegistrarException(
        'Failed to register an Atsign: the registrar reported an error.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.unavailable,
      );
    }
    if (status != 'success') {
      throw RegistrarException(
        'Failed to register an Atsign: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final rawCramkey = decoded['cramkey'];
    if (rawCramkey is! String) {
      throw RegistrarException(
        'Failed to register an Atsign: the registrar did not return a cramkey.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.noCramKey,
      );
    }
    final (registeredAtsign, cramKey) = _parseCramKey(
      rawCramkey,
      endpoint: endpointPath,
      statusCode: res.statusCode,
    );
    return RegisteredAtsign(
      requestedAtsign: atsign,
      registeredAtsign: registeredAtsign,
      cramKey: cramKey,
    );
  }

  /// Generates a one-time delete token for [atSigns].
  Future<DeleteTokenResult> generateAtSignDeleteToken(
      List<String> atSigns) async {
    final endpointPath = RegistrarApiEndpoint.manageAtsigns.path;
    final res = await _manageAtsignsRequest(
      {'atSigns': atSigns, 'operation': 'deletetoken'},
    );
    if (res.statusCode != 200) {
      throw RegistrarException(
        'Failed to generate delete token: unexpected status.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.unexpectedStatus,
      );
    }
    final dynamic payload;
    try {
      payload = jsonDecode(res.body);
    } on FormatException {
      throw RegistrarException(
        'Failed to generate delete token: response body is not valid JSON.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    if (payload is! Map) {
      throw RegistrarException(
        'Failed to generate delete token: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    if (payload['status'] != 'success' || payload['data'] == null) {
      throw RegistrarException(
        'Failed to generate delete token: the registrar reported an error.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.unavailable,
      );
    }
    return DeleteTokenResult(
      token: payload['data']['token'],
      atSigns: payload['data']['atSigns'] ?? [],
      skippedAtSigns: payload['data']['skippedatSigns'] ?? [],
    );
  }

  /// Deletes [atSigns] using a previously generated delete [token].
  Future<DeleteAtSignsResult> deleteAtSigns({
    required String token,
    required List<String> atSigns,
  }) async {
    final endpointPath = RegistrarApiEndpoint.manageAtsigns.path;
    final res = await _manageAtsignsRequest(
      {'token': token, 'atSigns': atSigns, 'operation': 'delete'},
    );
    if (res.statusCode != 200) {
      throw RegistrarException(
        'Failed to delete atSigns: unexpected status.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.unexpectedStatus,
      );
    }
    final dynamic payload;
    try {
      payload = jsonDecode(res.body);
    } on FormatException {
      throw RegistrarException(
        'Failed to delete atSigns: response body is not valid JSON.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    if (payload is! Map) {
      throw RegistrarException(
        'Failed to delete atSigns: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    if (payload['status'] != 'success' || payload['data'] == null) {
      throw RegistrarException(
        'Failed to delete atSigns: the registrar reported an error.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.unavailable,
      );
    }
    return DeleteAtSignsResult(
      deleted: payload['data']['deleted'] ?? [],
      failed: payload['data']['failed'] ?? [],
    );
  }
}
