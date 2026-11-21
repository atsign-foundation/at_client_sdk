import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client_web/src/js/bridge.dart';

/// The global the TypeScript package finds the bridge under.
const bridgeGlobal = '__atsignAtClientWeb';

/// Installs one [AtClientWebBridge] at `globalThis.__atsignAtClientWeb`.
void main() {
  globalContext[bridgeGlobal] = createJSInteropWrapper(AtClientWebBridge());
}
