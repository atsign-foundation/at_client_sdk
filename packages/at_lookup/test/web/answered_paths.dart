import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart';

/// The raw paths of the requests a fake on [port] has taken since the last
/// call, in the order it took them, read from its `GET /__answered`.
Future<List<String>> answeredPaths(int port) async {
  final response = await window
      .fetch('http://127.0.0.1:$port/__answered'.toJS,
          RequestInit(cache: 'no-store'))
      .toDart;
  final body = (await response.text().toDart).toDart;
  return (jsonDecode(body) as List).cast<String>();
}
