import 'package:at_lookup/at_lookup_io.dart';

/// Connections through a proxy that fronts many atServers.
///
/// at_lookup itself sends the `from:<atSign>` such a proxy needs first on
/// every connection made for a `proxy:<host>` root domain, so this is
/// [secureSocketLookUps], TLS on TCP, and no more. A caller that reached the
/// proxy any other way, such as a plain root with a fixed address finder,
/// sends no `from:<atSign>` now: make the proxy the root domain instead.
@Deprecated('at_lookup sends from:<atSign> only for a proxy:<host> root '
    'domain; set the root domain to proxy:<host> and use '
    'secureSocketLookUps()')
AtLookUpFactory proxyLookUps() => secureSocketLookUps();

/// The `lookUps` for a client whose atDirectory is [rootDomain]:
/// [secureSocketLookUps] whatever [rootDomain] is, since at_lookup names the
/// atSign first itself when the root is a proxy (`proxy:<host>`).
@Deprecated('the root domain no longer picks the lookups; use '
    'secureSocketLookUps()')
AtLookUpFactory lookUpsFor(String rootDomain) => secureSocketLookUps();
