import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/util/at_client_util.dart';
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
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()
          ..namespaceAware = false
          ..isPublic = true
          ..isCached = true);
      var builder =
          LookUpBuilderManager.get(atKey, '@alice', AtClientPreference());
      expect(builder, isA<LLookupVerbBuilder>());
    });

    // Current atSign is bob
    // bob looking for a key shared by alice
    // llookup:cached:@bob:phone@alice;
    test('Test to verify cached shared key returns a Llookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..metadata = (Metadata()
          ..isCached = true
          ..namespaceAware = false);
      var builder =
          LookUpBuilderManager.get(atKey, '@alice', AtClientPreference());
      expect(builder, isA<LLookupVerbBuilder>());
    });

    test(
        'Test to verify a self key with sharedWith populated returns a llookup verb builder',
        () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..sharedWith = '@alice'
        ..metadata = (Metadata()..namespaceAware = false);
      var builder =
          LookUpBuilderManager.get(atKey, '@alice', AtClientPreference());
      expect(builder, isA<LLookupVerbBuilder>());
    });

    test('Test to verify a self key returns a llookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()..namespaceAware = false);
      var builder =
          LookUpBuilderManager.get(atKey, '@alice', AtClientPreference());
      expect(builder, isA<LLookupVerbBuilder>());
    });

    test('Test to verify a hidden key returns a llookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = '_phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()
          ..isHidden = true
          ..namespaceAware = false);
      var builder =
          LookUpBuilderManager.get(atKey, '@alice', AtClientPreference());
      expect(builder, isA<LLookupVerbBuilder>());
    });

    // Current atSign is bob
    // bob looking for a key shared by alice
    // plookup:phone@alice;
    test('Test to verify public key returns plookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()
          ..isPublic = true
          ..namespaceAware = false);
      var builder =
          LookUpBuilderManager.get(atKey, '@bob', AtClientPreference());
      expect(builder, isA<PLookupVerbBuilder>());
    });

    // Current atSign is bob
    // bob looking for a key shared by alice
    // lookup:phone@alice;
    test('Test to verify shared key returns a Lookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()..namespaceAware = false);
      var builder =
          LookUpBuilderManager.get(atKey, '@bob', AtClientPreference());
      expect(builder, isA<LookupVerbBuilder>());
    });
  });

  group('A group of tests to validate appending namespace to key', () {
    test('A test to verify namespace from AtKey is appended to key', () {
      String atKey = AtClientUtil.getKeyWithNameSpace(
          AtKey.self('phone', namespace: 'wavi').build(),
          (AtClientPreference()));
      expect(atKey, 'phone.wavi');
    });

    test('A test to verify namespace from preference is appended to key', () {
      String atKey = AtClientUtil.getKeyWithNameSpace(
          AtKey.self('phone').build(),
          (AtClientPreference()..namespace = 'wavi'));
      expect(atKey, 'phone.wavi');
    });

    test(
        'A test to verify namespace is not appended to key when already present',
        () {
      String atKey = AtClientUtil.getKeyWithNameSpace(
          AtKey.self('phone.wavi').build(), (AtClientPreference()));
      expect(atKey, 'phone.wavi');
    });

    test(
        'A test to verify namespace is not appended when namespaceAware is set to false',
        () {
      String atKey = AtClientUtil.getKeyWithNameSpace(
          AtKey()
            ..key = 'phone'
            ..namespace = 'wavi'
            ..metadata = (Metadata()..namespaceAware = false),
          (AtClientPreference()));
      expect(atKey, 'phone');
    });
  });
  group('A group of tests to check bypass cache flag', () {
    test('A test to verify bypass cache flag in plookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()
          ..isPublic = true
          ..namespaceAware = false);
      final requestOptions = GetRequestOptions()..bypassCache = true;
      var builder = LookUpBuilderManager.get(
          atKey, '@bob', AtClientPreference(),
          getRequestOptions: requestOptions);
      expect(builder, isA<PLookupVerbBuilder>());
      expect(builder.buildCommand(), contains('bypassCache:true'));
    });

    test('A test to verify bypass cache flag in lookup verb builder', () {
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()..namespaceAware = false);
      final requestOptions = GetRequestOptions()..bypassCache = true;
      var builder = LookUpBuilderManager.get(
          atKey, '@bob', AtClientPreference(),
          getRequestOptions: requestOptions);
      expect(builder, isA<LookupVerbBuilder>());
      expect(builder.buildCommand(), contains('bypassCache:true'));
    });
  });
}
