import 'package:at_follows_flutter/domain/connection_model.dart';
import 'package:at_follows_flutter/utils/color_constants.dart';
import 'package:at_follows_flutter/utils/custom_textstyles.dart';
import 'package:at_follows_flutter/services/size_config.dart';
import 'package:flutter/material.dart';

//a class to create custom button
class CustomButton extends StatefulWidget {
  final isActive;
  final text;
  final highLightColor;
  final providerStatus;
  final double? height;
  final double width;
  final Function onPressedCallBack;
  final bool showCount;
  final String? count;
  // final highlightColor;
  CustomButton(
      {required this.text,
      required this.onPressedCallBack,
      this.providerStatus,
      textstyle,
      highLightColor,
      this.height,
      this.width = 0.0,
      this.showCount = false,
      this.count,
      this.isActive = false})
      : this.highLightColor = highLightColor ?? ColorConstants.secondary;

  @override
  _CustomButtonState createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  @override
  void initState() {
    super.initState();
  }

  ConnectionProvider connectionProvider = ConnectionProvider();

  @override
  Widget build(BuildContext context) {
    return MaterialButton(
      height: widget.height,
      minWidth: widget.width,
      onPressed: () {
        widget.onPressedCallBack(!widget.isActive);
      },
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5.0.toFont),
          side: BorderSide(color: ColorConstants.borderColor!)),
      color: widget.isActive
          ? ColorConstants.buttonHighLightColor
          : ColorConstants.secondary,
      highlightColor: widget.highLightColor,
      child: widget.showCount
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0.toFont),
              child: Column(
                children: [
                  Text('${widget.count ?? 0}',
                      style: widget.isActive
                          ? CustomTextStyles.fontBold14light
                          : CustomTextStyles.fontBold14primary),
                  Text(
                    widget.text,
                    style: widget.isActive
                        ? CustomTextStyles.fontBold14light
                        : CustomTextStyles.fontBold14primary,
                  ),
                ],
              ),
            )
          : Text(
              widget.text,
              style: widget.isActive
                  ? CustomTextStyles.fontR14light
                  : CustomTextStyles.fontR14primary,
            ),
    );
  }
}
