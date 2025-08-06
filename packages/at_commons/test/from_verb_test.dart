import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/verb/from_verb_builder.dart';
import 'package:test/test.dart';

import 'syntax_test.dart';

void main() {
  group('A group of positive tests to validate the from regex', () {
    test('validating regex when atSign and client config are populated', () {
      var command = 'from:@alice:${AtConstants.clientConfig}:${jsonEncode({
            'version': '3.2.0'
          })}';
      var actualVerbParams = getVerbParams(VerbSyntax.from, command);
      expect(actualVerbParams['atSign'], '@alice');
      expect(actualVerbParams[AtConstants.clientConfig], '{"version":"3.2.0"}');
    });

    test('validating regex when only atSign is populated', () {
      var command = 'from:@alice';
      var actualVerbParams = getVerbParams(VerbSyntax.from, command);
      expect(actualVerbParams['atSign'], '@alice');
    });
  });

  group('A group of negative tests to validated from regex', () {
    test('A test to validate from verb builder with empty atSign', () {
      var fromVerbBuilder = FromVerbBuilder()..atSign = '';
      expect(fromVerbBuilder.checkParams(), false);
      var command = fromVerbBuilder.buildCommand();
      expect(
          () => getVerbParams(VerbSyntax.from, command),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    test(
        'validating regex when atSign is not populated and client config is populated',
        () {
      var fromVerbBuilder = FromVerbBuilder()
        ..atSign = ''
        ..clientConfig = {'version': '1.0.0'};
      expect(fromVerbBuilder.checkParams(), false);
      expect(fromVerbBuilder.clientConfig, {'version': '1.0.0'});
      expect(fromVerbBuilder.clientConfig['version'], '1.0.0');
      var command = fromVerbBuilder.buildCommand();
      expect(
          () => getVerbParams(VerbSyntax.from, command),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    test('A test to validate from verb builder with no atSign', () {
      var fromVerbBuilder = FromVerbBuilder();
      expect(() => fromVerbBuilder.buildCommand(),
          throwsA(predicate((dynamic e) => e is Error)));
    });
  });

  group('A group of from verb builder tests', () {
    test('A test to validate from verb builder with only atSign', () {
      var fromVerbBuilder = FromVerbBuilder()..atSign = '@alice';
      expect(fromVerbBuilder.checkParams(), true);
      expect(fromVerbBuilder.atSign, '@alice');
      var command = fromVerbBuilder.buildCommand();
      expect(command, 'from:@alice\n');
    });

    test('A test to validate from verb builder with atSign and client version',
        () {
      var fromVerbBuilder = FromVerbBuilder()
        ..atSign = '@alice'
        ..clientConfig = {'version': '1.0.0'};
      expect(fromVerbBuilder.checkParams(), true);
      expect(fromVerbBuilder.atSign, '@alice');
      expect(fromVerbBuilder.clientConfig, {'version': '1.0.0'});
      expect(fromVerbBuilder.clientConfig['version'], '1.0.0');
      var command = fromVerbBuilder.buildCommand();
      expect(command, 'from:@alice:clientConfig:{"version":"1.0.0"}\n');
    });
  });
}
