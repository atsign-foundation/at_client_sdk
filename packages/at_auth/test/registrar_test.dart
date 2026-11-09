import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/registrar/registrar_admin_service.dart';
import 'package:at_auth/src/registrar/registrar_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _registrarUrl = 'my.registrar.test';
const _apiKey = 'test-api-key';

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

    test('the deprecated superApiKey getter still returns the key', () {
      final service = _makeAdminService(_mockResponse({}));
      // ignore: deprecated_member_use_from_same_package
      expect(service.superApiKey, equals(_apiKey));
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
  });
}
