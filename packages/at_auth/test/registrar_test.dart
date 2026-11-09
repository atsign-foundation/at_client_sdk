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
    test('returns the atsign and the stripped cramkey on success', () async {
      final service = _makeAdminService(_mockResponse(
          {'status': 'success', 'cramkey': 'prefix:ADMINCRAMKEY'}));
      final result = await service.registerAtsign(atsign: '@alice'.toAtsign());
      expect(result.atsign, equals('@alice'.toAtsign()));
      expect(result.cramKey, equals('ADMINCRAMKEY'));
    });

    test('sends the super key and the atsign with its leading "@"', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({'status': 'success', 'cramkey': 'prefix:KEY'}), 200);
      });
      final service = _makeAdminService(client);
      await service.registerAtsign(atsign: '@alice'.toAtsign());

      expect(captured.url.path, equals('/api/app/v4/register-atsign/'));
      expect(captured.headers['Authorization'], equals(_apiKey));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['atSign'], equals('@alice'));
      expect(body['operation'], equals('register'));
    });

    test(
        'throws RegistrarException when register succeeds but the cramkey is missing',
        () async {
      final service = _makeAdminService(_mockResponse({'status': 'success'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
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
        'throws RegistrarException when the cramkey has no value after its prefix',
        () async {
      final service = _makeAdminService(
          _mockResponse({'status': 'success', 'cramkey': 'prefix:'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
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
        throwsA(isA<RegistrarException>()),
      );
    });

    test(
        'RegistrarException text carries neither the cramkey nor the server message',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message': 'super-secret-server-detail',
        'cramkey': 'prefix:SHOULDNOTLEAK',
      }));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          predicate(
            (e) =>
                e is RegistrarException &&
                !e.toString().contains('SHOULDNOTLEAK') &&
                !e.toString().contains('super-secret-server-detail'),
          ),
        ),
      );
    });

    test('throws when status is not "success"', () async {
      final service = _makeAdminService(_mockResponse(
          {'status': 'error', 'message': 'atSign not available'}));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
      );
    });

    test('throws on non-200 status', () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()),
      );
    });

    test('401 exception text does not contain the super key', () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Unauthorized'}, status: 401));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('super-API-key') &&
                e.toString().contains('/register-atsign/') &&
                e.toString().contains('401') &&
                !e.toString().contains(_apiKey),
          ),
        ),
      );
    });

    test('403 exception text does not contain the super key', () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Forbidden'}, status: 403));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('super-API-key') &&
                e.toString().contains('/register-atsign/') &&
                e.toString().contains('403') &&
                !e.toString().contains(_apiKey),
          ),
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

    test('throws when all atSigns are invalid', () async {
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
        throwsException,
      );
    });

    test('throws on non-200 status', () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsException,
      );
    });

    test('throws helpful exception on 403 auth failure', () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Forbidden'}, status: 403));
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('super-API-key') &&
                e.toString().contains('403'),
          ),
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

    test('throws when status is not "success"', () async {
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
        throwsException,
      );
    });

    test('throws on non-200 status', () async {
      final service = _makeAdminService(
          _mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsException,
      );
    });
  });
}
