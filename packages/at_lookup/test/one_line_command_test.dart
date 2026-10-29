import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'fake_at_server_transport.dart';

/// A connection writes a command only when it is one line.
void main() {
  group('Given a connection to an atServer', () {
    late FakeAtServerTransport transport;
    late OutboundConnection connection;

    setUp(() {
      transport = FakeAtServerTransport();
      connection = OutboundConnectionImpl(transport);
    });

    test(
        'when a command is one line, ending in its line feed or not, then it '
        'is written', () async {
      await connection.write('lookup:phone@bob\n');
      await connection.write('noop:0');

      expect(transport.written, ['lookup:phone@bob\n', 'noop:0']);
    });

    test(
        'when a command holds a line feed before its end, then it is refused, '
        'nothing is written and the connection stays usable', () async {
      for (final command in [
        'lookup:phone@bob\n\n',
        '\nlookup:phone@bob\n',
        'lookup:ph\none@bob\n',
      ]) {
        await expectLater(
            connection.write(command), throwsA(isA<IllegalArgumentException>()),
            reason: 'command ${command.length} characters long');
      }
      expect(transport.written, isEmpty);
      expect(connection.isInValid(), isFalse,
          reason: 'a refused command says nothing about the connection');

      await connection.write('lookup:phone@bob\n');
      expect(transport.written, ['lookup:phone@bob\n']);
    });

    test(
        'when a command holds a carriage return, then it is written as given, '
        'since only a line feed ends a command', () async {
      await connection.write('update:public:note@alice a\rb\n');

      expect(transport.written, ['update:public:note@alice a\rb\n']);
    });
  });
}
