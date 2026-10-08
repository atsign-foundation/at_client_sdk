import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// Reading an atServer's `info` `features`: present unless Retired, and a
/// warning, once, for anything not GA.
void main() {
  test('the names and statuses travel exactly as these literals', () {
    // FROZEN: client and atServer both compare against these, so a typo in a
    // constant would pass every test that used the constant.
    expect(InfoFeature.notifyEph, 'notify.eph');
    expect(InfoFeature.notifyEAtn, 'notify.eAtn');
    expect(InfoFeature.notifyAll, 'notify.all');
    expect(InfoFeature.notifyText, 'notify.text');
    expect(InfoFeatureStatus.preview, 'Preview');
    expect(InfoFeatureStatus.beta, 'Beta');
    expect(InfoFeatureStatus.ga, 'GA');
    expect(InfoFeatureStatus.deprecated, 'Deprecated');
    expect(InfoFeatureStatus.retired, 'Retired');
  });

  group('present unless Retired', () {
    final features = InfoFeatures.parse('data:{"version":"3.17.0","features":['
        '{"name":"notify.eph","status":"GA","description":"x"},'
        '{"name":"notify.eAtn","status":"Deprecated","description":"x"},'
        '{"name":"notify.all","status":"Retired","description":"x"},'
        '{"name":"a.lower","status":"retired","description":"x"},'
        '{"name":"a.unknown","status":"Sunset","description":"x"},'
        '{"name":"a.none","description":"x"}]}')!;

    test('GA and Deprecated count; Retired does not', () {
      expect(features.has('notify.eph'), isTrue);
      expect(features.has('notify.eAtn'), isTrue);
      expect(features.has('notify.all'), isFalse);
    });

    test('statuses are compared exactly, and any other counts', () {
      expect(features.has('a.lower'), isTrue,
          reason: '"retired" is not "Retired"');
      expect(features.has('a.unknown'), isTrue);
      expect(features.has('a.none'), isTrue);
      expect(features.statusOf('a.none'), isNull);
    });

    test('an unlisted feature is absent', () {
      expect(features.has('notify.unlisted'), isFalse);
    });
  });

  test('anything not GA warns, once per feature, naming its status', () {
    final features = InfoFeatures({'notify.eph': 'Beta', 'notify.eAtn': 'GA'});
    final warnings = <String>[];
    features.has('notify.eph', warn: warnings.add);
    features.has('notify.eph', warn: warnings.add);
    features.has('notify.eAtn', warn: warnings.add);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('notify.eph'));
    expect(warnings.single, contains('Beta'));
  });

  test('a name listed twice is absent if either entry says Retired', () {
    for (final pair in [
      ['GA', 'Retired'],
      ['Retired', 'GA']
    ]) {
      final features = InfoFeatures.parse('{"features":['
          '{"name":"notify.eph","status":"${pair[0]}"},'
          '{"name":"notify.eph","status":"${pair[1]}"}]}')!;
      expect(features.has('notify.eph'), isFalse, reason: '$pair');
    }
  });

  test('a reply it cannot read is null; one listing nothing is empty', () {
    expect(InfoFeatures.parse('data:not json'), isNull);
    expect(InfoFeatures.parse('[1,2]'), isNull);
    final none = InfoFeatures.parse('{"version":"3.16.5"}')!;
    expect(none.has('notify.eph'), isFalse,
        reason: 'and the data: prefix is optional');
  });
}
