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

/// An [http.Client] that forwards to [_inner], counts its [close] calls and,
/// like a real client, refuses to send once closed.
class _CloseCountingClient extends http.BaseClient {
  final http.Client _inner;
  int closeCount = 0;

  _CloseCountingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closeCount > 0) throw http.ClientException('closed', request.url);
    return _inner.send(request);
  }

  @override
  void close() => closeCount++;
}

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

    test(
        'throws AtException, not ArgumentError, when superApiKey is '
        'whitespace-only', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: _registrarUrl,
          superApiKey: '   ',
          httpClient: _mockResponse({}),
        ),
        throwsA(isA<AtException>()),
      );
    });

    for (final entry in {
      'a tab': '\t',
      'a newline': '\n',
      'CRLF': '\r\n',
      'a no-break space': '\u00A0',
    }.entries) {
      test(
          'given a superApiKey of only whitespace holding ${entry.key}, when '
          'the service is constructed, then it throws AtException, not '
          'ArgumentError', () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: _registrarUrl,
            superApiKey: entry.value,
            httpClient: _mockResponse({}),
          ),
          throwsA(isA<AtException>()),
        );
      });
    }

    for (final noHost in ['', ':', ':443']) {
      test(
          'given registrarUrl "$noHost", which names no host, when the '
          'service is constructed, then it throws ArgumentError naming '
          'registrarUrl', () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: noHost,
            superApiKey: _apiKey,
            httpClient: _mockResponse({}),
          ),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
          ),
        );
      });
    }

    for (final entry in {
      'a space': ' ',
      'two spaces': '  ',
      'a tab': '\t',
      'a no-break space': '\u00A0',
      'an escaped space': '%20',
      'a dot': '.',
      'two dots': '..',
      'dots and spaces': ' . ',
      'a space and a port': ' :8443',
    }.entries) {
      test(
          'given a registrarUrl whose host is only ${entry.key}, when the '
          'service is constructed, then it throws ArgumentError naming '
          'registrarUrl', () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: entry.value,
            superApiKey: _apiKey,
            httpClient: _mockResponse({}),
          ),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
          ),
        );
      });
    }

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

    test('accepts a bare host with the default https port spelled out', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl:443',
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

    test('accepts registrarUrl trailing whitespace, as Uri.https does', () {
      expect(
        () => RegistrarAdminService(
          registrarUrl: '$_registrarUrl ',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        ),
        returnsNormally,
      );
    });

    final hostShapeLeakCases = <String, String>{
      'scheme': 'https://leaksecret.$_registrarUrl',
      'path': '$_registrarUrl/leaksecret',
      'userInfo': 'user:leaksecret@host',
      'fragment': '$_registrarUrl#leaksecret',
      'query': '$_registrarUrl?q=leaksecret',
      'multiColon': '$_registrarUrl:443:leaksecret',
      'schemeAndMultiColon': 'https://leaksecret.$_registrarUrl:443',
    };
    for (final entry in hostShapeLeakCases.entries) {
      test(
          'ArgumentError for a ${entry.key} registrarUrl never echoes the '
          'offending value', () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: entry.value,
            superApiKey: _apiKey,
            httpClient: _mockResponse({}),
          ),
          throwsA(
            predicate(
              (e) =>
                  e is ArgumentError &&
                  e.name == 'registrarUrl' &&
                  !e.toString().contains('leaksecret'),
            ),
          ),
        );
      });
    }

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

    test(
        'throws ArgumentError naming registrarUrl for an oversized port, '
        'never echoing the digits and never a FormatException', () {
      const oversizedPort = '99999999999999999999';
      try {
        RegistrarAdminService(
          registrarUrl: '$_registrarUrl:$oversizedPort',
          superApiKey: _apiKey,
          httpClient: _mockResponse({}),
        );
        fail('expected an ArgumentError');
      } catch (e) {
        expect(e, isNot(isA<FormatException>()));
        expect(
          e,
          isA<ArgumentError>().having((e) => e.name, 'name', 'registrarUrl'),
        );
        expect(e.toString().contains(oversizedPort), isFalse);
      }
    });

    for (final entry in {
      'tab': 'k\tk',
      'newline': 'k\n',
      'crlfHeaderInjection': 'k\r\nX-Injected: 1',
      'controlBelowSpace': 'k\x1F',
      'del': 'k\x7F',
      'highByte': 'k\x80',
      'nonAsciiLetter': 'kéy',
      'emoji': 'k😀',
    }.entries) {
      test(
          'throws ArgumentError naming superApiKey for a ${entry.key} key, '
          'never echoing it, and sends no request', () async {
        var requestSent = false;
        final client = MockClient((_) async {
          requestSent = true;
          return http.Response(jsonEncode({}), 200);
        });
        try {
          RegistrarAdminService(
            registrarUrl: _registrarUrl,
            superApiKey: entry.value,
            httpClient: client,
          );
          fail('expected an ArgumentError');
        } catch (e) {
          expect(
            e,
            isA<ArgumentError>().having((e) => e.name, 'name', 'superApiKey'),
          );
          expect(e.toString().contains(entry.value), isFalse);
        }
        expect(requestSent, isFalse,
            reason: 'constructor validation must reject before any request '
                'is sent');
      });
    }

    for (final acceptedKey in ['!', '~', 'k k', ' k']) {
      test('accepts the superApiKey "$acceptedKey"', () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: _registrarUrl,
            superApiKey: acceptedKey,
            httpClient: _mockResponse({}),
          ),
          returnsNormally,
        );
      });
    }

    for (final timeout in [
      Duration.zero,
      const Duration(microseconds: -1),
      const Duration(seconds: -30),
    ]) {
      test(
          'given a requestTimeout of $timeout, when the service is '
          'constructed, then it throws ArgumentError naming requestTimeout',
          () {
        expect(
          () => RegistrarAdminService(
            registrarUrl: _registrarUrl,
            superApiKey: _apiKey,
            requestTimeout: timeout,
            httpClient: _mockResponse({}),
          ),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'requestTimeout'),
          ),
        );
      });
    }

    final acceptedRegistrarUrls = <String, ({String host, int port})>{
      'registrar_api:8443': (host: 'registrar_api', port: 8443),
      '[::1]:8443': (host: '::1', port: 8443),
      'bücher.example': (host: 'b%C3%BCcher.example', port: 443),
      '$_registrarUrl:1': (host: _registrarUrl, port: 1),
      '$_registrarUrl:65535': (host: _registrarUrl, port: 65535),
      '$_registrarUrl:00443': (host: _registrarUrl, port: 443),
      '$_registrarUrl:': (host: _registrarUrl, port: 443),
      '$_registrarUrl:000443': (host: _registrarUrl, port: 443),
      '$_registrarUrl:+443': (host: _registrarUrl, port: 443),
      '$_registrarUrl: 443': (host: _registrarUrl, port: 443),
      '$_registrarUrl:0x1BB': (host: _registrarUrl, port: 443),
      '%FF': (host: '%FF', port: 443),
    };
    for (final entry in acceptedRegistrarUrls.entries) {
      test(
          'accepts registrarUrl "${entry.key}" and sends the request to '
          'host "${entry.value.host}" port ${entry.value.port}', () async {
        late http.Request captured;
        final client = MockClient((req) async {
          captured = req;
          return http.Response(
              jsonEncode({'status': 'success', 'cramkey': '@alice:K'}), 200);
        });
        final service = RegistrarAdminService(
          registrarUrl: entry.key,
          superApiKey: _apiKey,
          httpClient: client,
        );
        await service.registerAtsign(atsign: '@alice'.toAtsign());
        expect(captured.url.host, equals(entry.value.host));
        expect(captured.url.port, equals(entry.value.port));
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
    test('RegistrarException is an AtException', () async {
      final service = _makeAdminService(_mockResponse({'status': 'success'}));
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<AtException>()),
      );
    });

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

    final cramkeyLeakCases = <String, String>{
      'no "@" prefix': 'SECRETMARKER:KEY',
      'no ":" separator': '@SECRETMARKER',
      'empty key after ":"': '@SECRETMARKER:',
      'invalid Atsign': '@invalid!SECRETMARKER:KEY',
    };
    for (final entry in cramkeyLeakCases.entries) {
      test('cramkey error for ${entry.key} never echoes the raw cramkey',
          () async {
        final service = _makeAdminService(
            _mockResponse({'status': 'success', 'cramkey': entry.value}));
        await expectLater(
          service.registerAtsign(atsign: '@alice'.toAtsign()),
          throwsA(
            isA<RegistrarException>()
                .having((e) => e.reason, 'reason',
                    RegistrarFailure.malformedResponse)
                .having((e) => e.toString().contains('SECRETMARKER'),
                    'leaks the raw cramkey', isFalse),
          ),
        );
      });
    }

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
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)
            .having((e) => e.toString().contains('502 Bad Gateway'),
                'leaks the response body', isFalse)),
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

    test('throws RegistrarException(malformedResponse) when status is missing',
        () async {
      final service = _makeAdminService(_mockResponse({
        'cramkey': '@alice:KEY',
      }));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when status is '
        'unrecognized', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'weird',
        'cramkey': '@alice:KEY',
      }));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
      );
    });

    test('throws RegistrarException(registrarError) when status is "error"',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'error',
        'message': 'super-secret-server-detail',
      }));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(
          isA<RegistrarException>()
              .having(
                  (e) => e.reason, 'reason', RegistrarFailure.registrarError)
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
            .having((e) => e.endpoint, 'endpoint', '/register-atsign/')
            .having((e) => e.toString().contains('@alice:k'),
                'leaks the cramkey', isFalse)),
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

    test(
        'requestTimeout bounds the send and the body read together, not '
        'as separate budgets', () async {
      const timeout = Duration(milliseconds: 100);
      final client = MockClient.streaming((request, bodyStream) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final controller = StreamController<List<int>>();
        Timer(const Duration(milliseconds: 60), () {
          controller.add(utf8.encode(
              jsonEncode({'status': 'success', 'cramkey': '@alice:K'})));
          controller.close();
        });
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: timeout,
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.timeout)),
        reason: 'each half taking 0.6x the timeout must still exceed it when '
            'the budget is shared, not reset between send and read',
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
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        unawaited(() async {
          for (var i = 0; i < 20 && !cancelled; i++) {
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
      expect(cancelled, isTrue,
          reason: 'the stream must be cancelled once the cap is crossed, '
              'not drained to completion');
    });

    test('accepts a response body of exactly the 64 KiB cap', () async {
      final unpadded = jsonEncode({'status': 'success', 'cramkey': '@alice:K'});
      final body = unpadded.padRight(64 * 1024, ' ');
      expect(utf8.encode(body).length, equals(64 * 1024));
      final client = MockClient((_) async => http.Response(body, 200));
      final result = await _makeAdminService(client)
          .registerAtsign(atsign: '@alice'.toAtsign());
      expect(result.cramKey, equals('K'));
    });

    test('the deprecated superApiKey getter still returns the key', () {
      final service = _makeAdminService(_mockResponse({}));
      // ignore: deprecated_member_use_from_same_package
      expect(service.superApiKey, equals(_apiKey));
    });

    for (final status in [200, 401]) {
      test(
          'given no httpClient, when two calls end with status $status, then '
          'each closes the client it was given', () async {
        final created = <_CloseCountingClient>[];
        await http.runWithClient(() async {
          final service = RegistrarAdminService(
              registrarUrl: _registrarUrl, superApiKey: _apiKey);
          for (var call = 0; call < 2; call++) {
            await service
                .registerAtsign(atsign: '@alice'.toAtsign())
                .then((_) {}, onError: (Object _) {});
          }
        }, () {
          final client = _CloseCountingClient(_mockResponse(
              {'status': 'success', 'cramkey': '@alice:K'},
              status: status));
          created.add(client);
          return client;
        });
        expect(created.map((c) => c.closeCount), equals([1, 1]),
            reason: 'each call must close the client it used, once');
      });
    }

    test('given an httpClient, when two calls end, then it is never closed',
        () async {
      final client = _CloseCountingClient(
          _mockResponse({'status': 'success', 'cramkey': '@alice:K'}));
      final service = RegistrarAdminService(
          registrarUrl: _registrarUrl,
          superApiKey: _apiKey,
          httpClient: client);
      for (var call = 0; call < 2; call++) {
        await service.registerAtsign(atsign: '@alice'.toAtsign());
        expect(client.closeCount, equals(0),
            reason: 'a client the caller passed in is the caller\'s to close');
      }
    });

    test(
        'given no httpClient and a service built inside runWithClient, when '
        'it is called inside another, then it uses the client of the zone it '
        'was built in', () async {
      var buildZoneSends = 0;
      var callZoneSends = 0;
      final service = http.runWithClient(
        () => RegistrarAdminService(
            registrarUrl: _registrarUrl, superApiKey: _apiKey),
        () => MockClient((_) async {
          buildZoneSends++;
          return http.Response(
              jsonEncode({'status': 'success', 'cramkey': '@alice:K'}), 200);
        }),
      );
      await http.runWithClient(
        () => service
            .registerAtsign(atsign: '@alice'.toAtsign())
            .then((_) {}, onError: (Object _) {}),
        () => MockClient((_) async {
          callZoneSends++;
          return http.Response('', 500);
        }),
      );
      expect((buildZoneSends, callZoneSends), equals((1, 0)),
          reason: 'the client comes from the zone the service was built in');
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

    test('does not read a late response once the abort trigger already fired',
        () async {
      final spyChunk = _SpyBytes(List<int>.filled(10, 0));
      final client = MockClient.streaming((request, bodyStream) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final controller = StreamController<List<int>>();
        controller.add(spyChunk);
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
      const lateResponseGuardDelay = Duration(milliseconds: 100);
      await Future<void>.delayed(lateResponseGuardDelay);
      expect(spyChunk.wasRead, isFalse,
          reason: 'a response that arrives after the timeout fired must not '
              'have its body read');
    });

    test('surfaces an error raised by the body stream after headers arrive',
        () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>();
        controller.add(utf8.encode('{"stat'));
        controller.addError(Exception('stream broke'));
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>()
            .having((e) => e.reason, 'reason', RegistrarFailure.network)),
      );
    });

    test('sets followRedirects to false on the request', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({'status': 'success', 'cramkey': '@alice:KEY'}), 200);
      });
      final service = _makeAdminService(client);
      await service.registerAtsign(atsign: '@alice'.toAtsign());
      expect(captured.followRedirects, isFalse);
    });

    test('throws RegistrarException(unexpectedStatus) on a 3xx status',
        () async {
      final service = _makeAdminService(_mockResponse({}, status: 302));
      expect(
        () => service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.unexpectedStatus)),
      );
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

    test(
        'sends a POST over https with Content-Type, Authorization and the '
        'exact register body', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({'status': 'success', 'cramkey': '@alice:KEY'}), 200);
      });
      final service = _makeAdminService(client);
      await service.registerAtsign(atsign: '@alice'.toAtsign());

      expect(captured.method, equals('POST'));
      expect(captured.url.scheme, equals('https'));
      expect(captured.url.host, equals(_registrarUrl));
      expect(captured.url.path, equals('/api/app/v4/register-atsign/'));
      expect(captured.headers['Content-Type'], equals('application/json'));
      expect(captured.headers['Authorization'], equals(_apiKey));
      expect(
        jsonDecode(captured.body),
        equals({
          'operation': 'register',
          'atSign': '@alice',
          'startatServer': 'true',
        }),
      );
    });

    test('accepts a response body of exactly 65536 bytes', () async {
      final unpadded = jsonEncode({'status': 'success', 'cramkey': '@alice:K'});
      final body = unpadded.padRight(65536, ' ');
      expect(utf8.encode(body).length, equals(65536));
      final client = MockClient((_) async => http.Response(body, 200));
      final result = await _makeAdminService(client)
          .registerAtsign(atsign: '@alice'.toAtsign());
      expect(result.cramKey, equals('K'));
    });

    test('rejects a response body of exactly 65537 bytes', () async {
      final oversized = 'x' * 65537;
      final client = MockClient((_) async => http.Response(oversized, 200));
      final service = _makeAdminService(client);
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.responseTooLarge)),
      );
    });

    test(
        'a hung onCancel still yields timeout, within requestTimeout plus '
        'a margin', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>(
          onCancel: () => Completer<void>().future,
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
      ).timeout(const Duration(milliseconds: 500));
    });

    test(
        'a hung onCancel still yields responseTooLarge, within '
        'requestTimeout plus a margin', () async {
      final oversized = Uint8List(70 * 1024);
      final client = MockClient.streaming((request, bodyStream) async {
        late final StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          onListen: () => controller.add(oversized),
          onCancel: () => Completer<void>().future,
        );
        return http.StreamedResponse(controller.stream, 200);
      });
      final service = RegistrarAdminService(
        registrarUrl: _registrarUrl,
        superApiKey: _apiKey,
        requestTimeout: const Duration(seconds: 5),
        httpClient: client,
      );
      await expectLater(
        service.registerAtsign(atsign: '@alice'.toAtsign()),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.responseTooLarge)),
      ).timeout(const Duration(milliseconds: 500));
    });

    for (final status in [401, 403]) {
      test(
          'given a $status whose body cancel never completes, when '
          'registerAtsign runs, then it throws authentication with the '
          'status, not timeout', () async {
        final client = MockClient.streaming((request, bodyStream) async {
          final controller = StreamController<List<int>>(
            onCancel: () => Completer<void>().future,
          );
          return http.StreamedResponse(controller.stream, status);
        });
        final service = RegistrarAdminService(
          registrarUrl: _registrarUrl,
          superApiKey: _apiKey,
          requestTimeout: const Duration(seconds: 1),
          httpClient: client,
        );
        await expectLater(
          service.registerAtsign(atsign: '@alice'.toAtsign()),
          throwsA(isA<RegistrarException>()
              .having(
                  (e) => e.reason, 'reason', RegistrarFailure.authentication)
              .having((e) => e.statusCode, 'statusCode', status)),
        );
      });
    }
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

    test(
        'throws RegistrarException(registrarError) when all atSigns are invalid',
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
            .having((e) => e.reason, 'reason', RegistrarFailure.registrarError)
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
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.toString().contains('Server Error'),
                'leaks the response body', isFalse)),
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

    test(
        'throws RegistrarException(malformedResponse) when the response '
        'body is not valid JSON', () async {
      final client = MockClient(
          (_) async => http.Response('<html>502 Bad Gateway</html>', 200));
      final service = _makeAdminService(client);
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)
            .having((e) => e.toString().contains('502 Bad Gateway'),
                'leaks the response body', isFalse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when the response '
        'body is not a JSON object', () async {
      final client = MockClient((_) async => http.Response('[1, 2, 3]', 200));
      final service = _makeAdminService(client);
      expect(
        () => service.generateAtSignDeleteToken(['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
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
        'throws RegistrarException(malformedResponse) when skippedatSigns '
        'is not a List', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {
          'token': 'the-token',
          'atSigns': [],
          'skippedatSigns': 'not-a-list',
        },
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

    for (final entry in {
      'an empty token': {
        'token': '',
        'atSigns': ['@one'],
        'skippedatSigns': [],
      },
      'an atSigns element that is not a String': {
        'token': 'the-token',
        'atSigns': ['@one', 1],
        'skippedatSigns': [],
      },
      'a skippedatSigns element that is not a String': {
        'token': 'the-token',
        'atSigns': ['@one'],
        'skippedatSigns': ['@two', null],
      },
    }.entries) {
      test(
          'given a success reply holding ${entry.key}, when a delete token is '
          'requested, then it throws malformedResponse', () async {
        final service = _makeAdminService(
            _mockResponse({'status': 'success', 'data': entry.value}));
        await expectLater(
          service.generateAtSignDeleteToken(['@one', '@two']),
          throwsA(isA<RegistrarException>().having(
              (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
        );
      });
    }

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
      await service.generateAtSignDeleteToken(['@one', '@two']);

      expect(captured.method, equals('POST'));
      expect(captured.url.scheme, equals('https'));
      expect(captured.url.host, equals(_registrarUrl));
      expect(captured.url.path, equals('/api/app/v4/manage-atsigns/'));
      expect(captured.headers['Content-Type'], equals('application/json'));
      expect(captured.headers['Authorization'], equals(_apiKey));
      expect(
        jsonDecode(captured.body),
        equals({
          'operation': 'deletetoken',
          'atSigns': ['@one', '@two'],
        }),
      );
    });

    test('returns an empty atSigns list when the response omits it', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'token': 'the-token', 'skippedatSigns': []},
      }));
      final result = await service.generateAtSignDeleteToken(['@one']);
      expect(result.atSigns, equals([]));
    });

    test('returns an empty skippedAtSigns list when the response omits it',
        () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'token': 'the-token', 'atSigns': []},
      }));
      final result = await service.generateAtSignDeleteToken(['@one']);
      expect(result.skippedAtSigns, equals([]));
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

    test(
        'throws RegistrarException(registrarError) when status is not "success"',
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
            .having((e) => e.reason, 'reason', RegistrarFailure.registrarError)
            .having((e) => e.statusCode, 'statusCode', 200)
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
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.unexpectedStatus)
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.toString().contains('Server Error'),
                'leaks the response body', isFalse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when the response '
        'body is not valid JSON', () async {
      final client = MockClient(
          (_) async => http.Response('<html>502 Bad Gateway</html>', 200));
      final service = _makeAdminService(client);
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>()
            .having(
                (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)
            .having((e) => e.toString().contains('502 Bad Gateway'),
                'leaks the response body', isFalse)),
      );
    });

    test(
        'throws RegistrarException(malformedResponse) when the response '
        'body is not a JSON object', () async {
      final client = MockClient((_) async => http.Response('[1, 2, 3]', 200));
      final service = _makeAdminService(client);
      expect(
        () => service.deleteAtSigns(token: 'the-token', atSigns: ['@one']),
        throwsA(isA<RegistrarException>().having(
            (e) => e.reason, 'reason', RegistrarFailure.malformedResponse)),
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
      await service
          .deleteAtSigns(token: 'the-token', atSigns: ['@one', '@two']);

      expect(captured.method, equals('POST'));
      expect(captured.url.scheme, equals('https'));
      expect(captured.url.host, equals(_registrarUrl));
      expect(captured.url.path, equals('/api/app/v4/manage-atsigns/'));
      expect(captured.headers['Content-Type'], equals('application/json'));
      expect(captured.headers['Authorization'], equals(_apiKey));
      expect(
        jsonDecode(captured.body),
        equals({
          'token': 'the-token',
          'atSigns': ['@one', '@two'],
          'operation': 'delete',
        }),
      );
    });

    test('returns an empty deleted list when the response omits it', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'failed': []},
      }));
      final result =
          await service.deleteAtSigns(token: 'the-token', atSigns: ['@one']);
      expect(result.deleted, equals([]));
    });

    test('returns an empty failed list when the response omits it', () async {
      final service = _makeAdminService(_mockResponse({
        'status': 'success',
        'data': {'deleted': []},
      }));
      final result =
          await service.deleteAtSigns(token: 'the-token', atSigns: ['@one']);
      expect(result.failed, equals([]));
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
