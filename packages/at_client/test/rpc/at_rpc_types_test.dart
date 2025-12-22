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
        message: 'Test message'
      ); 
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
          '{"reqId":1,"respType":"success","payload":{"key":"value","key2":42,"key3":true,"key4":null,"key5":3.14,"key6":[]},"message":"Test message"}';
        expect(toStringOutput, equals(expectedStringOutput));
      });
    });

    group('Deep payload', () {
      final Map<String, dynamic> payload = {
        'level1': {
          'level2': {
            'level3': {
              'key': 'deepValue',
              'list': [1, 2, 3, {'nestedKey': 'nestedValue'}]
            }
          }
        }
      };
      final AtRpcResp resp = AtRpcResp(
        reqId: 2,
        respType: AtRpcRespType.success,
        payload: payload,
        message: 'Deep payload test'
      );
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
          '{"reqId":2,"respType":"success","payload":{"level1":{"level2":{"level3":{"key":"deepValue","list":[1,2,3,{"nestedKey":"nestedValue"}]}}}},"message":"Deep payload test"}';
        expect(toStringOutput, equals(expectedStringOutput));
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
      final AtRpcReq req = AtRpcReq(
        reqId: 10,
        payload: payload
      );
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
          '{"reqId":10,"payload":{"param1":"value1","param2":100,"param3":false,"param4":null,"param5":2.71,"param6":[]}}';
        expect(toStringOutput, equals(expectedStringOutput));
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
      final AtRpcReq req = AtRpcReq(
        reqId: 20,
        payload: payload
      );
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
          '{"reqId":20,"payload":{"config":{"settings":{"optionA":true,"optionB":{"subOption1":"subValue1","subOption2":[10,20,30]}}}}}';
        expect(toStringOutput, equals(expectedStringOutput));
      }); 
    });
  });
}

