import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/images.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

// ignore: todo
/// TODO:
/// Duplicate GlobalKey detected in widget tree as we now have
/// select contacts on right side and left side we have empty widget
/// and empty widget inturn has nested widgets, so it throws error

class DesktopEmptyGroup extends StatefulWidget {
  final bool createBtnTapped;
  final Function? onCreateBtnTap;

  const DesktopEmptyGroup(this.createBtnTapped, {Key? key, this.onCreateBtnTap})
      : super(key: key);
  @override
  _DesktopEmptyGroupState createState() => _DesktopEmptyGroupState();
}

class _DesktopEmptyGroupState extends State<DesktopEmptyGroup> {
  // bool createBtnTapped = false;
  // List<AtContact?> selectedContactList = [];
  // bool showAddGroupIcon = false, errorOcurred = false;

  // @override
  // void initState() {
  //   try {
  //     super.initState();
  //     GroupService().getAllGroupsDetails();
  //     GroupService().atGroupStream.listen((groupList) {
  //       if (groupList.isNotEmpty) {
  //         showAddGroupIcon = true;
  //       } else {
  //         showAddGroupIcon = false;
  //       }
  //       if (mounted) setState(() {});
  //     });
  //   } catch (e) {
  //     print('Error in init of Group_list $e');
  //     if (mounted) {
  //       setState(() {
  //         errorOcurred = true;
  //       });
  //     }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return _emptyGroup();
    // SizeConfig().init(context);
    // return Container(
    //   width: SizeConfig().screenWidth - TextConstants.SIDEBAR_WIDTH,
    //   color: Color(0xFFF7F7FF),
    //   child: StreamBuilder(
    //     stream: GroupService().atGroupStream,
    //     builder: (BuildContext context, AsyncSnapshot<List<AtGroup>> snapshot) {
    //       if (snapshot.connectionState == ConnectionState.waiting) {
    //         return Center(child: CircularProgressIndicator());
    //       } else {
    //         if (snapshot.hasError) {
    //           return ErrorScreen(onPressed: () {
    //             GroupService().getAllGroupsDetails();
    //           });
    //         } else {
    //           if (snapshot.hasData) {
    //             if (snapshot.data!.isEmpty) {
    //               print('snapshot.data!.isEmpty');
    //               showAddGroupIcon = false;
    //               return createBtnTapped ? nested_navigators() : _emptyGroup();
    //             } else {
    //               print('!snapshot.data!.isEmpty');
    //               return nested_navigators();
    //             }
    //           } else {
    //             return _emptyGroup();
    //           }
    //         }
    //       }
    //     },
    //   ),
    // );
  }

  Widget _emptyGroup() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          AllImages().EMPTY_GROUP,
          width: 181.toWidth,
          height: 181.toWidth,
          fit: BoxFit.cover,
          package: 'at_contacts_group_flutter',
        ),
        SizedBox(
          height: 15.toHeight,
        ),
        Text('No Groups!', style: CustomTextStyles().grey16),
        SizedBox(
          height: 5.toHeight,
        ),
        Text(
          'Would you like to create a group?',
          style: CustomTextStyles().grey16,
        ),
        SizedBox(
          height: 20.toHeight,
        ),
        TextButton(
          onPressed: widget.createBtnTapped
              ? null
              : () {
                  widget.onCreateBtnTap!();
                },
          style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> states) {
              return widget.createBtnTapped
                  ? ColorConstants.dullText
                  : ColorConstants.orangeColor;
            },
          ), fixedSize: WidgetStateProperty.resolveWith<Size>(
            (Set<WidgetState> states) {
              return const Size(160, 45);
            },
          )),
          child: const Text(
            'Create',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

// Container(
//             width: SizeConfig().screenWidth / 2 - 35,
//             child: DesktopNewGroup(),
//           )
