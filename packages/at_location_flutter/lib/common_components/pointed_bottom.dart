import 'package:flutter/material.dart';

/// Builds a pointed bottom widget
Widget pointedBottom({Color? color}) {
  return ClipPath(
    clipper: const ShapeBorderClipper(
      shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40),
              bottomRight: Radius.circular(40))),
    ),
    child: Container(
      height: 10,
      width: 10,
      color: color ?? Colors.white,
      alignment: Alignment.center,
      child: const SizedBox(),
    ),
  );
}
