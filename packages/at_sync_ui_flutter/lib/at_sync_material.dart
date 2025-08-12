import 'package:flutter/material.dart';

import 'at_sync_cupertino.dart' as cupertino;
import 'at_sync_progress_indicator.dart';

const double _kDefaultIndicatorRadius = 10.0;

const Color _kDefaultActiveTickColor = Color(0xFFf4533d);

class AtSyncIndicator extends StatelessWidget {
  /// If non-null, the value of this progress indicator.
  ///
  /// A value of 0.0 means no progress and 1.0 means that progress is complete.
  ///
  /// If null, this progress indicator is indeterminate, which means the
  /// indicator displays a predetermined animation that does not indicate how
  /// much actual progress is being made.
  final double? value;

  /// The progress indicator's background color.
  ///
  /// It is up to the subclass to implement this in whatever way makes sense
  /// for the given use case. See the subclass documentation for details.
  final Color? backgroundColor;

  /// {@template flutter.progress_indicator.ProgressIndicator.color}
  /// The progress indicator's color.
  ///
  /// This is only used if [ProgressIndicator.valueColor] is null.
  /// If [ProgressIndicator.color] is also null, then the ambient
  /// [ProgressIndicatorThemeData.color] will be used. If that
  /// is null then the current theme's [ColorScheme.primary] will
  /// be used by default.
  /// {@endtemplate}
  final Color? color;

  /// Radius of the spinner widget.
  ///
  /// Defaults to 10px. Must be positive and cannot be null.
  final double radius;

  const AtSyncIndicator({
    Key? key,
    this.value,
    this.backgroundColor,
    this.color,
    this.radius = _kDefaultIndicatorRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Padding(
        padding: EdgeInsets.all(radius / _kDefaultIndicatorRadius),
        child: CircularProgressIndicator(
          value: value,
          backgroundColor: backgroundColor ?? (color ?? _kDefaultActiveTickColor).withAlpha(46),
          color: (color ?? _kDefaultActiveTickColor).withAlpha(146),
          strokeWidth: radius / _kDefaultIndicatorRadius * 2,
        ),
      ),
    );
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

class AtSyncLinearProgressIndicator extends AtSyncProgressIndicator {
  /// {@template flutter.material.LinearProgressIndicator.minHeight}
  /// The minimum height of the line used to draw the linear indicator.
  ///
  /// If [LinearProgressIndicator.minHeight] is null then it will use the
  /// ambient [ProgressIndicatorThemeData.linearMinHeight]. If that is null
  /// it will use 4dp.
  /// {@endtemplate}
  final double? minHeight;

  const AtSyncLinearProgressIndicator({
    Key? key,
    Color? backgroundColor,
    Color? color,
    double? value,
    this.minHeight,
  }) : super(
          key: key,
          backgroundColor: backgroundColor,
          color: color,
          value: value,
        );

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      backgroundColor: backgroundColor ?? (color ?? _kDefaultActiveTickColor).withAlpha(47),
      color: color ?? _kDefaultActiveTickColor,
      value: value,
      minHeight: minHeight ?? 4,
    );
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

  final Color? indicatorColor;

  final TextStyle? textStyle;

  final Widget? child;

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
        ),
      ],
    );
  }
}

class AtSyncDialog {
  final AtSyncStyle syncStyle;

  /// [_progress] Listens to the value of progress.
  final ValueNotifier<double?> _progress = ValueNotifier<double?>(null);

  /// [_message] Listens to the msg value.
  final ValueNotifier<String> _message = ValueNotifier<String>('');

  /// [_dialogIsOpen] Shows whether the dialog is open.
  bool _dialogIsOpen = false;

  /// [_context] Required to show the alert.
  late BuildContext _context;

  Color? indicatorColor;
  Color? backgroundColor;
  TextStyle? messageStyle;
  TextStyle? valueStyle;

  AtSyncDialog({
    required BuildContext context,
    this.syncStyle = AtSyncStyle.material,
    this.indicatorColor,
    this.backgroundColor,
    this.messageStyle,
    this.valueStyle,
  }) {
    _context = context;
  }

  /// [update] Pass the new value to this method to update the status.
  void update({required double? value, String? message}) {
    _progress.value = value;
    if (message != null) _message.value = message;
  }

  /// [close] Closes the progress dialog.
  void close() {
    if (_dialogIsOpen) {
      Navigator.pop(_context);
      _dialogIsOpen = false;
    }
  }

  ///[isOpen] Returns whether the dialog box is open.
  bool isOpen() {
    return _dialogIsOpen;
  }

  /// [barrierDismissible] Determines whether the dialog closes when the back button or screen is clicked. Default: false
  show({
    String message = '',
    bool barrierDismissible = false,
  }) {
    _dialogIsOpen = true;
    _message.value = message;
    return showDialog(
      barrierDismissible: barrierDismissible,
      context: _context,
      builder: (context) => PopScope(
        child: AlertDialog(
          content: ValueListenableBuilder<double?>(
            valueListenable: _progress,
            builder: (BuildContext context, double? value, Widget? child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      syncStyle == AtSyncStyle.material
                          ? AtSyncIndicator(
                              radius: 16,
                              value: value,
                              color: indicatorColor,
                            )
                          : cupertino.AtSyncIndicator(
                              radius: 16,
                              value: value,
                              color: indicatorColor,
                            ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 15.0,
                            top: 8.0,
                            bottom: 8.0,
                          ),
                          child: Text(
                            _message.value,
                            overflow: TextOverflow.ellipsis,
                            style: messageStyle ??
                                const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Visibility(
                    visible: _progress.value != null,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        '${((_progress.value ?? 0) * 100).toInt()}%',
                        style: valueStyle ?? const TextStyle(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // ignore: deprecated_member_use
        onPopInvoked: (didPop) => Future.value(
          barrierDismissible,
        ),
      ),
    );
  }
}

class AtSyncSnackBar {
  final AtSyncStyle syncStyle;

  /// [_progress] Listens to the value of progress.
  final ValueNotifier<double?> _progress = ValueNotifier<double?>(null);

  /// [_message] Listens to the msg value.
  final ValueNotifier<String> _message = ValueNotifier<String>('');

  /// [_dialogIsOpen] Shows whether the dialog is open.
  final bool _dialogIsOpen = false;

  /// [_context] Required to show the alert.
  late BuildContext _context;

  Color? indicatorColor;
  Color? backgroundColor;
  TextStyle? textStyle;

  AtSyncSnackBar({
    required context,
    this.syncStyle = AtSyncStyle.material,
    this.indicatorColor,
    this.backgroundColor,
    this.textStyle,
  }) {
    _context = context;
  }

  /// [update] Pass the new value to this method to update the status.
  void update({required double? value, String? message}) {
    _progress.value = value;
    if (message != null) _message.value = message;
  }

  ///[isOpen] Returns whether the dialog box is open.
  bool isOpen() {
    return _dialogIsOpen;
  }

  void show({
    String message = '',
  }) {
    _message.value = message;
    ScaffoldMessenger.of(_context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 365),
        backgroundColor: backgroundColor,
        content: ValueListenableBuilder<double?>(
          valueListenable: _progress,
          builder: (BuildContext context, double? value, Widget? child) {
            return Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: syncStyle == AtSyncStyle.material
                      ? AtSyncIndicator(
                          value: value,
                          color: indicatorColor,
                        )
                      : cupertino.AtSyncIndicator(
                          value: value,
                          color: indicatorColor,
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  _message.value,
                  style: textStyle,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  ///[dismiss] Dismiss the snack bar.
  void dismiss() {
    ScaffoldMessenger.of(_context).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
  }
}
