import 'dart:typed_data';

/// This is a custom Circle Avatar with a border of secondary color
/// [size] is set to [50] as default

import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class CustomCircleAvatar extends StatelessWidget {
  final String? image;
  final double size;
  final bool nonAsset;
  final Uint8List? byteImage;

  const CustomCircleAvatar(
      {Key? key,
      this.image,
      this.size = 50,
      this.nonAsset = false,
      this.byteImage})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Container(
      height: size.toFont,
      width: size.toFont,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size.toWidth),
      ),
      child: CircleAvatar(
        radius: (size - 5).toFont,
        backgroundColor: Colors.transparent,
        backgroundImage:
            nonAsset ? Image.memory(byteImage!).image : AssetImage(image!),
      ),
    );
  }
}
