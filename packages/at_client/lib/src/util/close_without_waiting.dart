import 'dart:async' show StreamController, unawaited;

/// Closes [controller] and returns at once, without waiting for its
/// subscribers to take the `done` event.
///
/// `close()` on a broadcast controller completes only once every subscriber has
/// taken `done`, and a PAUSED subscriber never does until it resumes. When the
/// close belongs to a client stop the caller is awaiting, awaiting it here would
/// hang that stop for as long as any subscriber stays paused. Firing it
/// unawaited lets the stop return; the paused subscriber still gets `done` when
/// it resumes. A controller already closed is left untouched.
void closeWithoutWaiting<T>(StreamController<T> controller) {
  if (!controller.isClosed) unawaited(controller.close());
}
