import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';

import 'samples/test_util.dart';

void main() {
  group('A group of tests to verify getSecondary Instance', () {
    setUp(() async {
      final atSign = '@alice';
      await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, 'wavi', TestUtil.getMuraliPreference());
    });
    test('A local lookup returns local secondary instance', () async {
      var builder = LLookupVerbBuilder();
      var secondary = SecondaryManager.getSecondary(builder);
      expect(secondary, isA<LocalSecondary>());
    });

    test('A lookup returns remote secondary instance', () async {
      var builder = LookupVerbBuilder();
      var secondary = SecondaryManager.getSecondary(builder);
      expect(secondary, isA<RemoteSecondary>());
    });

    test('A public key lookup returns remote secondary instance', () async {
      var builder = PLookupVerbBuilder();
      var secondary = SecondaryManager.getSecondary(builder);
      expect(secondary, isA<RemoteSecondary>());
    });

    test('A public key update returns local secondary instance', () async {
      var builder = UpdateVerbBuilder();
      var secondary = SecondaryManager.getSecondary(builder);
      expect(secondary, isA<LocalSecondary>());
    });

    test('A share key notify returns remote secondary instance', () async {
      var builder = NotifyVerbBuilder();
      var secondary = SecondaryManager.getSecondary(builder);
      expect(secondary, isA<RemoteSecondary>());
    });

    test('Test to verify the stats key returns remote secondary', () async {
      var builder = StatsVerbBuilder();
      var secondary = SecondaryManager.getSecondary(builder);
      expect(secondary, isA<RemoteSecondary>());
    });
  });

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
