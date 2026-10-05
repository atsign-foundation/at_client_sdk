import 'dart:math';

// Returns 0, 1, 2, ... from nextInt so generated nonces are predictable
final class SequenceRandom implements Random {
  int _next = 0;

  @override
  int nextInt(int max) => _next++ % max;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1000) / 1000;
}
