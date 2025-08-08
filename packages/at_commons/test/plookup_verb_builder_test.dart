import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';

void main() {
  group('A group of lookup verb builder tests', () {
    test('verify simple plookup command', () {
      var plookupVerbBuilder = PLookupVerbBuilder()
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice';
      expect(plookupVerbBuilder.buildCommand(), 'plookup:phone@alice\n');
    });
    test('verify plookup meta command', () {
      var plookupVerbBuilder = PLookupVerbBuilder()
        ..operation = 'meta'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(plookupVerbBuilder.buildCommand(), 'plookup:meta:email@alice\n');
    });

    test('verify plookup all command', () {
      var plookupVerbBuilder = PLookupVerbBuilder()
        ..operation = 'all'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(plookupVerbBuilder.buildCommand(), 'plookup:all:email@alice\n');
    });

    test('verify plookup bypass cache command', () {
      var plookupVerbBuilder = PLookupVerbBuilder()
        ..bypassCache = true
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(plookupVerbBuilder.buildCommand(),
          'plookup:bypassCache:true:email@alice\n');
    });
  });
}
