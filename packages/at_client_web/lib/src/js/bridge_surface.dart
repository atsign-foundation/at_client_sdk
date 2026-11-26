// The JS surface of the bridge, as data.
//
// This file imports nothing, so a VM script (`tool/manifest.dart`) can import
// it without reaching `dart:js_interop`. The exported classes in
// `bridge.dart` remain the definition; `test/js/manifest_test.dart` scans
// them and fails when this list and the classes disagree.

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
