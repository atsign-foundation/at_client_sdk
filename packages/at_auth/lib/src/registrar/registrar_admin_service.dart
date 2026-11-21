import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/registrar/registrar_exceptions.dart';
import 'package:at_commons/at_commons.dart';
import 'package:http/http.dart' as http;

const _apiBase = '/api/app/v4';

/// Cancels [subscription], swallowing any error its `onCancel` raises.
Future<void> _cancelQuietly<T>(StreamSubscription<T>? subscription) async {
  try {
    await subscription?.cancel();
  } catch (_) {}
}

/// Lets an outer timeout cancel a request's active body-read subscription.
class _ReadCancelToken {
  StreamSubscription<List<int>>? _subscription;

  void attach(StreamSubscription<List<int>> subscription) {
    _subscription = subscription;
  }

  /// Cancels the attached subscription, if any.
  Future<void> cancel() => _cancelQuietly(_subscription);
}

/// The most bytes a registrar response body may hold before
/// [RegistrarFailure.responseTooLarge] is thrown.
const _maxResponseBytes = 64 * 1024;

/// The result of [RegistrarAdminService.registerAtsign].
///
/// [registeredAtsign] may differ from [requestedAtsign]; activate as
/// [registeredAtsign].
class RegisteredAtsign {
  /// The Atsign that was asked for.
  final Atsign requestedAtsign;

  /// The Atsign the registrar actually registered, read from the cramkey it
  /// returned.
  final Atsign registeredAtsign;

  /// The bare key, with the registrar's `@registeredAtsign:` prefix removed.
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

/// Registration and the v4 `/manage-atsigns/` delete flow, both of which
/// require a Super API key.
///
/// Kept apart from [RegistrarService] on purpose: [RegistrarService] ships in
/// client apps (re-exported by `at_client_flutter`, WASM-safe), so putting
/// these methods on it would encourage compiling a super key into a mobile
/// or web bundle, where it can be extracted. Build this service only in code
/// that holds the super key already, such as an admin tool or backend.
class RegistrarAdminService {
  final String registrarUrl;
  final String _superApiKey;

  @Deprecated('Will be removed in at_auth 5.0.0.')
  String get superApiKey => _superApiKey;

  /// How long a single registrar request may take before it fails with
  /// [RegistrarFailure.timeout].
  final Duration requestTimeout;

  final http.Client? _httpClient;

  /// Creates the client for one request when none was given, in the zone the
  /// service was built in.
  final http.Client Function() _newHttpClient =
      Zone.current.bindCallback(http.Client.new);

  /// With no [httpClient], each request takes a new client from
  /// `http.Client()` and closes it when the request ends, so a
  /// `runWithClient` factory must return a new client for each call. An
  /// [httpClient] that is given is never closed.
  ///
  /// Throws [AtException] if [superApiKey] is empty or all whitespace.
  ///
  /// Throws [ArgumentError] if [superApiKey] contains a code unit outside
  /// `0x20`-`0x7E`, or if [registrarUrl] is not an authority [Uri.https]
  /// accepts, names no host or one of only whitespace and dots, carries user
  /// info, or has a port outside 1-65535, or if [requestTimeout] is not
  /// positive.
  RegistrarAdminService({
    required this.registrarUrl,
    required String superApiKey,
    this.requestTimeout = const Duration(seconds: 30),
    http.Client? httpClient,
  })  : _superApiKey = superApiKey,
        _httpClient = httpClient {
    if (_superApiKey.trim().isEmpty) {
      throw AtException(
          'Registrar super API key is required and cannot be empty.');
    }
    if (_superApiKey.codeUnits.any((c) => c < 0x20 || c > 0x7E)) {
      throw ArgumentError(
          'superApiKey must contain only visible ASCII characters and '
              'spaces (0x20-0x7E)',
          'superApiKey');
    }
    _validateRegistrarUrl(registrarUrl);
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
          requestTimeout, 'requestTimeout', 'must be positive');
    }
  }

  static void _validateRegistrarUrl(String registrarUrl) {
    const invalidMessage =
        'registrarUrl must be an authority Uri.https accepts, with a host, no '
        'user info and a port between 1 and 65535';
    final Uri uri;
    try {
      uri = Uri.https(registrarUrl, '/');
    } on FormatException {
      throw ArgumentError(invalidMessage, 'registrarUrl');
    }
    if (_isBlankHost(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw ArgumentError(invalidMessage, 'registrarUrl');
    }
  }

  /// Whether [host], with its percent-escapes decoded, holds only whitespace
  /// and dots.
  static bool _isBlankHost(String host) {
    try {
      return Uri.decodeComponent(host).replaceAll('.', '').trim().isEmpty;
    } on FormatException {
      return false;
    }
  }

  Future<http.Response> _manageAtsignsRequest(Map<String, dynamic> data) =>
      _adminRequest(RegistrarApiEndpoint.manageAtsigns, data);

  /// Sends [data] to [endpoint] and reads its response, bounded together by
  /// [requestTimeout]. Returns only a 200 response; any other status throws
  /// before its body is read.
  Future<http.Response> _adminRequest(
    RegistrarApiEndpoint endpoint,
    Map<String, dynamic> data,
  ) async {
    final url = Uri.https(registrarUrl, "$_apiBase${endpoint.path}");
    final requestBody = utf8.encode(jsonEncode(data));
    final cancelToken = _ReadCancelToken();
    final abortTrigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'POST',
      url,
      abortTrigger: abortTrigger.future,
    )
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = _superApiKey
      ..contentLength = requestBody.length
      ..sink.add(requestBody);
    unawaited(request.sink.close());

    final client = _httpClient ?? _newHttpClient();
    try {
      return await _sendAndReadResponse(
              client, endpoint, request, cancelToken, abortTrigger)
          .timeout(requestTimeout);
    } on TimeoutException {
      if (!abortTrigger.isCompleted) abortTrigger.complete();
      unawaited(cancelToken.cancel());
      throw RegistrarException(
        'Registrar request timed out after $requestTimeout.',
        endpoint: endpoint.path,
        reason: RegistrarFailure.timeout,
      );
    } on RegistrarException {
      rethrow;
    } on Exception {
      throw RegistrarException(
        'Registrar request to ${endpoint.path} failed: the connection could '
        'not be completed.',
        endpoint: endpoint.path,
        reason: RegistrarFailure.network,
      );
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  Future<http.Response> _sendAndReadResponse(
    http.Client client,
    RegistrarApiEndpoint endpoint,
    http.AbortableStreamedRequest request,
    _ReadCancelToken cancelToken,
    Completer<void> abortTrigger,
  ) async {
    final streamed = await client.send(request);

    final requestAlreadyTimedOut = abortTrigger.isCompleted;
    if (requestAlreadyTimedOut) {
      await _cancelQuietly(streamed.stream.listen(null));
      throw RegistrarException(
        'Registrar request to ${endpoint.path} timed out after the '
        'response arrived.',
        endpoint: endpoint.path,
        reason: RegistrarFailure.timeout,
      );
    }

    if (streamed.statusCode == 401 || streamed.statusCode == 403) {
      unawaited(_cancelQuietly(streamed.stream.listen(null)));
      throw RegistrarException(
        'Registrar super-API-key authentication failed on ${endpoint.path}: '
        'the key is either invalid, missing, or lacks the privilege the '
        'endpoint requires. status=${streamed.statusCode}',
        endpoint: endpoint.path,
        statusCode: streamed.statusCode,
        reason: RegistrarFailure.authentication,
      );
    }

    if (streamed.statusCode != 200) {
      unawaited(_cancelQuietly(streamed.stream.listen(null)));
      throw RegistrarException(
        'Registrar request to ${endpoint.path} returned unexpected status '
        '${streamed.statusCode}.',
        endpoint: endpoint.path,
        statusCode: streamed.statusCode,
        reason: RegistrarFailure.unexpectedStatus,
      );
    }

    final bodyBytes = <int>[];
    final bodyRead = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = streamed.stream.listen(
      (chunk) {
        if (bodyBytes.length + chunk.length > _maxResponseBytes) {
          if (!bodyRead.isCompleted) {
            bodyRead.completeError(RegistrarException(
              'Registrar response exceeded $_maxResponseBytes bytes.',
              endpoint: endpoint.path,
              statusCode: streamed.statusCode,
              reason: RegistrarFailure.responseTooLarge,
            ));
          }
          unawaited(_cancelQuietly(subscription));
          return;
        }
        bodyBytes.addAll(chunk);
      },
      onDone: () {
        if (!bodyRead.isCompleted) bodyRead.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!bodyRead.isCompleted) bodyRead.completeError(error, stackTrace);
      },
      cancelOnError: true,
    );
    cancelToken.attach(subscription);
    await bodyRead.future;

    return http.Response.bytes(bodyBytes, streamed.statusCode,
        headers: streamed.headers, reasonPhrase: streamed.reasonPhrase);
  }

  /// Parses a raw cramkey (`@registeredAtsign:key`) into the registered
  /// [Atsign] and the bare key, splitting at the first `:`.
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
  /// Not idempotent: a failure other than [RegistrarFailure.authentication] or
  /// [RegistrarFailure.registrarError] may still have committed the
  /// registration, leaving [atsign] registered under a CRAM secret nobody
  /// holds. Reconcile — look it up, or run the delete flow — before retrying
  /// with the same [atsign].
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
        reason: RegistrarFailure.registrarError,
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
    final status = payload['status'];
    if (status == 'error') {
      throw RegistrarException(
        'Failed to generate delete token: the registrar reported an error.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.registrarError,
      );
    }
    if (status != 'success' || payload['data'] is! Map) {
      throw RegistrarException(
        'Failed to generate delete token: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final data = payload['data'] as Map;
    final token = data['token'];
    final resultAtSigns = data['atSigns'] ?? [];
    final skippedAtSigns = data['skippedatSigns'] ?? [];
    if (token is! String ||
        token.isEmpty ||
        resultAtSigns is! List ||
        resultAtSigns.any((a) => a is! String) ||
        skippedAtSigns is! List ||
        skippedAtSigns.any((a) => a is! String)) {
      throw RegistrarException(
        'Failed to generate delete token: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    return DeleteTokenResult(
      token: token,
      atSigns: resultAtSigns,
      skippedAtSigns: skippedAtSigns,
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
    final status = payload['status'];
    if (status == 'error') {
      throw RegistrarException(
        'Failed to delete atSigns: the registrar reported an error.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.registrarError,
      );
    }
    if (status != 'success' || payload['data'] is! Map) {
      throw RegistrarException(
        'Failed to delete atSigns: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    final data = payload['data'] as Map;
    final deleted = data['deleted'] ?? [];
    final failed = data['failed'] ?? [];
    if (deleted is! List || failed is! List) {
      throw RegistrarException(
        'Failed to delete atSigns: unexpected response shape.',
        endpoint: endpointPath,
        statusCode: res.statusCode,
        reason: RegistrarFailure.malformedResponse,
      );
    }
    return DeleteAtSignsResult(deleted: deleted, failed: failed);
  }
}
