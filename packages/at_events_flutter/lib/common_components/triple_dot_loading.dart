import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    Key? key,
    this.showIndicator = false,
    this.flashingCircleDarkColor = const Color(0xFF333333),
    this.flashingCircleBrightColor = const Color(0xFFaec1dd),
  }) : super(key: key);

  final bool showIndicator;
  final Color flashingCircleDarkColor;
  final Color flashingCircleBrightColor;

  @override
  _TypingIndicatorState createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  AnimationController? _appearanceController;
  late Animation<double> _indicatorSpaceAnimation;
  late Animation<double> _largeBubbleAnimation;

  late AnimationController _repeatingController;
  final List<Interval> _dotIntervals = const [
    Interval(0.25, 0.8),
    Interval(0.35, 0.9),
    Interval(0.45, 1.0),
  ];

  @override
  void initState() {
    super.initState();

    _appearanceController = AnimationController(
      vsync: this,
    )..addListener(() {
        setState(() {});
      });

    _indicatorSpaceAnimation = CurvedAnimation(
      parent: _appearanceController!,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeOut),
    ).drive(Tween<double>(
      begin: 0.0,
      end: 60.0,
    ));

    _largeBubbleAnimation = CurvedAnimation(
      parent: _appearanceController!,
      curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
      reverseCurve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );

    _repeatingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    if (widget.showIndicator) {
      _showIndicator();
    }
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.showIndicator != oldWidget.showIndicator) {
      if (widget.showIndicator) {
        _showIndicator();
      } else {
        _hideIndicator();
      }
    }
  }

  @override
  void dispose() {
    _appearanceController!.dispose();
    _repeatingController.dispose();
    super.dispose();
  }

  /// shows an indicator by animating its appearance and starting a repeating animation
  void _showIndicator() {
    _appearanceController!
      ..duration = const Duration(milliseconds: 750)
      ..forward();
    _repeatingController.repeat();
  }

  /// hides the indicator by animating its disappearance and stopping the repeating animation
  void _hideIndicator() {
    _appearanceController!
      ..duration = const Duration(milliseconds: 150)
      ..reverse();
    _repeatingController.stop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _indicatorSpaceAnimation,
      builder: (context, child) {
        return SizedBox(
          height: _indicatorSpaceAnimation.value,
          child: child,
        );
      },
      child: _buildAnimatedBubble(
        animation: _largeBubbleAnimation,
        left: 12,
        bottom: 12,
        bubble: _buildStatusBubble(),
      ),
    );
  }

  /// builds an animated bubble widget with scaling animation based on the provided animation, position, and bubble content
  Widget _buildAnimatedBubble({
    required Animation<double> animation,
    required double left,
    required double bottom,
    required Widget bubble,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.scale(
          scale: animation.value,
          alignment: Alignment.bottomLeft,
          child: child,
        );
      },
      child: bubble,
    );
  }

  /// builds a status bubble widget containing three flashing circles arranged horizontally
  Widget _buildStatusBubble() {
    return Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFlashingCircle(0),
          _buildFlashingCircle(1),
          _buildFlashingCircle(2),
        ],
      ),
    );
  }

  /// builds a flashing circle widget based on the provided index
  Widget _buildFlashingCircle(int index) {
    return AnimatedBuilder(
      animation: _repeatingController,
      builder: (context, child) {
        final circleFlashPercent =
            _dotIntervals[index].transform(_repeatingController.value);
        final circleColorPercent = sin(pi * circleFlashPercent);

        return Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(widget.flashingCircleDarkColor,
                widget.flashingCircleBrightColor, circleColorPercent),
          ),
        );
      },
    );
  }
}
