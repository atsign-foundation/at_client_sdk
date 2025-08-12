import 'package:at_sync_ui_flutter/at_sync_ui_flutter.dart';
import 'package:flutter/material.dart';

class CustomSyncIndicator extends StatelessWidget {
  CustomSyncIndicator({
    this.child,
    this.size = 15,
    required this.uiStatus,
    Key? key,
  })  : assert(size! >= 45 || child == null,
            'Size must be greater than 45 if child is not null'),
        super(key: key);
  final Widget? child;
  final AtSyncUIStatus? uiStatus;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.loose,
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          height: child != null ? 45 : size,
          width: child != null ? 45 : size,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: child == null ? syncColors(uiStatus) : null,
            border: Border.all(
              color: syncColors(uiStatus),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(2 * size!),
          ),
          child: child,
        ),
      ],
    );
  }

  Color syncColors(AtSyncUIStatus? value) =>
      value == null || value == AtSyncUIStatus.notStarted
          ? Colors.lightBlueAccent
          : value == AtSyncUIStatus.syncing
              ? Colors.yellow[600]!
              : value == AtSyncUIStatus.completed
                  ? Colors.transparent
                  : Colors.red;
}