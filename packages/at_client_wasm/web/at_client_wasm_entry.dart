import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_client_wasm/src/collections/js_collections_adapter.dart';

/// The compile target `test/web/compile_test.dart` builds with dart2js and
/// dart2wasm: it pulls in the whole slim client, `InMemoryAtClientStorage`
/// among it, and the JS collections adapter.
Future<void> main() async {
  final options = DevSessionOptions(atSign: '@alice', app: 'wavi');
  print(sessionTransport(options).finder);
  print(_adapter);
}

/// Reaches every adapter operation, so both compiles cover all of it.
Future<void> _adapter(AtClient client) async {
  final todos = await JsCollectionsAdapter.open(client,
      namespace: 'todos.wavi', type: 'Todo', expirationMs: 1);
  final item = await todos.create({'title': 'a'});
  final address = (id: item['id'] as String, owner: item['owner'] as String);
  await todos.get(address);
  await todos.list();
  await todos.query([(path: 'title', op: '<', value: 'b')]);
  await todos.update(address, {'title': 'b'});
  await todos.share(address, ['@bob']);
  await todos.remove(address, cascade: true);
  await todos.watch(print, onError: print)();
}
