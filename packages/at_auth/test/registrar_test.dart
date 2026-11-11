import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/registrar/registrar_admin_service.dart';
import 'package:at_auth/src/registrar/registrar_exceptions.dart';
import 'package:at_auth/src/registrar/registrar_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _registrarUrl = 'my.registrar.test';
const _apiKey = 'test-api-key';

/// A [List] that records whether its elements were ever read, so a test can
/// tell whether a chunk was copied into a buffer without a new public API.
class _SpyBytes extends ListBase<int> {
  final List<int> _bytes;
  bool wasRead = false;

  _SpyBytes(this._bytes);

  @override
  int get length => _bytes.length;

  @override
  set length(int newLength) => throw UnsupportedError('fixed length');

  @override
  int operator [](int index) {
    wasRead = true;
    return _bytes[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('fixed length');
}

RegistrarService _makeService(MockClient client) => RegistrarService(
      registrarUrl: _registrarUrl,
      apiKey: _apiKey,
      httpClient: client,
    );

RegistrarAdminService _makeAdminService(MockClient client) =>
    RegistrarAdminService(
      registrarUrl: _registrarUrl,
      superApiKey: _apiKey,
      httpClient: client,
    );

MockClient _mockResponse(Object body, {int status = 200}) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

void main() {
  group('constructor validation', () {
    test('throws when apiKey is empty', () {
      expect(
        () => RegistrarService(
          registrarUrl: _registrarUrl,
          apiKey: '',
          httpClient: _mockResponse({}),
        ),
        throwsException,
      );
    });

    test('throws when apiKey is whitespace', () {
      expect(
        () => RegistrarService(
          registrarUrl: _registrarUrl,
          apiKey: '   ',
          httpClient: _mockResponse({}),
        ),
        throwsException,
      );
    });

    test('throws when superApiKey is empty', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: _registrarUrl,
          superApiKey: '',
          httpClient: _mockResponse({}),
        ),
        throwsException,
      );
    });

    test('throws ArgumentError naming registrarUrl when it is empty', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('throws ArgumentError naming registrarUrl when it carries a scheme',
        () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: 'https://$_registrarUrl',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('throws ArgumentError naming registrarUrl when it carries a path', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl/path',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('accepts a bare host with a port', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl:8443',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        returnsNormally,
      );
    });

    test('throws ArgumentError naming registrarUrl when it carries user info',
        () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl@evil.example',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('throws ArgumentError naming registrarUrl when it carries a fragment',
        () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl#frag',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('throws ArgumentError naming registrarUrl when it carries a query',
        () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl?q=1',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('throws ArgumentError naming registrarUrl when it carries whitespace',
        () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl ',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        ),
      );
    });

    test('ArgumentError for registrarUrl never echoes the offending value', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: 'user:secret@host',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        throwsA(
          predicate(
            (e) =>
                e is ArgumentError &&
                e.name == 'registrarUrl' &&
                !e.toString().contains('secret'),
          ),
        ),
      );
    });

    for (final port in ['0', '-1', '65536', 'abc']) {
      test('throws ArgumentError naming registrarUrl when the port is $port',
          () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: '$_registrarUrl:$port',
            superApiKey: _apiKey,
            httpClient: _mockResponse({}),
          ),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
          ),
        );
      });
    }
  });

  group('sendActivationOtp', () {
    test('returns true on success', () async {
      final service =
          _makeService(_mockResponse({'message': 'Sent Successfully'}));
      expect(await service.sendActivationOtp('@alice'), isTrue);
    });

    test('returns false on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Server Error'}, status: 500));
      expect(await service.sendActivationOtp('@alice'), isFalse);
    });

    test('throws helpful exception on 401 auth failure', () async {
      final service =
          _makeService(_mockResponse({'message': 'Unauthorized'}, status: 401));
      expect(
        () => service.sendActivationOtp('@alice'),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('invalid or missing API key') &&
                e.toString().contains('/authenticate/atsign'),
          ),
        ),
      );
    });

    test('throws helpful exception on 403 auth failure', () async {
      final service =
          _makeService(_mockResponse({'message': 'Forbidden'}, status: 403));
      expect(
        () => service.sendActivationOtp('@alice'),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('invalid or missing API key') &&
                e.toString().contains('/authenticate/atsign'),
          ),
        ),
      );
    });

    test('returns false when message is not "Sent Successfully"', () async {
      final service = _makeService(_mockResponse({'message': 'Already sent'}));
      expect(await service.sendActivationOtp('@alice'), isFalse);
    });
  });

  group('verifyActivation', () {
    test('returns cram key portion on success', () async {
      final service = _makeService(_mockResponse(
          {'message': 'Verified', 'cramkey': 'prefix:THECRAMKEY'}));
      final result =
          await service.verifyActivation(atSign: '@alice', otp: '1234');
      expect(result, equals('THECRAMKEY'));
    });

    test('throws on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Unauthorized'}, status: 401));
      expect(
        () => service.verifyActivation(atSign: '@alice', otp: '0000'),
        throwsException,
      );
    });

    test('throws when message is not "Verified"', () async {
      final service = _makeService(_mockResponse({'message': 'Invalid OTP'}));
      expect(
        () => service.verifyActivation(atSign: '@alice', otp: '9999'),
        throwsException,
      );
    });
  });

  group('registerAtSign', () {
    test('returns atSign and message on lookup success', () async {
      final service = _makeService(_mockResponse({
        'status': 'success',
        'message': 'atSign is available',
        'atSign': 'ash12_3_102',
      }));
      final result = await service.registerAtSign(
          atSign: 'ash12_3_102', operation: RegisterOperation.lookup);
      expect(result.atSign, equals('ash12_3_102'));
      expect(result.message, equals('atSign is available'));
      expect(result.cramKey, isNull);
    });

    test('returns stripped cramkey on register success', () async {
      final service = _makeService(
          _mockResponse({'status': 'success', 'cramkey': 'prefix:REGCRAMKEY'}));
      final result =
          await service.registerAtSign(operation: RegisterOperation.register);
      expect(result.cramKey, equals('REGCRAMKEY'));
    });

    test('throws when register succeeds but the cramkey is missing', () async {
      final service = _makeService(_mockResponse({'status': 'success'}));
      expect(
        () => service.registerAtSign(operation: RegisterOperation.register),
        throwsException,
      );
    });

    test('does not throw for a missing cramkey when startAtServer is false',
        () async {
      final service = _makeService(_mockResponse({'status': 'success'}));
      final result = await service.registerAtSign(
        operation: RegisterOperation.register,
        startAtServer: false,
      );
      expect(result.cramKey, isNull);
    });

    test('throws on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.registerAtSign(operation: RegisterOperation.register),
        throwsException,
      );
    });

    test('throws when status is not "success"', () async {
      final service = _makeService(_mockResponse(
          {'status': 'error', 'message': 'atSign not available'}));
      expect(
        () => service.registerAtSign(
            atSign: 'taken', operation: RegisterOperation.register),
        throwsException,
      );
    });
  });

  group('RegistrarAdminService.registerAtsign', () {
    test('returns the registered and requested atsign and the cramkey',
        () async {
      final service = _makeAdminService(_mockResponse(
          {'status': 'success', 'cramkey': '@alice:ADMINCRAMKEY'}));
      final result = await service.registerAtsign(atsign: '@alice'.toAtsign());
      expect(result.requestedAtsign, equals('@alice'.toAtsign()));
      expect(result.registeredAtsign, equals('@alice'.toAtsign()));
      expect(result.cramKey, equals('ADMINCRAMKEY'));
    });

    test(
        'returns the registrar-chosen atsign, distinct from the one requested, '
        'when a super key prefix/postfix was applied', () async {
      final service = _makeAdminService(_mockResponse(
          {'status': 'success', 'cramkey': '@acme_alice:ADMINCRAMKEY'}));
      final result = await service.registerAtsign(atsign: '@alice'.toAtsign());
      expect(result.requestedAtsign, equals('@alice'.toAtsign()));
      expect(result.registeredAtsign, equals('@acme_alice'.toAtsign()));
      expect(result.cramKey, equals('ADMINCRAMKEY'));
    });

    test('splits the cramkey at the first ":", not the last', () async {
      final service = _makeAdminService(_mockResponse(
          {'status': 'success', 'cramkey': '@alice:part1:part2'}));
      final result = await service.registerAtsign(atsign: '@alice'.toAtsign());
      expect(result.registeredAtsign, equals('@alice'.toAtsign()));
      expect(result.cramKey, equals('part1:part2'));
    });

    test('sends the super key, the requested atsign and startatServer=true',
        () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({'status': 'success', 'cramkey': '@alice:KEY'}), 200);
      });
      final service = _makeAdminService(client);
      await service.registerAtsign(atsign: '@alice'.toAtsign());

      expect(captured.url.scheme, equals('https'));
      expect(captured.url.host, equals(_registrarUrl));
      expect(captured.url.path, equals('/api/app/v4/register-atsign/'));
      expect(captured.headers['Authorization'], equals(_apiKey));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['atSign'], equals('@alice'));
      expect(body['operation'], equals('register'));
      expect(body['startatServer'], equals('true'));
      expect(body['startatServer'], isA<String>());
    });

    test(
        'throws RegistrarException(noCramKey) when register succeeds but '
        'the cramkey is missing', () async {
      final service = _makeAdminService(_mockResponse({'status': 'success'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having((e) => e.reason, 'reason', RegistrarFailure.noCramKey)
              .having((e) => e.endpoint, 'endpoint', '/register-atsign/'),
        ),
      );
    });

    test('throws RegistrarException when the cramkey has no "@" prefix',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': 'alice:KEY'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('throws RegistrarException when the cramkey has no ":" separator',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': '@alice'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('throws RegistrarException when the cramkey is an empty string',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': ''}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
      );
    });

    test(
        'throws RegistrarException when the cramkey has no value after its ":"',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': '@alice:'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
      );
    });

    test('throws RegistrarException when the cramkey names an invalid atsign',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': '@alice!:KEY'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('throws RegistrarException when the cramkey is not a string',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': 12345}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
      );
    });

    test(
        'throws RegistrarException when the response body is not a JSON object',
        () async {
      final client = MockClient((_) async => http.Response('[1, 2, 3]', 200));
      final service = _makeAdminService(client);
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('throws RegistrarException(malformedResponse) on real non-JSON',
        () async {
      final client = MockClient(
          (_) async => http.Response('<html>502 Bad Gateway</html>', 200));
      final service = _makeAdminService(client);
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'RegistrarException text carries neither the cramkey nor the server message',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'cramkey': '@alice!invalid:SHOULDNOTLEAK',
      }));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          predicate(
            (e) =>
                e is RegistrarException &&
                !e.toString().contains('SHOULDNOTLEAK'),
          ),
        ),
      );
    });

    test('throws RegistrarException(unavailable) when status is "error"',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message': 'super-secret-server-detail',
      }));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having((e) => e.reason, 'reason', RegistrarFailure.unavailable)
              .having(
                  (e) => e.toString().contains('super-secret-server-detail'),
                  'leaks the server message',
                  isFalse),
        ),
      );
    });

    test('throws RegistrarException(unexpectedStatus) on non-200 status',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.unexpectedStatus)
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test(
        'throws RegistrarException(unexpectedStatus) on a non-200 whose body '
        'looks like success', () async {
      final service = _makeAdminService(_mockResponse(
          {'status': 'success', 'cramkey': '@alice:k'},
          status: 500));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.unexpectedStatus)
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.endpoint, 'endpoint', '/register-atsign/')),
      );
    });

    test('401 raises RegistrarException(authentication) without the super key',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Unauthorized'}, status: 401));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having(
                  (e) => e.reason, 'reason', RegistrarFailure.authentication)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.endpoint, 'endpoint', '/register-atsign/')
              .having((e) => e.toString().contains(_apiKey), 'leaks the key',
                  isFalse),
        ),
      );
    });

    test('403 raises RegistrarException(authentication) without the super key',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Forbidden'}, status: 403));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having(
                  (e) => e.reason, 'reason', RegistrarFailure.authentication)
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.toString().contains(_apiKey), 'leaks the key',
                  isFalse),
        ),
      );
    });

    test('times out instead of hanging forever', () async {
      final neverResponds = Completer<http.StreamedResponse>();
      final client = MockClient.streaming((request, bodyStream) async {
        return await neverResponds.future;
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.timeout)),
      );
    });

    test(
        'times out on a body that drips slower in total than requestTimeout, '
        'even though no single gap between chunks exceeds it', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>();
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
          if (timer.tick > 5) {
            timer.cancel();
            controller.close();
            return;
          }
          controller.add(utf8.encode('x'));
        });
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.timeout)),
      );
    });

    test('rejects a response body over the size cap', () async {
      final oversized = 'x' * (70 * 1024);
      final client = MockClient((_) async => http.Response(oversized, 200));
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.responseTooLarge)),
      );
    });

    test(
        'enforces the response cap before buffering a single oversized '
        'chunk', () async {
      final spyChunk = _SpyBytes(List<int>.filled(70 * 1024, 0));
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>();
        controller.add(spyChunk);
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.responseTooLarge)),
      );
      expect(spyChunk.wasRead, isFalse,
          reason: 'an oversized chunk must never be copied into the buffer');
    });

    test('cancels the stream once many small chunks cross the response cap',
        () async {
      var cancelled = false;
      var chunksSent = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        unawaited(() async {
          for (var i = 0; i < 20 && !cancelled; i++) {
            chunksSent++;
            controller.add(List<int>.filled(4 * 1024, 0));
            await Future<void>.delayed(Duration.zero);
          }
          if (!controller.isClosed) await controller.close();
        }());
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.responseTooLarge)),
      );
      expect(chunksSent, lessThan(20),
          reason: 'the stream must be cancelled once the cap is crossed, '
              'not drained to completion');
    });

    test('the deprecated superApiKey getter still returns the key', () {
      final service = _makeAdminService(_mockResponse({}));
      // ignore: deprecated_member_use_from_same_package
      expect(service.superApiKey, equals(_apiKey));
    });

    test(
        'throws RegistrarException(network) when the connection fails, '
        'without leaking the super key', () async {
      final client = MockClient((_) async {
        throw http.ClientException('Connection refused');
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having((e) => e.reason, 'reason', RegistrarFailure.network)
              .having((e) => e.endpoint, 'endpoint', '/register-atsign/')
              .having((e) => e.toString().contains(_apiKey), 'leaks the key',
                  isFalse),
        ),
      );
    });

    test(
        'a 401 whose body exceeds the size cap still reports authentication, '
        'not responseTooLarge', () async {
      final oversized = 'x' * (70 * 1024);
      final client = MockClient((_) async => http.Response(oversized, 401));
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.authentication)
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('cancels the body subscription when the request times out', () async {
      var wasCancelled = false;
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>(
          onCancel: () => wasCancelled = true,
        );
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.timeout)),
      );
      expect(wasCancelled, isTrue);
    });

    test('aborts the in-flight request via Abortable when it times out',
        () async {
      http.BaseRequest? captured;
      final client = MockClient.streaming((request, bodyStream) async {
        captured = request;
        return await Completer<http.StreamedResponse>().future;
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.timeout)),
      );
      expect(captured, isA<http.Abortable>());
      await expectLater((captured as http.Abortable).abortTrigger, completes);
    });

    test(
        'cancelling the body subscription on timeout does not surface an '
        'unhandled error when onCancel throws', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>(
          onCancel: () => throw StateError('onCancel boom'),
        );
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.timeout)),
      );
    });

    test(
        'rejecting an oversized body does not surface an unhandled error '
        'when onCancel throws', () async {
      final oversized = Uint8List((70 * 1024));
      final client = MockClient.streaming((request, bodyStream) async {
        late final StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          onListen: () {
            controller.add(oversized);
          },
          onCancel: () => throw StateError('onCancel boom'),
        );
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.responseTooLarge)),
      );
    });

    test(
        'throws RegistrarException(network) for a non-ClientException '
        'Exception, dropping the inner message', () async {
      final client = MockClient((_) async {
        throw const FormatException('super-secret-inner-detail');
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having((e) => e.reason, 'reason', RegistrarFailure.network)
              .having((e) => e.toString().contains('super-secret-inner-detail'),
                  'leaks the inner message', isFalse),
        ),
      );
    });
  });

  group('generateAtSignDeleteToken', () {
    test('returns token and atSigns when all are valid', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'message': 'Delete token created successfully.',
        'data': {
          'token': 'the-token',
          'atSigns': ['@one', '@two'],
          'skippedatSigns': [],
        },
      }));
      final result = await service.generateAtSignDeleteToken(['@one', '@two']);
      expect(result.token, equals('the-token'));
      expect(result.atSigns, equals(['@one', '@two']));
      expect(result.skippedAtSigns, equals([]));
    });

    test('returns skippedAtSigns alongside token when some are invalid',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {
          'token': 'the-token',
          'atSigns': ['@one'],
          'skippedatSigns': ['@bogus'],
        },
      }));
      final result =
          await service.generateAtSignDeleteToken(['@one', '@bogus']);
      expect(result.skippedAtSigns, equals(['@bogus']));
    });

    test('throws RegistrarException(unavailable) when all atSigns are invalid',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message':
            'One or more Atsigns mentioned are not associated with this account.',
        'data': {
          'skippedatSigns': ['@bogus'],
        },
      }));
      expect(
        () => service.generateAtSignDeleteToken(['@bogus']),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.unavailable)
            .having(
                (e) => e.toString().contains(
                    'One or more Atsigns mentioned are not associated with this account.'),
                'leaks the server message',
                isFalse)),
      );
    });

    test('throws RegistrarException(unexpectedStatus) on non-200 status',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.unexpectedStatus)
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test(
        '403 raises RegistrarException(authentication) naming /manage-atsigns/',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Forbidden'}, status: 403));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(
          isA<RegistrarException>()
              .having(
                  (e) => e.reason, 'reason', RegistrarFailure.authentication)
              .having((e) => e.endpoint, 'endpoint', '/manage-atsigns/')
              .having((e) => e.toString().contains('/manage-atsigns/'),
                  'names the endpoint', isTrue)
              .having((e) => e.toString().contains(_apiKey), 'leaks the key',
                  isFalse),
        ),
      );
    });

    test(
        '401 raises RegistrarException(authentication) naming /manage-atsigns/',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Unauthorized'}, status: 401));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(
          isA<RegistrarException>()
              .having(
                  (e) => e.reason, 'reason', RegistrarFailure.authentication)
              .having((e) => e.endpoint, 'endpoint', '/manage-atsigns/')
              .having((e) => e.toString().contains('/manage-atsigns/'),
                  'names the endpoint', isTrue)
              .having((e) => e.toString().contains(_apiKey), 'leaks the key',
                  isFalse),
        ),
      );
    });

    test('throws RegistrarException(malformedResponse) when data is not a Map',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': ['not', 'a', 'map'],
      }));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when token is not a String',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'token': 12345, 'atSigns': [], 'skippedatSigns': []},
      }));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when atSigns is not a List',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'token': 'the-token', 'atSigns': 'not-a-list'},
      }));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('throws RegistrarException(malformedResponse) when status is missing',
        () async {
      final service = _makeAdminService(_mockResponse({
        'data': {'token': 'the-token', 'atSigns': [], 'skippedatSigns': []},
      }));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when status is '
        'unrecognized', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'weird',
        'data': {'token': 'the-token', 'atSigns': [], 'skippedatSigns': []},
      }));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when status is '
        '"success" but data is null', () async {
      final service =
          _makeAdminService(_mockResponse({'status': 'success', 'data': null}));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('requests the manage-atsigns endpoint over https for a delete token',
        () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'token': 'the-token',
                'atSigns': [],
                'skippedatSigns': []
              },
            }),
            200);
      });
      final service = _makeAdminService(client);
      await service.generateAtSignDeleteToken(['@one']);

      expect(captured.url.scheme, equals('https'));
      expect(captured.url.host, equals(_registrarUrl));
      expect(captured.url.path, equals('/api/app/v4/manage-atsigns/'));
    });
  });

  group('deleteAtSigns', () {
    test('returns deleted and failed lists on success', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'message': 'Atsigns deleted successfully.',
        'data': {
          'deleted': [
            {'atSign': '@one'},
          ],
          'failed': [],
        },
      }));
      final result = await service.deleteAtSigns(
        token: 'the-token',
        atSigns: ['@one'],
      );
      expect(
          result.deleted,
          equals([
            {'atSign': '@one'}
          ]));
      expect(result.failed, equals([]));
    });

    test('throws RegistrarException(unavailable) when status is not "success"',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message':
            'One or more Atsigns mentioned are not associated with this account.',
        'data': {
          'skippedatSigns': ['@one'],
        },
      }));
      expect(
        () => service.deleteAtSigns(token: 'bad-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.unavailable)),
      );
    });

    test('throws RegistrarException(unexpectedStatus) on non-200 status',
        () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.unexpectedStatus)),
      );
    });

    test('throws RegistrarException(malformedResponse) when status is missing',
        () async {
      final service = _makeAdminService(_mockResponse({
        'data': {'deleted': [], 'failed': []},
      }));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when status is '
        'unrecognized', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'weird',
        'data': {'deleted': [], 'failed': []},
      }));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when status is '
        '"success" but data is null', () async {
      final service =
          _makeAdminService(_mockResponse({'status': 'success', 'data': null}));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(network) for a delete call when the '
        'connection fails', () async {
      final client = MockClient((_) async {
        throw http.ClientException('Connection refused');
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(
          isA<RegistrarException>()
              .having((e) => e.reason, 'reason', RegistrarFailure.network)
              .having((e) => e.endpoint, 'endpoint', '/manage-atsigns/')
              .having((e) => e.toString().contains(_apiKey), 'leaks the key',
                  isFalse),
        ),
      );
    });

    test('requests the manage-atsigns endpoint over https', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'deleted': [],
                'failed': [],
              },
            }),
            200);
      });
      final service = _makeAdminService(client);
      await service.deleteAtSigns(token: 'the-token', atSigns: ['@one']);

      expect(captured.url.scheme, equals('https'));
      expect(captured.url.host, equals(_registrarUrl));
      expect(captured.url.path, equals('/api/app/v4/manage-atsigns/'));
    });

    test('throws RegistrarException(malformedResponse) when data is not a Map',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': 'not-a-map',
      }));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when deleted is not a List',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'deleted': 'not-a-list', 'failed': []},
      }));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when failed is not a List',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'deleted': [], 'failed': 'not-a-list'},
      }));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });
  });
}
