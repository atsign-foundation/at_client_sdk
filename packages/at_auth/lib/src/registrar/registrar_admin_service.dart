import 'dart:convert';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_commons/at_commons.dart';
import 'package:http/http.dart' as http;

const _apiBase = '/api/app/v4';

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

  /// Registers [atSign] under the super API key, authorizing the same way
  /// [_manageAtsignsRequest] does.
  ///
  /// Throws [AtException] on an auth failure and [Exception] when the
  /// response is not a 200, `status` is not `success`, or the cramkey is
  /// missing.
  Future<RegisterAtSignResult> registerAtSign({required String atSign}) async {
    var res = await _adminRequest(
      RegistrarApiEndpoint.registerAtsign,
      {'operation': RegisterOperation.register.wireValue, 'atSign': atSign},
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to register atSign: ${res.reasonPhrase} (status=${res.statusCode})');
    }
    var payload = jsonDecode(res.body);
    if (payload["status"] != "success") {
      throw Exception(
          'Failed to register atSign: ${payload["message"] ?? "Unknown error"}');
    }
    String? cramKey = payload["cramkey"]?.split(':').last;
    if (cramKey == null) {
      throw Exception(
          'Failed to register atSign: cramKey missing from payload');
    }
    return RegisterAtSignResult(
      cramKey: cramKey,
      atSign: payload["atSign"],
      message: payload["message"],
    );
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
