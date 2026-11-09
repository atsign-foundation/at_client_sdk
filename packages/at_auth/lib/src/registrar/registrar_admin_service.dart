import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_commons/at_commons.dart';
import 'package:http/http.dart' as http;

const _apiBase = '/api/app/v4';

/// The result of [RegistrarAdminService.registerAtsign].
class RegisteredAtsign {
  final Atsign atsign;
  final String cramKey;

  const RegisteredAtsign({required this.atsign, required this.cramKey});
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
  final String superApiKey;
  late final http.Client _http;

  RegistrarAdminService({
    required this.registrarUrl,
    required this.superApiKey,
    http.Client? httpClient,
  }) {
    if (superApiKey.trim().isEmpty) {
      throw AtException(
          'Registrar super API key is required and cannot be empty.');
    }
    _http = httpClient ?? http.Client();
  }

  Future<http.Response> _manageAtsignsRequest(Map<String, dynamic> data) =>
      _adminRequest(RegistrarApiEndpoint.manageAtsigns, data);

  Future<http.Response> _adminRequest(
    RegistrarApiEndpoint endpoint,
    Map<String, dynamic> data,
  ) async {
    final url = Uri.https(registrarUrl, "$_apiBase${endpoint.path}");
    final response = await _http.post(
      url,
      body: jsonEncode(data),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': superApiKey,
      },
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AtException(
        'Registrar super-API-key authentication failed on '
        '${endpoint.path}: the key is either invalid, missing, or lacks '
        'the privilege the endpoint requires. status=${response.statusCode}',
      );
    }
    return response;
  }

  /// Registers [atsign] with the super API key and returns its CRAM key.
  ///
  /// Throws [AtException] when the super key is rejected, and
  /// [RegistrarException] when the registrar's response is not a usable
  /// 200 with a cramkey.
  ///
  /// ```dart
  /// final admin = RegistrarAdminService(
  ///   registrarUrl: 'my.registrar.example',
  ///   superApiKey: superApiKey,
  /// );
  /// final registered = await admin.registerAtsign(atsign: '@alice'.toAtsign());
  /// ```
  Future<RegisteredAtsign> registerAtsign({required Atsign atsign}) async {
    final res = await _adminRequest(
      RegistrarApiEndpoint.registerAtsign,
      {'operation': RegisterOperation.register.wireValue, 'atSign': atsign},
    );
    final endpointPath = RegistrarApiEndpoint.registerAtsign.path;
    if (res.statusCode != 200) {
      throw RegistrarException(
          'Failed to register an Atsign: status=${res.statusCode}, endpoint=$endpointPath');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      throw RegistrarException(
          'Failed to register an Atsign: response body is not valid JSON, endpoint=$endpointPath');
    }
    if (decoded is! Map || decoded["status"] != "success") {
      throw RegistrarException(
          'Failed to register an Atsign: unexpected response shape, endpoint=$endpointPath');
    }
    final rawCramkey = decoded["cramkey"];
    if (rawCramkey is! String) {
      throw RegistrarException(
          'Failed to register an Atsign: cramkey missing from response, endpoint=$endpointPath');
    }
    final cramKey = rawCramkey.split(':').last;
    if (cramKey.isEmpty) {
      throw RegistrarException(
          'Failed to register an Atsign: cramkey missing from response, endpoint=$endpointPath');
    }
    return RegisteredAtsign(atsign: atsign, cramKey: cramKey);
  }

  /// Generates a one-time delete token for [atSigns].
  Future<DeleteTokenResult> generateAtSignDeleteToken(
      List<String> atSigns) async {
    var res = await _manageAtsignsRequest(
      {'atSigns': atSigns, 'operation': 'deletetoken'},
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to generate delete token: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);
    if (payload["status"] != "success" || payload["data"] == null) {
      throw Exception(
          'Failed to generate delete token: ${payload["message"] ?? "Unknown error"}');
    }
    return DeleteTokenResult(
      token: payload["data"]["token"],
      atSigns: payload["data"]["atSigns"] ?? [],
      skippedAtSigns: payload["data"]["skippedatSigns"] ?? [],
    );
  }

  /// Deletes [atSigns] using a previously generated delete [token].
  Future<DeleteAtSignsResult> deleteAtSigns({
    required String token,
    required List<String> atSigns,
  }) async {
    var res = await _manageAtsignsRequest(
      {'token': token, 'atSigns': atSigns, 'operation': 'delete'},
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to delete atSigns: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);
    if (payload["status"] != "success" || payload["data"] == null) {
      throw Exception(
          'Failed to delete atSigns: ${payload["message"] ?? "Unknown error"}');
    }
    return DeleteAtSignsResult(
      deleted: payload["data"]["deleted"] ?? [],
      failed: payload["data"]["failed"] ?? [],
    );
  }
}
