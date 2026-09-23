import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_lookup/at_lookup.dart';

/// Throws: the web has no default transport.
AtLookUpFactory defaultLookUps([AtClientPreference? preference]) =>
    throw StateError('There is no default transport on the web; pass lookUps: '
        '(e.g. webSocketLookUps from package:at_lookup/at_lookup_web.dart)');

/// Throws: the web has no atDirectory lookup.
SecondaryAddressFinder defaultSecondaryAddressFinder(
        AtClientPreference preference) =>
    throw StateError('There is no atDirectory lookup on the web; pass '
        'secondaryAddressFinder: or call '
        'AtClientManager.setSecondaryAddressFinder '
        '(e.g. ProxySecondaryAddressFinder(host, port))');
