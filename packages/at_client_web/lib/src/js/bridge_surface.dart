// The JS surface of the bridge, as data.
//
// This file imports nothing, so a VM script (`tool/manifest.dart`) can import
// it without reaching `dart:js_interop`. The exported classes in
// `bridge.dart` remain the definition; `test/js/manifest_test.dart` scans
// them and fails when this list and the classes disagree.

/// The options `BridgeEntry.create` reads, per session form: the keys form and
/// the passkey form. `passkey` is in both, because `_options` reads it before
/// it branches and an absent or false value selects the keys form. Each list
/// is sorted.
const createOptions = <String, List<String>>{
  'keys': [
    'appName',
    'appVersion',
    'atSign',
    'keys',
    'namespace',
    'passkey',
    'rootDomain',
  ],
  'passkey': [
    'appName',
    'appVersion',
    'atSign',
    'namespace',
    'passkey',
    'rootDomain',
    'rpId',
    'rpName',
  ],
};

/// The fields of each envelope the bridge hands JS. Each list is sorted.
const envelopes = <String, List<String>>{
  'keyParts': [
    'isCached',
    'isPublic',
    'name',
    'namespace',
    'sharedBy',
    'sharedWith',
  ],
  'subscribe': [
    'epochMillis',
    'from',
    'id',
    'key',
    'keyParts',
    'operation',
    'value',
  ],
};

/// Every status `AtClientSession` reports, sorted. There is no other state:
/// the connection having stopped leaves the last status in place.
const statuses = <String>[
  'connected',
  'connecting',
  'waiting:auth',
  'waiting:network',
  'waiting:server',
];

/// The exported classes and their exported members: exactly what
/// `bridge.dart` exposes to JavaScript. Each member list is sorted; the map's
/// own keys are not, and `tool/manifest.dart` sorts them when it writes the
/// manifest.
const bridgeSurface = <String, List<String>>{
  'BridgeEntry': ['create'],
  'BridgeCollection': [
    'create',
    'get',
    'list',
    'query',
    'remove',
    'share',
    'update',
    'watch',
  ],
  'BridgeSession': [
    'approve',
    'atSign',
    'close',
    'collection',
    'deny',
    'notify',
    'onStatus',
    'otp',
    'pendingEnrollments',
    'status',
    'subscribe',
  ],
};
