import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'at_sync_material.dart' as material;
import 'at_sync_progress_indicator.dart';

const double _kDefaultIndicatorRadius = 10.0;

const Color _kDefaultActiveTickColor = Color(0xFFf4533d);

class AtSyncIndicator extends StatefulWidget {
  const AtSyncIndicator({
    Key? key,
    this.radius = _kDefaultIndicatorRadius,
    this.color,
    this.value,
  }) : super(key: key);

  /// Radius of the spinner widget.
  ///
  /// Defaults to 10px. Must be positive and cannot be null.
  final double radius;

  /// Determines the percentage of spinner ticks that will be shown. Typical usage would
  /// display all ticks, however, this allows for more fine-grained control such as
  /// during pull-to-refresh when the drag-down action shows one tick at a time as
  /// the user continues to drag down.
  ///
  /// Defaults to 1.0. Must be between 0.0 and 1.0 inclusive, and cannot be null.
  final double? value;

  final Color? color;

  @override
  State<AtSyncIndicator> createState() => _AtSyncIndicatorState();
}

class _AtSyncIndicatorState extends State<AtSyncIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AtSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value == null) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.radius * 2,
      width: widget.radius * 2,
      child: CustomPaint(
        painter: _AtSyncIndicatorPainter(
          position: _controller,
          activeColor: widget.color ?? _kDefaultActiveTickColor,
          radius: widget.radius,
          progress: widget.value,
        ),
      ),
    );
  }
}

const double _kTwoPI = math.pi * 2.0;

/// Alpha values extracted from the native component (for both dark and light mode) to
/// draw the spinning ticks.
const List<int> _kAlphaValues = <int>[
  47,
  47,
  47,
  47,
  72,
  97,
  122,
  147,
];

/// The alpha value that is used to draw the partially revealed ticks.
const int _partiallyRevealedAlpha = 147;

class _AtSyncIndicatorPainter extends CustomPainter {
  _AtSyncIndicatorPainter({
    required this.position,
    required this.activeColor,
    required this.radius,
    required this.progress,
  })  : tickFundamentalRRect = RRect.fromLTRBXY(
          -radius / _kDefaultIndicatorRadius,
          -radius / 3.0,
          radius / _kDefaultIndicatorRadius,
          -radius,
          radius / _kDefaultIndicatorRadius,
          radius / _kDefaultIndicatorRadius,
        ),
        super(repaint: position);

  final Animation<double> position;
  final Color activeColor;
  final double radius;
  final double? progress;

  final RRect tickFundamentalRRect;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final int tickCount = _kAlphaValues.length;
    // final double tickRadius = radius / tickCount * math.sqrt(2);

    canvas.save();
    canvas.translate(size.width / 2.0, size.height / 2.0);

    final int activeTick = (tickCount * position.value).floor();

    // for (int i = 0; i < tickCount; ++i) {
    //   final int t = (i - activeTick) % tickCount;
    //   paint.color = activeColor
    //       .withAlpha(progress < 1 ? _partiallyRevealedAlpha : _kAlphaValues[t]);
    //   // canvas.drawRRect(tickFundamentalRRect, paint);
    //   canvas.drawCircle(Offset(radius - tickRadius, 0), tickRadius, paint);
    //   canvas.rotate(_kTwoPI / tickCount);
    // }

    for (int i = 0; i < tickCount; ++i) {
      final int t = (i - activeTick) % tickCount;
      if (progress == null) {
        paint.color = activeColor.withAlpha(_kAlphaValues[t]);
      } else {
        if (i < ((progress ?? 0) * tickCount)) {
          paint.color = activeColor.withAlpha(_partiallyRevealedAlpha);
        } else {
          paint.color = activeColor.withAlpha(47);
        }
      }
      canvas.drawRRect(tickFundamentalRRect, paint);
      canvas.rotate(_kTwoPI / tickCount);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AtSyncIndicatorPainter oldPainter) {
    return oldPainter.position != position ||
        oldPainter.activeColor != activeColor ||
        oldPainter.progress != progress;
  }
}

class AtSyncButton extends StatelessWidget {
  final Widget? child;
  final bool isLoading;
  final VoidCallback? onPressed;
  final Color? syncIndicatorColor;

  const AtSyncButton({
    Key? key,
    this.child,
    this.isLoading = false,
    this.onPressed,
    this.syncIndicatorColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Visibility(
            visible: !isLoading,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: child ?? Container(),
          ),
          Visibility(
            visible: isLoading,
            child: AtSyncIndicator(
              color: syncIndicatorColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// An iOS-style activity indicator that spins clockwise.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=AENVH-ZqKDQ}
///
/// See also:
///
///  * <https://developer.apple.com/ios/human-interface-guidelines/controls/progress-indicators/#activity-indicators>
class AtSyncLinearProgressIndicator extends StatefulWidget {
  /// Creates an iOS-style activity indicator that spins clockwise.
  const AtSyncLinearProgressIndicator({
    Key? key,
    this.progress,
    this.color,
    this.minHeight,
  }) : super(key: key);

  /// Determines the percentage of spinner ticks that will be shown. Typical usage would
  /// display all ticks, however, this allows for more fine-grained control such as
  /// during pull-to-refresh when the drag-down action shows one tick at a time as
  /// the user continues to drag down.
  ///
  /// Defaults to 1.0. Must be between 0.0 and 1.0 inclusive, and cannot be null.
  final double? progress;

  final Color? color;

  /// {@template flutter.material.LinearProgressIndicator.minHeight}
  /// The minimum height of the line used to draw the linear indicator.
  ///
  /// If [LinearProgressIndicator.minHeight] is null then it will use the
  /// ambient [ProgressIndicatorThemeData.linearMinHeight]. If that is null
  /// it will use 4dp.
  /// {@endtemplate}
  final double? minHeight;

  @override
  State<AtSyncLinearProgressIndicator> createState() =>
      _AtSyncLinearIndicatorState();
}

class _AtSyncLinearIndicatorState extends State<AtSyncLinearProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    if (widget.progress == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AtSyncLinearProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      if (widget.progress == null) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.minHeight ?? 10,
      width: double.infinity,
      child: CustomPaint(
        painter: _AtSyncLinearIndicatorPainter(
          position: _controller,
          activeColor: widget.color ??
              CupertinoDynamicColor.resolve(_kDefaultActiveTickColor, context),
          progress: widget.progress,
        ),
      ),
    );
  }
}

class _AtSyncLinearIndicatorPainter extends CustomPainter {
  _AtSyncLinearIndicatorPainter({
    required this.position,
    required this.activeColor,
    required this.progress,
  }) : super(repaint: position);

  final Animation<double> position;
  final Color activeColor;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final tickWidth = size.height / 4;
    final defaultTickSpacer = size.height / 6;
    final int tickCount = size.width ~/ (tickWidth + defaultTickSpacer);
    final tickSpacer = (size.width - tickCount * tickWidth) / (tickCount - 1);

    canvas.save();
    canvas.translate(0, size.height / 2.0);

    final int activeTick = (tickCount * position.value).floor();

    for (int i = 0; i < tickCount; ++i) {
      final int t = (i - activeTick) % tickCount;
      final rRect = RRect.fromLTRBXY(
        i * (tickWidth + tickSpacer),
        size.height / 2,
        tickWidth + i * (tickWidth + tickSpacer),
        -size.height / 2,
        tickWidth / 2,
        tickWidth / 2,
      );
      if (progress == null) {
        paint.color = activeColor
            .withAlpha((progress ?? 1) < 1 ? 147 : (t < activeTick ? 147 : 47));
        canvas.drawRRect(rRect, paint);
      } else {
        if (i < tickCount * progress!) {
          paint.color = activeColor.withAlpha(147);
          canvas.drawRRect(rRect, paint);
        } else {
          paint.color = activeColor.withAlpha(47);
          canvas.drawRRect(rRect, paint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AtSyncLinearIndicatorPainter oldPainter) {
    return oldPainter.position != position ||
        oldPainter.activeColor != activeColor ||
        oldPainter.progress != progress;
  }
}

class AtSyncText extends StatelessWidget {
  /// If non-null, the value of this progress indicator.
  ///
  /// A value of 0.0 means no progress and 1.0 means that progress is complete.
  ///
  /// If null, this progress indicator is indeterminate, which means the
  /// indicator displays a predetermined animation that does not indicate how
  /// much actual progress is being made.
  final double? value;

  final Widget? child;

  final Color? indicatorColor;

  final TextStyle? textStyle;

  const AtSyncText({
    Key? key,
    this.value,
    this.child,
    this.indicatorColor,
    this.textStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AtSyncIndicator(
          value: value,
          color: indicatorColor,
        ),
        Text(
          '${((value ?? 0) * 100).toInt()}%',
          style: textStyle,
        ),
        Container(
          child: child,
        )
      ],
    );
  }
}

class AtSyncDialog extends material.AtSyncDialog {
  AtSyncDialog({
    required BuildContext context,
    Color? indicatorColor,
    Color? backgroundColor,
    TextStyle? messageStyle,
    TextStyle? valueStyle,
  }) : super(
          context: context,
          syncStyle: AtSyncStyle.cupertino,
          indicatorColor: indicatorColor,
          backgroundColor: backgroundColor,
          messageStyle: messageStyle,
          valueStyle: valueStyle,
        );
}

class AtSyncSnackBar extends material.AtSyncSnackBar {
  AtSyncSnackBar({
    required BuildContext context,
    Color? indicatorColor,
    Color? backgroundColor,
    TextStyle? textStyle,
  }) : super(
          context: context,
          syncStyle: AtSyncStyle.cupertino,
          indicatorColor: indicatorColor,
          backgroundColor: backgroundColor,
          textStyle: textStyle,
        );
}
