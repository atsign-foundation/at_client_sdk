import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/at_common_flutter.dart';

class Tasks extends StatelessWidget {
  final IconData icon;
  final String task;
  final Function onTap;
  final double angle;
  const Tasks(
      {Key? key,
      required this.task,
      required this.icon,
      required this.onTap,
      this.angle = 0.0})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap as void Function()?,
      child: SizedBox(
        height: 58.toHeight,
        width: 70.toWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: angle,
              child: Icon(
                icon,
                size: 20.toWidth,
                color: AllColors().ORANGE,
              ),
            ),
            Flexible(
              child: Text(
                task,
                style: CustomTextStyles().black12,
                textAlign: TextAlign.center,
              ),
            )
          ],
        ),
      ),
    );
  }
}
