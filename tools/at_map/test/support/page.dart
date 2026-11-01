import 'dart:io';

import 'package:path/path.dart' as p;

import 'harness.dart';

/// A copy of the page beside [data], under [temp], as a file URL.
String pageOver(String data, Directory temp) {
  final dir = Directory(
      p.join(temp.path, 'page${DateTime.now().microsecondsSinceEpoch}'))
    ..createSync(recursive: true);
  for (final f in ['index.html', 'app.js', 'app.css']) {
    File(p.join(repoRoot(), 'docs/map', f)).copySync(p.join(dir.path, f));
  }
  for (final f in Directory(data).listSync(recursive: true).whereType<File>()) {
    final to = File(p.join(dir.path, 'data', p.relative(f.path, from: data)));
    to.parent.createSync(recursive: true);
    f.copySync(to.path);
  }
  return Uri.file(p.join(dir.path, 'index.html')).toString();
}

/// The committed page, as a file URL.
String committedPage() =>
    Uri.file(p.join(repoRoot(), 'docs/map/index.html')).toString();
