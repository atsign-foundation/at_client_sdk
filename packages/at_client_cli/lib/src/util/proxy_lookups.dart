import 'package:at_lookup/at_lookup_io.dart';

/// Connections through a proxy that fronts many atServers.
///
/// at_lookup itself sends the `from:<atSign>` such a proxy needs first on
/// every connection made for a `proxy:<host>` root domain, so this is
/// [secureSocketLookUps], TLS on TCP, and no more.
@Deprecated('at_lookup sends from:<atSign> for a proxy: root domain; use '
    'secureSocketLookUps()')
AtLookUpFactory proxyLookUps() => secureSocketLookUps();

/// The `lookUps` for a client whose atDirectory is [rootDomain]:
/// [secureSocketLookUps], which at_lookup makes name the atSign first when
/// [rootDomain] is a proxy (`proxy:<host>`).
AtLookUpFactory lookUpsFor(String rootDomain) => secureSocketLookUps();
