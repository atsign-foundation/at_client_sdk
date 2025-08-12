import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class DraggableSymbol extends StatelessWidget {
  const DraggableSymbol({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4.toHeight,
      width: SizeConfig().screenWidth,
      alignment: Alignment.center,
      child: Container(
          width: 60.toWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7.toHeight),
            color: AllColors().DARK_GREY,
          )),
    );
  }
}
