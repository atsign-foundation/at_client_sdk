import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/cache/atdirectory_answer.dart';
import 'package:test/test.dart';

/// What the browser's atDirectory lookup asks for and accepts, which the
/// browser glue around it cannot be tested for in the VM.
void main() {
  group('atDirectoryUri', () {
    test('asks for the atSign in its canonical form', () {
      expect(
          atDirectoryUri('https', 'root.atsign.org', 443, 'Alice.Smith')
              .toString(),
          'https://root.atsign.org/@alicesmith');
    });

    test('an atSign that is not one is refused', () {
      expect(() => atDirectoryUri('https', 'root.atsign.org', 443, '@a b/c?d'),
          throwsA(isA<InvalidAtSignException>()));
    });
  });

  group('checkAtDirectoryStatus', () {
    test('a 2xx is an answer', () {
      for (final status in [200, 204, 299]) {
        expect(() => checkAtDirectoryStatus('root.atsign.org', '@alice', status),
            returnsNormally,
            reason: '$status');
      }
    });

    test('a 404 is SecondaryNotFoundException', () {
      expect(() => checkAtDirectoryStatus('root.atsign.org', '@alice', 404),
          throwsA(isA<SecondaryNotFoundException>()));
    });

    test('any other status is RootServerConnectivityException', () {
      for (final status in [199, 301, 403, 500, 503]) {
        expect(
            () => checkAtDirectoryStatus('root.atsign.org', '@alice', status),
            throwsA(isA<RootServerConnectivityException>().having(
                (e) => e.message, 'message', contains('answered $status'))),
            reason: '$status');
      }
    });
  });

  group('AtDirectoryAnswer', () {
    SecondaryAddress addressIn(String answer) =>
        (AtDirectoryAnswer('@alice')..add(utf8.encode(answer))).address;

    test('a host:port answer is the atServer address', () {
      final address = addressIn('a1b2.swarm0002.atsign.zone:6464\r\n');

      expect(address.host, 'a1b2.swarm0002.atsign.zone');
      expect(address.port, 6464);
    });

    test('an IPv4 address and a name with an underscore are hosts', () {
      expect(addressIn('127.0.0.1:6464').host, '127.0.0.1');
      expect(addressIn('vip_ve:25000').host, 'vip_ve');
    });

    test('the longest host name and label are accepted', () {
      final label = 'a' * 63;
      final host = [label, label, label, 'a' * 61].join('.');
      expect(host.length, 253, reason: 'the premise: the longest host name');

      expect(addressIn('$host:443').host, host);
    });

    test('an answer that could send a URL elsewhere is refused', () {
      for (final answer in [
        'a@b.example:443',
        'b.example/x:443',
        'b.example?x:443',
        'b.example#x:443',
        'b%2e.example:443',
        'b .example:443',
        '[::1]:443',
        'b.example:443:1',
        ':443',
        'b.example:',
        '${'a' * 64}.example:443',
        '${List.filled(4, 'a' * 63).join('.')}:443',
      ]) {
        expect(
            () => addressIn(answer),
            throwsA(isA<AtException>().having(
                (e) => e.message, 'message', contains('not host:port'))),
            reason: '"$answer" is not a host name and a port');
      }
    });

    test('a port outside 1 to 65535 is refused', () {
      for (final answer in ['b.example:0', 'b.example:65536']) {
        expect(() => addressIn(answer), throwsA(isA<AtException>()),
            reason: answer);
      }
      expect(addressIn('b.example:65535').port, 65535);
      expect(addressIn('b.example:1').port, 1);
    });

    test('an answer longer than 512 bytes is refused as it arrives', () {
      final answer = AtDirectoryAnswer('@alice')
        ..add(List.filled(500, 0x61))
        ..add(List.filled(12, 0x61));

      expect(
          () => answer.add([0x61]),
          throwsA(isA<AtException>().having((e) => e.message, 'message',
              contains('longer than 512 bytes'))),
          reason: 'the 513th byte, wherever its chunk starts');
    });
  });
}
