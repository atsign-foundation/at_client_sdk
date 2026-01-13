import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

Future<void> main() async {
  // Test that AtRpcResp payloads are JSON parsable
  group('AtRpcResp', () {
    group('Non-deep payload', () {
      // A payload that is not deeply nested with JSON objects
      final Map<String, dynamic> payload = {
        'key': 'value',
        'key2': 42,
        'key3': true,
        'key4': null,
        'key5': 3.14,
        'key6': []
      };
      final AtRpcResp resp = AtRpcResp(
          reqId: 1,
          respType: AtRpcRespType.success,
          payload: payload,
          message: 'Test message');
      test('toJson', () {
        final Map<String, dynamic> toJsonOutput = resp.toJson();
        final Map<String, dynamic> expectedJsonOutput = {
          'reqId': resp.reqId,
          'respType': AtRpcRespType.success.name,
          'payload': payload,
          'message': resp.message,
        };
        expect(toJsonOutput, equals(expectedJsonOutput));
      });
      test('toString', () {
        final String toStringOutput = resp.toString();
        final String expectedStringOutput =
            '{"reqId":1,"respType":"success","payload":{"key":"value","key2":'
            '42,"key3":true,"key4":null,"key5":3.14,"key6":[]},"message":"Test'
            ' message"}';
        expect(toStringOutput, equals(expectedStringOutput));

        // now try parsing it and reading values
        final Map<String, dynamic> parsedJson = jsonDecode(toStringOutput);

        expect(parsedJson['reqId'], equals(1));
        expect(parsedJson['respType'], equals('success'));
        expect(parsedJson['payload']['key'], equals('value'));
        expect(parsedJson['payload']['key2'], equals(42));
        expect(parsedJson['payload']['key3'], equals(true));
        expect(parsedJson['payload']['key4'], isNull);
        expect(parsedJson['payload']['key5'], equals(3.14));
        expect(parsedJson['payload']['key6'], equals([]));
        expect(parsedJson['message'], equals('Test message'));
      });
    });

    group('Deep payload', () {
      final Map<String, dynamic> payload = {
        'level1': {
          'level2': {
            'level3': {
              'key': 'deepValue',
              'list': [
                1,
                2,
                3,
                {'nestedKey': 'nestedValue'}
              ]
            }
          }
        }
      };
      final AtRpcResp resp = AtRpcResp(
          reqId: 2,
          respType: AtRpcRespType.success,
          payload: payload,
          message: 'Deep payload test');
      test('toJson', () {
        final Map<String, dynamic> toJsonOutput = resp.toJson();
        final Map<String, dynamic> expectedJsonOutput = {
          'reqId': resp.reqId,
          'respType': AtRpcRespType.success.name,
          'payload': payload,
          'message': resp.message,
        };
        expect(toJsonOutput, equals(expectedJsonOutput));
      });
      test('toString', () {
        final String toStringOutput = resp.toString();
        final String expectedStringOutput =
            '{"reqId":2,"respType":"success","payload":{"level1":{"level2":'
            '{"level3":{"key":"deepValue","list":[1,2,3,{"nestedKey":"nestedV'
            'alue"}]}}}},"message":"Deep payload test"}';
        expect(toStringOutput, equals(expectedStringOutput));

        // now try parsing it and reading values
        final Map<String, dynamic> parsedJson = jsonDecode(toStringOutput);
        expect(parsedJson['reqId'], equals(2));
        expect(parsedJson['respType'], equals('success'));
        expect(parsedJson['payload']['level1']['level2']['level3']['key'],
            equals('deepValue'));
        expect(parsedJson['payload']['level1']['level2']['level3']['list'][0],
            equals(1));
        expect(parsedJson['payload']['level1']['level2']['level3']['list'][1],
            equals(2));
        expect(parsedJson['payload']['level1']['level2']['level3']['list'][2],
            equals(3));
        expect(
            parsedJson['payload']['level1']['level2']['level3']['list'][3]
                ['nestedKey'],
            equals('nestedValue'));
        expect(parsedJson['message'], equals('Deep payload test'));
      });
    });
  });

  // Test that AtRpcReq payloads are JSON parsable
  group('AtRpcReq', () {
    group('Non deep payload', () {
      final Map<String, dynamic> payload = {
        'param1': 'value1',
        'param2': 100,
        'param3': false,
        'param4': null,
        'param5': 2.71,
        'param6': []
      };
      final AtRpcReq req = AtRpcReq(reqId: 10, payload: payload);
      test('toJson', () {
        final Map<String, dynamic> toJsonOutput = req.toJson();
        final Map<String, dynamic> expectedJsonOutput = {
          'reqId': req.reqId,
          'payload': payload,
        };
        expect(toJsonOutput, equals(expectedJsonOutput));
      });
      test('toString', () {
        final String toStringOutput = req.toString();
        final String expectedStringOutput =
            '{"reqId":10,"payload":{"param1":"value1","param2":100,"param3":'
            'false,"param4":null,"param5":2.71,"param6":[]}}';
        expect(toStringOutput, equals(expectedStringOutput));

        // now try parsing it and reading values
        final Map<String, dynamic> parsedJson = jsonDecode(toStringOutput);
        expect(parsedJson['reqId'], equals(10));
        expect(parsedJson['payload']['param1'], equals('value1'));
        expect(parsedJson['payload']['param2'], equals(100));
        expect(parsedJson['payload']['param3'], equals(false));
        expect(parsedJson['payload']['param4'], isNull);
        expect(parsedJson['payload']['param5'], equals(2.71));
        expect(parsedJson['payload']['param6'], equals([]));
      });
    });
    group('Deep payload', () {
      final Map<String, dynamic> payload = {
        'config': {
          'settings': {
            'optionA': true,
            'optionB': {
              'subOption1': 'subValue1',
              'subOption2': [10, 20, 30]
            }
          }
        }
      };
      final AtRpcReq req = AtRpcReq(reqId: 20, payload: payload);
      test('toJson', () {
        final Map<String, dynamic> toJsonOutput = req.toJson();
        final Map<String, dynamic> expectedJsonOutput = {
          'reqId': req.reqId,
          'payload': payload,
        };
        expect(toJsonOutput, equals(expectedJsonOutput));
      });
      test('toString', () {
        final String toStringOutput = req.toString();
        final String expectedStringOutput =
            '{"reqId":20,"payload":{"config":{"settings":{"optionA":true,'
            '"optionB":{"subOption1":"subValue1","subOption2":[10,20,30]}}}}}';
        expect(toStringOutput, equals(expectedStringOutput));

        // now try parsing it and reading values
        final Map<String, dynamic> parsedJson = jsonDecode(toStringOutput);
        expect(parsedJson['reqId'], equals(20));
        expect(parsedJson['payload']['config']['settings']['optionA'],
            equals(true));
        expect(
            parsedJson['payload']['config']['settings']['optionB']
                ['subOption1'],
            equals('subValue1'));
        expect(
            parsedJson['payload']['config']['settings']['optionB']['subOption2']
                [0],
            equals(10));
        expect(
            parsedJson['payload']['config']['settings']['optionB']['subOption2']
                [1],
            equals(20));
        expect(
            parsedJson['payload']['config']['settings']['optionB']['subOption2']
                [2],
            equals(30));
      });
    });
  });
}
