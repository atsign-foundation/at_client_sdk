import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';

void main() {
  group('A group of lookup verb builder tests', () {
    test('verify simple lookup command', () {
      var lookupVerbBuilder = LookupVerbBuilder()
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice';
      expect(lookupVerbBuilder.buildCommand(), 'lookup:phone@alice\n');
    });
    test('verify lookup meta command', () {
      var lookupVerbBuilder = LookupVerbBuilder()
        ..operation = 'meta'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(lookupVerbBuilder.buildCommand(), 'lookup:meta:email@alice\n');
    });

    test('verify lookup all command', () {
      var lookupVerbBuilder = LookupVerbBuilder()
        ..operation = 'all'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(lookupVerbBuilder.buildCommand(), 'lookup:all:email@alice\n');
    });

    test('verify lookup bypass cache command', () {
      var lookupVerbBuilder = LookupVerbBuilder()
        ..bypassCache = true
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(lookupVerbBuilder.buildCommand(),
          'lookup:bypassCache:true:email@alice\n');
    });
  });
}
