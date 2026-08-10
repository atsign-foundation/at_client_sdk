import 'package:at_lookup/at_lookup.dart' show SecondaryAddressFinder;

/// The process-wide source `RemoteSecondary` consults for an atDirectory
/// lookup when none was handed to it.
///
/// `RemoteSecondary` has always read
/// `AtClientManager.getInstance().secondaryAddressFinder` — the singleton
/// manager's finder, never a per-atSign manager's own — and this seam
/// preserves exactly that: `AtClientManager`'s constructors register a
/// source that reads the singleton's field, and the read stays lazy (per
/// call, not captured), so a finder set after a `RemoteSecondary` was
/// built is still found. The seam exists so `RemoteSecondary` does not
/// import the manager, which sits above it and imports the whole client.
///
/// When no manager was ever constructed the source is unregistered and
/// the answer is null — the same null the singleton's untouched field
/// held before.
SecondaryAddressFinder? Function()? _source;

/// Registers where [processSecondaryAddressFinder] looks. Later
/// registrations replace earlier ones.
void registerSecondaryAddressFinderSource(
    SecondaryAddressFinder? Function() source) {
  _source = source;
}

/// The process's atDirectory lookup, or null when none is available.
SecondaryAddressFinder? processSecondaryAddressFinder() => _source?.call();
