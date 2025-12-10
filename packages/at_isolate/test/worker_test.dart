import 'package:test/test.dart';
import 'package:at_isolate/at_isolate.dart';
import 'package:at_isolate/src/isolated_atclient.dart';
import 'package:mocktail/mocktail.dart';
import 'dart:async';
import 'dart:isolate';
// ignore: implementation_imports
import 'package:at_client/src/response/response.dart';
import 'test_utils.dart';

void main() {
  late MockAtClient mockAtClient;
  late StreamController<Object?> inputController;
  late ReceivePort outputPort;
  late SendPort outputSendPort;
  late bool receiverClosed;

  setUp(() {
    registerFallbackValues();
    mockAtClient = MockAtClient();
    inputController = StreamController<Object?>.broadcast();
    outputPort = ReceivePort();
    outputSendPort = outputPort.sendPort;
    receiverClosed = false;
  });

  tearDown(() async {
    await inputController.close();
    outputPort.close();
  });

  group('Worker handle() - delete operations', () {
    test('delete request forwards correctly to AtClient', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey(key: 'test_key');
      final atKeyRecord = _atKeyToRecord(atKey);
      final request = (
        atKey: atKeyRecord,
        isDedicated: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'delete', params: request);

      when(() => mockAtClient.delete(
            any(),
            isDedicated: any(named: 'isDedicated'),
            deleteRequestOptions: any(named: 'deleteRequestOptions'),
          )).thenAnswer((_) async => true);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      inputController.add(workerMsg);

      // Assert
      await Future.delayed(Duration(milliseconds: 100));

      verify(() => mockAtClient.delete(
            any(that: predicate((AtKey key) => key.key == 'test_key')),
            isDedicated: false,
            deleteRequestOptions: any(named: 'deleteRequestOptions'),
          )).called(1);
    });

    test('delete response structure is correct', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey();
      final request = (
        atKey: _atKeyToRecord(atKey),
        isDedicated: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'delete', params: request);

      when(() => mockAtClient.delete(
            any(),
            isDedicated: any(named: 'isDedicated'),
            deleteRequestOptions: any(named: 'deleteRequestOptions'),
          )).thenAnswer((_) async => true);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response, isA<({bool success})>());
      expect(response.success, isTrue);
    });

    test('delete error propagates as string', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey();
      final request = (
        atKey: _atKeyToRecord(atKey),
        isDedicated: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'delete', params: request);

      when(() => mockAtClient.delete(
            any(),
            isDedicated: any(named: 'isDedicated'),
            deleteRequestOptions: any(named: 'deleteRequestOptions'),
          )).thenThrow(Exception('Key not found'));

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response, isA<String>());
      expect(response, contains('Exception: Key not found'));
    });
  });

  group('Worker handle() - get operations', () {
    test('get request forwards correctly to AtClient', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey(key: 'phone');
      final request = (
        atKey: _atKeyToRecord(atKey),
        isDedicated: false,
        bypassCache: true,
        useRemoteAtServer: false,
      );
      final workerMsg = (request: 'get', params: request);

      final atValue = AtValue()..value = 'test_value';
      when(() => mockAtClient.get(
            any(),
            isDedicated: any(named: 'isDedicated'),
            getRequestOptions: any(named: 'getRequestOptions'),
          )).thenAnswer((_) async => atValue);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      inputController.add(workerMsg);

      // Assert
      await Future.delayed(Duration(milliseconds: 100));

      verify(() => mockAtClient.get(
            any(that: predicate((AtKey key) => key.key == 'phone')),
            isDedicated: false,
            getRequestOptions: any(named: 'getRequestOptions'),
          )).called(1);
    });

    test('get response includes value and metadata', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey();
      final request = (
        atKey: _atKeyToRecord(atKey),
        isDedicated: false,
        bypassCache: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'get', params: request);

      final metadata = TestDataGenerator.createTestMetadata(
        ttl: 3600,
        isPublic: true,
      );
      final atValue = AtValue()
        ..value = 'test_value'
        ..metadata = metadata;

      when(() => mockAtClient.get(
            any(),
            isDedicated: any(named: 'isDedicated'),
            getRequestOptions: any(named: 'getRequestOptions'),
          )).thenAnswer((_) async => atValue);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response.value, equals('test_value'));
      expect(response.metadata, isNotNull);
      expect(response.metadata.ttl, equals(3600));
      expect(response.metadata.isPublic, isTrue);
    });

    test('get handles null metadata', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey();
      final request = (
        atKey: _atKeyToRecord(atKey),
        isDedicated: false,
        bypassCache: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'get', params: request);

      final atValue = AtValue()..value = 'test_value';

      when(() => mockAtClient.get(
            any(),
            isDedicated: any(named: 'isDedicated'),
            getRequestOptions: any(named: 'getRequestOptions'),
          )).thenAnswer((_) async => atValue);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response.value, equals('test_value'));
      expect(response.metadata, isNull);
    });
  });

  group('Worker handle() - put operations', () {
    test('put request forwards correctly to AtClient', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey(key: 'email');
      final request = (
        atKey: _atKeyToRecord(atKey),
        value: 'test@example.com',
        isDedicated: false,
        useRemoteAtServer: true,
        storeSharedKeyEncryptedMetadata: null,
        shouldEncrypt: null,
      );
      final workerMsg = (request: 'put', params: request);

      when(() => mockAtClient.put(
            any(),
            any(),
            isDedicated: any(named: 'isDedicated'),
            putRequestOptions: any(named: 'putRequestOptions'),
          )).thenAnswer((_) async => true);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      inputController.add(workerMsg);

      // Assert
      await Future.delayed(Duration(milliseconds: 100));

      verify(() => mockAtClient.put(
            any(that: predicate((AtKey key) => key.key == 'email')),
            'test@example.com',
            isDedicated: false,
            putRequestOptions: any(named: 'putRequestOptions'),
          )).called(1);
    });

    test('put response structure is correct', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey();
      final request = (
        atKey: _atKeyToRecord(atKey),
        value: 'test_value',
        isDedicated: false,
        useRemoteAtServer: true,
        storeSharedKeyEncryptedMetadata: null,
        shouldEncrypt: null,
      );
      final workerMsg = (request: 'put', params: request);

      when(() => mockAtClient.put(
            any(),
            any(),
            isDedicated: any(named: 'isDedicated'),
            putRequestOptions: any(named: 'putRequestOptions'),
          )).thenAnswer((_) async => true);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response, isA<({bool success})>());
      expect(response.success, isTrue);
    });
  });

  group('Worker handle() - putBinary operations', () {
    test('putBinary forwards binary data correctly', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey(key: 'file');
      final binaryData = [72, 101, 108, 108, 111]; // "Hello"
      final request = (
        atKey: _atKeyToRecord(atKey),
        value: binaryData,
        storeSharedKeyEncryptedMetadata: null,
        useRemoteAtServer: null,
        shouldEncrypt: null,
      );
      final workerMsg = (request: 'putBinary', params: request);

      final atResponse = AtResponse()
        ..response = 'data:12345'
        ..errorDescription = '';
      when(() => mockAtClient.putBinary(
            any(),
            any(),
            putRequestOptions: any(named: 'putRequestOptions'),
          )).thenAnswer((_) async => atResponse);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      inputController.add(workerMsg);

      // Assert
      await Future.delayed(Duration(milliseconds: 100));

      verify(() => mockAtClient.putBinary(
            any(that: predicate((AtKey key) => key.key == 'file')),
            binaryData,
            putRequestOptions: any(named: 'putRequestOptions'),
          )).called(1);
    });
  });

  group('Worker handle() - getAtKeys operations', () {
    test('getAtKeys forwards parameters correctly', () async {
      // Arrange
      final request = (
        regex: r'phone.*',
        sharedBy: '@alice',
        sharedWith: '@bob',
        showHiddenKeys: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'getAtKeys', params: request);

      final atKeys = [
        AtKey()
          ..key = 'phone'
          ..sharedBy = '@alice',
      ];

      when(() => mockAtClient.getAtKeys(
            regex: any(named: 'regex'),
            sharedBy: any(named: 'sharedBy'),
            sharedWith: any(named: 'sharedWith'),
            showHiddenKeys: any(named: 'showHiddenKeys'),
            useRemoteAtServer: any(named: 'useRemoteAtServer'),
          )).thenAnswer((_) async => atKeys);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      inputController.add(workerMsg);

      // Assert
      await Future.delayed(Duration(milliseconds: 100));

      verify(() => mockAtClient.getAtKeys(
            regex: r'phone.*',
            sharedBy: '@alice',
            sharedWith: '@bob',
            showHiddenKeys: false,
            useRemoteAtServer: true,
          )).called(1);
    });

    test('getAtKeys response contains string list', () async {
      // Arrange
      final request = (
        regex: r'.*',
        sharedBy: null,
        sharedWith: null,
        showHiddenKeys: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'getAtKeys', params: request);

      final atKeys = [
        AtKey()
          ..key = 'phone'
          ..sharedBy = '@alice'
          ..namespace = 'wavi',
        AtKey()
          ..key = 'email'
          ..sharedBy = '@alice'
          ..namespace = 'wavi',
      ];

      when(() => mockAtClient.getAtKeys(
            regex: any(named: 'regex'),
            sharedBy: any(named: 'sharedBy'),
            sharedWith: any(named: 'sharedWith'),
            showHiddenKeys: any(named: 'showHiddenKeys'),
            useRemoteAtServer: any(named: 'useRemoteAtServer'),
          )).thenAnswer((_) async => atKeys);

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response.atKeys, isA<List<String>>());
      expect(response.atKeys.length, equals(2));
    });
  });

  group('Worker handle() - close operation', () {
    test('close message triggers closeRecv callback', () async {
      // Arrange
      final workerMsg = (request: 'close', params: ());

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      inputController.add(workerMsg);

      // Assert
      await Future.delayed(Duration(milliseconds: 100));
      expect(receiverClosed, isTrue);
    });
  });

  group('Worker handle() - error cases', () {
    test('unknown message type returns error string', () async {
      // Arrange - send invalid message (not a _WorkerRequest)
      final invalidMsg = 'not a valid request';

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(invalidMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response, isA<String>());
      expect(response, contains('Unknown message type'));
    });

    test('AtClient exception is caught and sent as string', () async {
      // Arrange
      final atKey = TestDataGenerator.createTestAtKey();
      final request = (
        atKey: _atKeyToRecord(atKey),
        isDedicated: false,
        useRemoteAtServer: true,
      );
      final workerMsg = (request: 'delete', params: request);

      when(() => mockAtClient.delete(
            any(),
            isDedicated: any(named: 'isDedicated'),
            deleteRequestOptions: any(named: 'deleteRequestOptions'),
          )).thenThrow(AtClientException('AT0015', 'Key not found'));

      // Act
      AtClientWorker.handle(
        send: outputSendPort,
        atClient: mockAtClient,
        recv: inputController.stream,
        closeRecv: () => receiverClosed = true,
      );

      final responseCompleter = Completer<dynamic>();
      outputPort.listen((msg) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(msg);
        }
      });

      inputController.add(workerMsg);

      // Assert
      final response = await responseCompleter.future;
      expect(response, isA<String>());
      expect(response, contains('Key not found'));
    });
  });
}

// Helper function to convert AtKey to record
typedef _MetadataRecord = ({
  int? ttl,
  int? ttb,
  int? ttr,
  bool? ccd,
  DateTime? availableAt,
  DateTime? expiresAt,
  DateTime? refreshAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? dataSignature,
  String? sharedKeyStatus,
  bool isPublic,
  bool isHidden,
});

typedef _AtKeyRecord = ({
  String key,
  String? sharedWith,
  String? sharedBy,
  String? namespace,
  bool isLocal,
  bool isRef,
  _MetadataRecord metadata,
});

_AtKeyRecord _atKeyToRecord(AtKey atKey) {
  return (
    key: atKey.key,
    sharedWith: atKey.sharedWith,
    sharedBy: atKey.sharedBy,
    namespace: atKey.namespace,
    isLocal: atKey.isLocal,
    isRef: atKey.isRef,
    metadata: (
      ttl: atKey.metadata.ttl,
      ttb: atKey.metadata.ttb,
      ttr: atKey.metadata.ttr,
      ccd: atKey.metadata.ccd,
      availableAt: atKey.metadata.availableAt,
      expiresAt: atKey.metadata.expiresAt,
      refreshAt: atKey.metadata.refreshAt,
      createdAt: atKey.metadata.createdAt,
      updatedAt: atKey.metadata.updatedAt,
      dataSignature: atKey.metadata.dataSignature,
      sharedKeyStatus: atKey.metadata.sharedKeyStatus,
      isPublic: atKey.metadata.isPublic,
      isHidden: atKey.metadata.isHidden,
    ),
  );
}
