import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to verify legacy AtKey', () {
    // Current atSign is bob
    // bob looking for a key shared by alice
    // llookup:cached:public:phone@alice;
    test(
        'Test to verify cached public key returns a Local lookup  verb builder',
        () {
      var metadata = Metadata()
        ..isPublic = true
        ..isCached = true;

      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = metadata;
      var builder = LookUpBuilderManager.get(atKey, '@alice');
      expect(builder, isA<LLookupVerbBuilder>());
    });

    // Current atSign is bob
    // bob looking for a key shared by alice
    // llookup:cached:@bob:phone@alice;
    test('Test to verify cached shared key returns a Llookup verb builder', () {
      var metadata = Metadata()..isCached = true;
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..metadata = metadata;
      var builder = LookUpBuilderManager.get(atKey, '@alice');
      expect(builder, isA<LLookupVerbBuilder>());
    });

    test(
        'Test to verify a self key with sharedWith populated returns a llookup verb builder',
        () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..sharedWith = '@alice';
      var builder = LookUpBuilderManager.get(atKey, '@alice');
      expect(builder, isA<LLookupVerbBuilder>());
    });

    test('Test to verify a self key returns a llookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = Metadata();
      var builder = LookUpBuilderManager.get(atKey, '@alice');
      expect(builder, isA<LLookupVerbBuilder>());
    });

    test('Test to verify a hidden key returns a llookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = '_phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()..isHidden = true);
      var builder = LookUpBuilderManager.get(atKey, '@alice');
      expect(builder, isA<LLookupVerbBuilder>());
    });

    // Current atSign is bob
    // bob looking for a key shared by alice
    // plookup:phone@alice;
    test('Test to verify public key returns plookup verb builder', () {
      var metadata = Metadata()..isPublic = true;
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = metadata;
      var builder = LookUpBuilderManager.get(atKey, '@bob');
      expect(builder, isA<PLookupVerbBuilder>());
    });

    // Current atSign is bob
    // bob looking for a key shared by alice
    // lookup:phone@alice;
    test('Test to verify shared key returns a Lookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = Metadata();
      var builder = LookUpBuilderManager.get(atKey, '@bob');
      expect(builder, isA<LookupVerbBuilder>());
    });
  });
}
