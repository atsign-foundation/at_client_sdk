import 'package:test/test.dart';
import 'package:at_onboarding_cli/src/util/root_server_parser.dart';

void main() {
  group('RootServerParser tests', () {
    test('parse host only - should default to port 64', () {
      final result = RootServerParser.parse('example.com');
      
      expect(result.host, equals('example.com'));
      expect(result.port, equals(64));
      expect(result.isUsingProxy, equals(false));
    });

    test('parse host:port format', () {
      final result = RootServerParser.parse('example.com:8080');
      
      expect(result.host, equals('example.com'));
      expect(result.port, equals(8080));
      expect(result.isUsingProxy, equals(false));
    });

    test('parse host:invalid_port - should default to port 64', () {
      final result = RootServerParser.parse('example.com:invalid');
      
      expect(result.host, equals('example.com'));
      expect(result.port, equals(64));
      expect(result.isUsingProxy, equals(false));
    });

    test('parse proxy:host format', () {
      final result = RootServerParser.parse('proxy:example.com');
      
      expect(result.host, equals('proxy:example.com'));
      expect(result.port, equals(64));
      expect(result.isUsingProxy, equals(true));
    });

    test('parse proxy:host:port format', () {
      final result = RootServerParser.parse('proxy:example.com:8080');
      
      expect(result.host, equals('proxy:example.com'));
      expect(result.port, equals(8080));
      expect(result.isUsingProxy, equals(true));
    });

    test('parse proxy:host:invalid_port - should default to port 64', () {
      final result = RootServerParser.parse('proxy:example.com:invalid');
      
      expect(result.host, equals('proxy:example.com'));
      expect(result.port, equals(64));
      expect(result.isUsingProxy, equals(true));
    });

    test('parse empty string - should use defaults', () {
      final result = RootServerParser.parse('');
      
      expect(result.host, equals(''));
      expect(result.port, equals(64));
      expect(result.isUsingProxy, equals(false));
    });
  });
}