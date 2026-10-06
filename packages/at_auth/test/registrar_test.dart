import 'dart:convert';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/registrar/registrar_admin_service.dart';
import 'package:at_auth/src/registrar/registrar_service.dart';
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

    test(
        'does not throw for a missing cramkey when startAtServer is false',
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
      final service = _makeService(
          _mockResponse({'status': 'error', 'message': 'atSign not available'}));
      expect(
        () => service.registerAtSign(
            atSign: 'taken', operation: RegisterOperation.register),
        throwsException,
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
      final result = await service.generateAtSignDeleteToken(['@one', '@bogus']);
      expect(result.skippedAtSigns, equals(['@bogus']));
    });

    test('throws when all atSigns are invalid', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message': 'One or more Atsigns mentioned are not associated with this account.',
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
      final service =
          _makeAdminService(_mockResponse({'message': 'Server Error'}, status: 500));
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
      expect(result.deleted, equals([{'atSign': '@one'}]));
      expect(result.failed, equals([]));
    });

    test('throws when status is not "success"', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message': 'One or more Atsigns mentioned are not associated with this account.',
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
      final service =
          _makeAdminService(_mockResponse({'message': 'Server Error'}, status: 500));
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsException,
      );
    });
  });
}
