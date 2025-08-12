import 'package:flutter/widgets.dart';

enum AtSyncStyle {
  material,
  cupertino,
}

/// A base class for material design progress indicators.
///
/// This widget cannot be instantiated directly. For a linear progress
/// indicator, see [LinearProgressIndicator]. For a circular progress indicator,
/// see [CircularProgressIndicator].
///
/// See also:
///
///  * <https://material.io/components/progress-indicators>
abstract class AtSyncProgressIndicator extends StatelessWidget {
  /// Creates a progress indicator.
  ///
  /// {@template flutter.material.ProgressIndicator.ProgressIndicator}
  /// The [value] argument can either be null for an indeterminate
  /// progress indicator, or non-null for a determinate progress
  /// indicator.
  ///
  /// ## Accessibility
  ///
  /// The [semanticsLabel] can be used to identify the purpose of this progress
  /// bar for screen reading software. The [semanticsValue] property may be used
  /// for determinate progress indicators to indicate how much progress has been made.
  /// {@endtemplate}
  const AtSyncProgressIndicator({
    Key? key,
    this.value,
    this.backgroundColor,
    this.color,
  }) : super(key: key);

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
}
