/// A helper the exit walker's tests follow into another file.
library;

import 'handlers.dart';

/// A helper in another file.
void otherFile(int n) {
  if (n == 13) throw InvalidSyntaxException('thirteen');
}
