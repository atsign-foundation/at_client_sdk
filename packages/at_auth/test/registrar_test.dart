import 'dart:convert';

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

  group('getFreeAtSign', () {
    test('returns atsign string on success', () async {
      final service = _makeService(_mockResponse({
        'success': true,
        'data': {'atsign': '@bob'},
      }));
      expect(await service.getFreeAtSign(), equals('@bob'));
    });

    test('throws on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Server Error'}, status: 503));
      expect(() => service.getFreeAtSign(), throwsException);
    });

    test('throws when data is null', () async {
      final service =
          _makeService(_mockResponse({'success': true, 'data': null}));
      expect(() => service.getFreeAtSign(), throwsException);
    });
  });

  group('getFreeAtSignByCategory', () {
    test('returns atsign string on success', () async {
      final service = _makeService(_mockResponse({
        'Status': 'success',
        'data': {'atsign': '@zodiac'},
      }));
      expect(
        await service.getFreeAtSignByCategory(['zodiac']),
        equals('@zodiac'),
      );
    });

    test('throws on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Bad Request'}, status: 400));
      expect(
        () => service.getFreeAtSignByCategory(['invalid']),
        throwsException,
      );
    });

    test('throws when data is null', () async {
      final service =
          _makeService(_mockResponse({'Status': 'success', 'data': null}));
      expect(
        () => service.getFreeAtSignByCategory(['zodiac']),
        throwsException,
      );
    });
  });

  group('registerPerson', () {
    test('completes without throwing on success', () async {
      final service =
          _makeService(_mockResponse({'message': 'Sent Successfully'}));
      await expectLater(
        service.registerPerson(atSign: '@alice', email: 'alice@example.com'),
        completes,
      );
    });

    test('throws on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Not Found'}, status: 404));
      expect(
        () => service.registerPerson(
            atSign: '@alice', email: 'alice@example.com'),
        throwsException,
      );
    });

    test('throws when message is not "Sent Successfully"', () async {
      final service =
          _makeService(_mockResponse({'message': 'Email already registered'}));
      expect(
        () => service.registerPerson(
            atSign: '@alice', email: 'alice@example.com'),
        throwsException,
      );
    });
  });

  group('validatePerson', () {
    test('returns cramkey map for new user', () async {
      final service = _makeService(
          _mockResponse({'success': true, 'cramkey': 'prefix:NEWUSERCRAMKEY'}));
      final result = await service.validatePerson(
        atSign: '@alice',
        email: 'alice@example.com',
        otp: '4321',
      );
      expect(result['success'], isTrue);
      expect(result['cramkey'], equals('NEWUSERCRAMKEY'));
    });

    test('returns atsigns list for existing user', () async {
      final service = _makeService(_mockResponse({
        'data': {
          'atsigns': ['@existing1', '@existing2'],
          'newAtsign': '@new',
        }
      }));
      final result = await service.validatePerson(
        atSign: '@alice',
        email: 'alice@example.com',
        otp: '4321',
      );
      expect(result['atsigns'], equals(['@existing1', '@existing2']));
      expect(result['newAtsign'], equals('@new'));
    });

    test('throws on non-200 status', () async {
      final service =
          _makeService(_mockResponse({'message': 'Unauthorized'}, status: 401));
      expect(
        () => service.validatePerson(
          atSign: '@alice',
          email: 'alice@example.com',
          otp: '0000',
        ),
        throwsException,
      );
    });

    test('throws when neither success nor data is present', () async {
      final service = _makeService(_mockResponse({'message': 'Invalid OTP'}));
      expect(
        () => service.validatePerson(
          atSign: '@alice',
          email: 'alice@example.com',
          otp: '1111',
        ),
        throwsException,
      );
    });
  });
}
