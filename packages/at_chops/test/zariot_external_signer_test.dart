import 'package:dart_periphery/dart_periphery.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

import '../example/zariot/external_signer.dart';

/// A modem that answers each AT command it is sent from [answers], keyed by
/// a fragment of the command, and is silent once that answer has been read.
class _ScriptedModem extends Fake implements Serial {
  final Map<String, String> answers;

  /// Reads past this many fail the test, so a reader that never gives up
  /// stops instead of hanging the suite.
  final int readLimit;
  int reads = 0;
  String? _pending;

  _ScriptedModem(this.answers, {this.readLimit = 20});

  @override
  int writeString(String command) {
    _pending = 'OK';
    for (final entry in answers.entries) {
      if (command.contains(entry.key)) {
        _pending = entry.value;
        break;
      }
    }
    return command.length;
  }

  @override
  SerialReadEvent read(int len, int timeout) {
    if (++reads > readLimit) {
      throw StateError('read $reads times without giving up');
    }
    final answer = _pending ?? '';
    _pending = null;
    return _Answer(answer);
  }
}

class _Answer extends Fake implements SerialReadEvent {
  final String text;
  _Answer(this.text);

  @override
  String toString() => text;
}

const _openChannel = '0070000000';
const _selectApp = 'A4040007';
const _opened = {
  _openChannel: '+CSIM: 6,"019000"\r\nOK\r\n',
  _selectApp: '+CSIM: 4,"9000"\r\nOK\r\n',
};

void main() {
  group('Given a zariot ExternalSigner', () {
    test('when the SIM computes the activation key, then it is returned', () {
      const prf = '00112233445566778899AABBCCDDEEFF';
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '48000032': '+CSIM: 4,"6110"\r\nOK\r\n',
              'C0000010': '+CSIM: 36,"${prf}9000"\r\nOK\r\n',
            }));

      expect(signer.computeActivationKey('KEY', 'SECRET', 'LABEL'), prf);
    });

    test('when the SIM refuses the PRF, then there is no activation key', () {
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '48000032': '+CSIM: 4,"6A80"\r\nOK\r\n',
              // A well-formed key, so only the refused PRF can make it fail.
              'C0000010':
                  '+CSIM: 36,"00112233445566778899AABBCCDDEEFF9000"\r\nOK\r\n',
            }));

      expect(signer.computeActivationKey('KEY', 'SECRET', 'LABEL'), isNull);
    });

    test(
        'when the SIM answers the PRF with a status other than 9000, '
        'then there is no activation key', () {
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '48000032': '+CSIM: 4,"6110"\r\nOK\r\n',
              'C0000010':
                  '+CSIM: 36,"00112233445566778899AABBCCDDEEFF6A82"\r\nOK\r\n',
            }));

      expect(signer.computeActivationKey('KEY', 'SECRET', 'LABEL'), isNull);
    });

    test('when the SIM answers the PRF with no key, then there is none', () {
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '48000032': '+CSIM: 4,"6110"\r\nOK\r\n',
              'C0000010': '+CSIM: 4,"9000"\r\nOK\r\n',
            }));

      expect(signer.computeActivationKey('KEY', 'SECRET', 'LABEL'), isNull);
    });

    test('when the modem answers a key pair with ERROR, then it gives up', () {
      final modem =
          _ScriptedModem({..._opened, 'B9000005': 'ERROR\r\n'}, readLimit: 6);
      final signer = ExternalSigner()
        ..initWithPort('000001', modem)
        ..readInterval = Duration.zero;

      expect(signer.generateKeyPair('0001'), isNull);
    });

    test('when the modem never finishes a signature, then it gives up', () {
      final modem = _ScriptedModem({..._opened, '2B800122': ''}, readLimit: 10);
      final signer = ExternalSigner()
        ..initWithPort('000001', modem)
        ..maxReads = 3
        ..readInterval = Duration.zero;

      expect(signer.sign('ab' * 32), isNull);
      // 3 reads of the update, and one each to open, select, init and close.
      expect(modem.reads, 7);
    });

    test('when the modem answers a signature with ERROR, then there is none',
        () {
      // The retrieve still answers with a signature, so only the failed
      // update can make sign() give up.
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '2B800122': 'ERROR\r\n',
              'C0000043': '+CSIM: 138,"330040${'AB' * 64}9000"\r\nOK\r\n',
            }))
        ..readInterval = Duration.zero;

      expect(signer.sign('ab' * 32), isNull);
    });

    test(
        'when the signature is computed but the answer carries no signature, '
        'then there is none', () {
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '2B800122': '+CSIM: 4,"6143"\r\nOK\r\n',
              'C0000043': '+CSIM: 12,"AABBCCDD9000"\r\nOK\r\n',
            }))
        ..readInterval = Duration.zero;

      expect(signer.sign('ab' * 32), isNull);
    });

    test('when the SIM signs, then the signature is returned', () {
      final signer = ExternalSigner()
        ..initWithPort(
            '000001',
            _ScriptedModem({
              ..._opened,
              '2B800122': '+CSIM: 4,"6143"\r\nOK\r\n',
              'C0000043': '+CSIM: 138,"330040${'AB' * 64}9000"\r\nOK\r\n',
            }))
        ..readInterval = Duration.zero;

      expect(signer.sign('ab' * 32), 'ab' * 64);
    });

    for (final (name, answer) in [
      ('the tag but no signature', '+CSIM: 10,"3300409000"'),
      ('another tag', '+CSIM: 138,"340040${'AB' * 64}9000"'),
      ('a status other than 9000', '+CSIM: 138,"330040${'AB' * 64}6110"'),
    ]) {
      test('when the signature answer carries $name, then there is none', () {
        final signer = ExternalSigner()
          ..initWithPort(
              '000001',
              _ScriptedModem({
                ..._opened,
                '2B800122': '+CSIM: 4,"6143"\r\nOK\r\n',
                'C0000043': '$answer\r\nOK\r\n',
              }))
          ..readInterval = Duration.zero;

        expect(signer.sign('ab' * 32), isNull);
      });
    }
  });
}
