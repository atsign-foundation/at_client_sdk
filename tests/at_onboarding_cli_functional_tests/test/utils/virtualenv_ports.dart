import 'dart:io';

/// The virtualenv's atDirectory port, 64 unless `VIRTUALENV_BASE_PORT` is set.
///
/// Every site naming `vip.ve.atsign.zone` must also set this: the preference
/// default is 64 regardless of the base port.
int get virtualenvRootPort =>
    int.tryParse(Platform.environment['VIRTUALENV_BASE_PORT'] ?? '') ?? 64;

/// The host port of the atServer that binds [legacyPort] on an unshifted run.
///
/// atServers occupy `[base+1, base+98]`, so the shift is one past the base.
int virtualenvSecondaryPort(int legacyPort) {
  final base = int.tryParse(Platform.environment['VIRTUALENV_BASE_PORT'] ?? '');
  return base == null ? legacyPort : base + 1 + (legacyPort - 25000);
}
