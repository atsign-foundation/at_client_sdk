import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'at_lookup_test_utils.dart';

void main() {
  OutboundConnection mockOutBoundConnection = MockOutboundConnectionImpl();

  group('A group of tests to verify buffer of outbound message listener', () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    test('A test to validate complete data comes in single packet', () async {
      await outboundMessageListener
          .messageHandler('data:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:phone@alice');
    });

    test(
        'A test to validate complete data comes in packet and prompt in different packet',
        () async {
      await outboundMessageListener
          .messageHandler('data:@bob:phone@alice\n'.codeUnits);
      await outboundMessageListener.messageHandler('@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:@bob:phone@alice');
    });

    test('A test to validate data two complete data comes in single packets',
        () async {
      await outboundMessageListener
          .messageHandler('data:@bob:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:@bob:phone@alice');
      await outboundMessageListener
          .messageHandler('data:public:phone@alice\n@alice@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:public:phone@alice');
    });

    test('A test to validate data two complete data comes in multiple packets',
        () async {
      await outboundMessageListener
          .messageHandler('data:public:phone@alice\n@ali'.codeUnits);
      await outboundMessageListener.messageHandler('ce@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:public:phone@alice');
      await outboundMessageListener.messageHandler(
          'data:@bob:location@alice,@bob:phone@alice\n@alice@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:@bob:location@alice,@bob:phone@alice');
    });

    test('A test to validate single data comes two packets', () async {
      await outboundMessageListener
          .messageHandler('data:public:phone@'.codeUnits);
      await outboundMessageListener.messageHandler('alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:public:phone@alice');
    });

    test('A test to validate data contains @', () async {
      await outboundMessageListener
          .messageHandler('data:phone@alice_12345675\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:phone@alice_12345675');
    });

    test(
        'A test to validate data contains @ and partial prompt of previous data',
        () async {
      // partial response of previous data.
      await outboundMessageListener.messageHandler('data:hello\n@'.codeUnits);
      await outboundMessageListener.messageHandler('alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:hello');
      await outboundMessageListener
          .messageHandler('data:phone@alice_12345675\n@alice@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:phone@alice_12345675');
    });

    test('A test to validate data contains new line character', () async {
      await outboundMessageListener.messageHandler(
          'data:value_contains_\nin_the_value\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:value_contains_\nin_the_value');
    });

    test('A test to validate data contains new line character and @', () async {
      await outboundMessageListener.messageHandler(
          'data:the_key_is\n@bob:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:the_key_is\n@bob:phone@alice');
    });
  });

  group('A group of test to verify response from unauthorized connection', () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    test('A test to validate response from unauthorized connection', () async {
      await outboundMessageListener.messageHandler('data:hello\n@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:hello');
    });

    test('A test to validate multiple response from unauthorized connection',
        () async {
      await outboundMessageListener.messageHandler('data:hello\n@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:hello');
      await outboundMessageListener.messageHandler('data:hi\n@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:hi');
    });

    test(
        'A test to validate response from unauthorized connection in multiple packets',
        () async {
      await outboundMessageListener
          .messageHandler('data:public:location@alice,'.codeUnits);
      await outboundMessageListener
          .messageHandler('public:phone@alice\n@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:public:location@alice,public:phone@alice');
      await outboundMessageListener.messageHandler('data:hi\n@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:hi');
    });
  });

  group('A group of test to validate buffer over flow scenarios', () {
    test('A test to verify buffer over flow exception', () {
      OutboundMessageListener outboundMessageListener =
          OutboundMessageListener(mockOutBoundConnection, bufferCapacity: 10);
      expect(
          () => outboundMessageListener
              .messageHandler('data:dummy_data_to_exceed_limit'.codeUnits),
          throwsA(predicate((dynamic e) =>
              e is BufferOverFlowException &&
              e.message ==
                  'data length exceeded the buffer limit. Data length : 31 and Buffer capacity 10')));
    });

    test('A test to verify buffer over flow with multiple data packets', () {
      OutboundMessageListener outboundMessageListener =
          OutboundMessageListener(mockOutBoundConnection, bufferCapacity: 20);
      outboundMessageListener.messageHandler('data:dummy_data'.codeUnits);
      expect(
          () => outboundMessageListener
              .messageHandler('to_exceed_limit\n@alice@'.codeUnits),
          throwsA(predicate((dynamic e) =>
              e is BufferOverFlowException &&
              e.message ==
                  'data length exceeded the buffer limit. Data length : 38 and Buffer capacity 20')));
    });
  });

  group('A group of tests to verify error: and stream responses from server',
      () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    test('A test to validate complete error comes in single packet', () async {
      await outboundMessageListener.messageHandler(
          'error:AT0012: Invalid value found\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'error:AT0012: Invalid value found');
    });

    test('A test to validate complete error comes in single packet', () async {
      await outboundMessageListener
          .messageHandler('stream:@bob:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'stream:@bob:phone@alice');
    });
  });

  group('A group of tests to verify AtTimeOutException', () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    setUp(() {
      when(() => mockOutBoundConnection.isInValid()).thenAnswer((_) => false);
      when(() => mockOutBoundConnection.close())
          .thenAnswer((Invocation invocation) async {});
    });
    test(
        'A test to verify when no data is received from server within transientWaitTimeMillis',
        () async {
      expect(
          () async =>
              await outboundMessageListener.read(transientWaitTimeMillis: 50),
          throwsA(predicate((dynamic e) =>
              e is AtTimeoutException &&
              e.message
                  .startsWith('Waited for 50 millis. No response after'))));
    });
    test(
        'A test to verify no response from server- wait time greater than maxWaitMillis',
        () async {
      expect(
          () async =>
              // we want to trigger the maxWaitMilliSeconds exception, so setting transient to a higher value
              await outboundMessageListener.read(
                  transientWaitTimeMillis: 100, maxWaitMilliSeconds: 50),
          throwsA(predicate((dynamic e) =>
              e is AtTimeoutException &&
              e.message.startsWith(
                  'Full response not received after 50 millis from '))));
    });
    test(
        'A test to verify partial response - wait time greater than transientWaitTimeMillis',
        () async {
      await outboundMessageListener
          .messageHandler('data:public:phone@'.codeUnits);
      await outboundMessageListener.messageHandler('12'.codeUnits);
      expect(
          () async =>
              await outboundMessageListener.read(transientWaitTimeMillis: 50),
          throwsA(predicate((dynamic e) =>
              e is AtTimeoutException &&
              e.message
                  .startsWith('Waited for 50 millis. No response after'))));
    });
    test(
        'A test to verify partial response - wait time greater than maxWaitMillis',
        () async {
      await outboundMessageListener
          .messageHandler('data:public:phone@'.codeUnits);
      await outboundMessageListener.messageHandler('12'.codeUnits);
      await outboundMessageListener.messageHandler('34'.codeUnits);
      await outboundMessageListener.messageHandler('56'.codeUnits);
      await outboundMessageListener.messageHandler('78'.codeUnits);
      expect(
          () async =>
              // we want to trigger the maxWaitMilliSeconds exception, so setting transient to a higher value
              await outboundMessageListener.read(
                  transientWaitTimeMillis: 30, maxWaitMilliSeconds: 20),
          throwsA(predicate((dynamic e) =>
              e is AtTimeoutException &&
              e.message ==
                  'Full response not received after 20 millis from remote atServer')));
    });
    test(
        'A test to verify full response received - delay between messages from server',
        () async {
      String? response;
      unawaited(outboundMessageListener
          .read(transientWaitTimeMillis: 50)
          .whenComplete(() => {})
          .then((value) => response = value));
      await outboundMessageListener.messageHandler('data:'.codeUnits);
      await Future.delayed(Duration(milliseconds: 25));
      await outboundMessageListener.messageHandler('12'.codeUnits);
      await Future.delayed(Duration(milliseconds: 15));
      await outboundMessageListener.messageHandler('34'.codeUnits);
      await Future.delayed(Duration(milliseconds: 17));
      await outboundMessageListener.messageHandler('56'.codeUnits);
      await Future.delayed(Duration(milliseconds: 30));
      await outboundMessageListener.messageHandler('78'.codeUnits);
      await Future.delayed(Duration(milliseconds: 45));
      await outboundMessageListener.messageHandler('910\n@'.codeUnits);
      await Future.delayed(Duration(milliseconds: 25));
      expect(response, isNotEmpty);
      expect(response, 'data:12345678910');
    });
    test(
        'A test to verify max wait timeout - delay between messages from server',
        () async {
      String? response;
      await outboundMessageListener
          .read(maxWaitMilliSeconds: 100)
          .catchError((e) {
            return e.toString();
          })
          .whenComplete(() => {})
          .then((value) => {response = value});
      await outboundMessageListener.messageHandler('data:'.codeUnits);
      await Future.delayed(Duration(milliseconds: 15));
      await outboundMessageListener.messageHandler('12'.codeUnits);
      await Future.delayed(Duration(milliseconds: 10));
      await outboundMessageListener.messageHandler('34'.codeUnits);
      await Future.delayed(Duration(milliseconds: 12));
      await outboundMessageListener.messageHandler('56'.codeUnits);
      await Future.delayed(Duration(milliseconds: 13));
      await outboundMessageListener.messageHandler('78'.codeUnits);
      await Future.delayed(Duration(milliseconds: 20));
      await outboundMessageListener.messageHandler('910'.codeUnits);
      await Future.delayed(Duration(milliseconds: 50));
      expect(response, isNotEmpty);
      expect(
        response!.contains(
            'Full response not received after 100 millis from '),
        true,
      );
    });
    test(
        'A test to verify transient timeout - delay between messages from server',
        () async {
      String? response;
      await outboundMessageListener
          .read(transientWaitTimeMillis: 50)
          .catchError((e) {
            return e.toString();
          })
          .whenComplete(() => {})
          .then((value) => {response = value});
      await outboundMessageListener.messageHandler('data:'.codeUnits);
      await Future.delayed(Duration(milliseconds: 10));
      await outboundMessageListener.messageHandler('12'.codeUnits);
      await Future.delayed(Duration(milliseconds: 15));
      await outboundMessageListener.messageHandler('34'.codeUnits);
      await Future.delayed(Duration(milliseconds: 17));
      await outboundMessageListener.messageHandler('56'.codeUnits);
      await Future.delayed(Duration(milliseconds: 20));
      await outboundMessageListener.messageHandler('78'.codeUnits);
      await Future.delayed(Duration(milliseconds: 10));
      await outboundMessageListener.messageHandler('910'.codeUnits);
      await Future.delayed(Duration(milliseconds: 60));
      expect(response, isNotEmpty);
      expect(
        response!.contains('Waited for 50 millis. No response after'),
        true,
      );
    });
  });
}
