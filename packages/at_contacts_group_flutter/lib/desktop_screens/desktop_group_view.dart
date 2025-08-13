import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';

class DesktopGroupView extends StatefulWidget {
  const DesktopGroupView({Key? key}) : super(key: key);
  @override
  _DesktopGroupViewState createState() => _DesktopGroupViewState();
}

class _DesktopGroupViewState extends State<DesktopGroupView> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SizeConfig().screenWidth,
      child: Row(
        children: [
          // Container(
          //   width: SizeConfig().screenWidth / 2 - 35,
          //   child: DesktopGroupList(),
          // ),
          SizedBox(
              width: SizeConfig().screenWidth / 2 - 35,
              child: const Text('Commented')
              // DesktopGroupDetail(),
              )
        ],
      ),
    );
  }
}
