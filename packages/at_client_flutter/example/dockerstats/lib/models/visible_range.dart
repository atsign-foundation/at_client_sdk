/// The dashboard's chart-visible time range.
///
/// Two state bits: how wide the window is ([spanMs]) and whether
/// the right edge is **pinned to "now"** ([endMs] == null, "live")
/// or anchored to a specific past timestamp ([endMs] != null,
/// "historical").
///
/// Range transformations ([zoomedAroundCenter], [pannedBy],
/// [goingLive], [fittingAll]) live on this class as pure functions
/// returning new instances — easier to test, and the dashboard
/// state is the only mutator.
///
/// Clamping is **always done by the caller** against the actual
/// data extent — the model itself doesn't know which dataset it
/// belongs to.
library;

import 'package:flutter/foundation.dart';

/// Minimum span the user can zoom into.
const Duration minVisibleSpan = Duration(minutes: 5);

@immutable
class VisibleRange {
  /// Width of the chart's x-axis in milliseconds.
  final int spanMs;

  /// Right edge of the chart, or `null` if pinned to current time
  /// (the "live" state). When null, the right edge tracks `now`
  /// each frame; the left edge follows as `now - spanMs`.
  final int? endMs;

  const VisibleRange({required this.spanMs, this.endMs});

  /// True when the right edge tracks "now". False when the range
  /// has been scrolled to a fixed historical window.
  bool get isLive => endMs == null;

  /// Resolve [endMs] against [nowMs] — `nowMs` when live, the stored
  /// value otherwise.
  int resolveEndMs(int nowMs) => endMs ?? nowMs;

  /// Resolve [startMs] = [resolveEndMs] − [spanMs].
  int resolveStartMs(int nowMs) => resolveEndMs(nowMs) - spanMs;

  /// Return a new range with the same `endMs` anchor but a new
  /// [spanMs] — zooming keeps the *center* of the visible window
  /// fixed (so a user reading the chart's midpoint stays roughly
  /// under the same data).
  ///
  /// - `factor > 1` zooms in (narrower span).
  /// - `factor < 1` zooms out (wider span).
  /// - Live ranges stay live when the new span is still bounded by
  ///   `now`. Historical ranges that would otherwise extend past
  ///   `now` snap back to live.
  /// - Spans are clamped to `[minSpanMs, maxSpanMs]` — pass
  ///   `dataExtent` from the service.
  VisibleRange zoomedAroundCenter(
    double factor, {
    required int nowMs,
    required int minSpanMs,
    required int maxSpanMs,
  }) {
    if (factor <= 0) return this;
    final newSpan = (spanMs / factor).round().clamp(minSpanMs, maxSpanMs);
    if (isLive) {
      return VisibleRange(spanMs: newSpan, endMs: null);
    }
    final centerMs = resolveEndMs(nowMs) - spanMs ~/ 2;
    final newEnd = centerMs + newSpan ~/ 2;
    if (newEnd >= nowMs) {
      return VisibleRange(spanMs: newSpan, endMs: null);
    }
    return VisibleRange(spanMs: newSpan, endMs: newEnd);
  }

  /// Shift the range by [deltaMs] — positive = pan right (toward
  /// "now"), negative = pan left (toward older data).
  ///
  /// - Panning past `now` snaps back to live (your stated rule).
  /// - Panning past `earliestMs` clamps so the left edge sits at
  ///   `earliestMs` (you can't scroll into data you don't have).
  VisibleRange pannedBy(
    int deltaMs, {
    required int nowMs,
    required int earliestMs,
  }) {
    final currentEnd = resolveEndMs(nowMs);
    final proposedEnd = currentEnd + deltaMs;
    if (proposedEnd >= nowMs) {
      return VisibleRange(spanMs: spanMs, endMs: null);
    }
    final minEnd = earliestMs + spanMs;
    final clampedEnd = proposedEnd < minEnd ? minEnd : proposedEnd;
    return VisibleRange(spanMs: spanMs, endMs: clampedEnd);
  }

  /// Snap the right edge back to "now", preserving the current
  /// span. The Live button does this regardless of the current
  /// state.
  VisibleRange goingLive() {
    return VisibleRange(spanMs: spanMs, endMs: null);
  }

  /// Zoom the range to cover the full data extent and pin live.
  /// `latestMs` is implied by going live; [earliestMs] determines
  /// the span. The Fit button does this.
  VisibleRange fittingAll({required int earliestMs, required int nowMs}) {
    final span = nowMs - earliestMs;
    return VisibleRange(spanMs: span > 0 ? span : spanMs, endMs: null);
  }

  /// Construct a live range of [spanMs]. Used by the preset
  /// shortcuts (1h, 1d, 1m, 1y, all).
  static VisibleRange livePreset(int spanMs) {
    return VisibleRange(spanMs: spanMs, endMs: null);
  }

  @override
  bool operator ==(Object other) =>
      other is VisibleRange && other.spanMs == spanMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(spanMs, endMs);

  @override
  String toString() {
    if (isLive) return 'VisibleRange(spanMs: $spanMs, live)';
    return 'VisibleRange(spanMs: $spanMs, endMs: $endMs)';
  }
}
