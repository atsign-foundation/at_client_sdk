import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

class FakeAtServerTransport implements AtTransport {
  late final StreamController<List<int>> _inbound = StreamController<List<int>>();

  @override
  final String description;

  FakeAtServerTransport({this.description = '127.0.0.66:6464'});

  final List<String> written = <String>[];

  int flushCount = 0;
  bool destroyed = false;

  Future<void> serverSends(List<int> data) async {
    _inbound.add(data);
    await settle();
  }

  Future<void> serverCloses() async {
    await _inbound.close();
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration.zero);
    }
  }

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) {
    written.add(utf8.decode(bytes));
  }

  @override
  Future<void> flush() async => flushCount++;

  @override
  void destroy() {
    destroyed = true;
    if (!_inbound.isClosed) _inbound.close();
  }
}

class FakeAtServerTransportFactory implements AtTransportFactory {
  final List<FakeAtServerTransport> created = <FakeAtServerTransport>[];

  @override
  Future<AtTransport> connect(String host, String port, {Duration? timeout}) async {
    final transport = FakeAtServerTransport(description: '$host:$port');
    created.add(transport);
    return transport;
  }
}

class MockSecondaryAddressFinder implements SecondaryAddressFinder {
  SecondaryAddress? address;

  @override
  Future<SecondaryAddress> findSecondary(String atSign, {Duration? timeout}) async {
    return address ?? SecondaryAddress('127.0.0.1', 6464);
  }
}

class MockEncryptionService implements EncryptionService {
  @override
  Future<String> getSharedKeyForDecryption(String atSign) async {
    return 'my_shared_key';
  }

  @override
  List<int> decryptStream(List<int> encryptedData, String sharedKey, {String? ivBase64}) {
    return encryptedData;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StreamNotificationHandler', () {
    late StreamNotificationHandler handler;
    late FakeAtServerTransportFactory transportFactory;
    late AtClientPreference preference;
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('stream_test');
      preference = AtClientPreference()..downloadPath = tempDir.path;
      transportFactory = FakeAtServerTransportFactory();

      AtClientManager.getInstance().secondaryAddressFinder = MockSecondaryAddressFinder();

      handler = StreamNotificationHandler()
        ..preference = preference
        ..transportFactory = transportFactory
        ..encryptionService = MockEncryptionService();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('streamAck routes through injected AtTransportFactory', () async {
      var notification = AtStreamNotification()
        ..streamId = 'test-stream-123'
        ..fileName = 'test.txt'
        ..senderAtSign = '@alice'
        ..fileLength = 5;

      var completionFired = false;

      void completionCallback(String id) {
        expect(id, 'test-stream-123');
        completionFired = true;
      }

      void receiveCallback(int bytes) {}

      var ackFuture = handler.streamAck(notification, completionCallback, receiveCallback);

      // wait for connect and 'stream:receive' write
      await Future.delayed(Duration(milliseconds: 50));

      expect(transportFactory.created.length, 1);
      var transport = transportFactory.created.first;
      expect(transport.description, '127.0.0.1:6464');

      expect(transport.written.first, 'stream:receive test-stream-123\n');
      expect(transport.flushCount, greaterThanOrEqualTo(1));

      // simulate server sending first @ prompt
      await transport.serverSends([64]); // '@'

      // simulate server sending file data with a leading @ (from the data stream)
      await transport.serverSends([64, 104, 101, 108, 108, 111]);

      await ackFuture;

      expect(transport.written.last, 'stream:done test-stream-123\n');
      expect(transport.flushCount, greaterThanOrEqualTo(2));
      
      await transport.serverCloses();

      expect(transport.destroyed, true);
      expect(completionFired, true);

      var downloadedFile = File('${tempDir.path}${Platform.pathSeparator}test.txt');
      expect(downloadedFile.existsSync(), true);
      expect(downloadedFile.readAsStringSync(), 'hello');
    });
  });
}
