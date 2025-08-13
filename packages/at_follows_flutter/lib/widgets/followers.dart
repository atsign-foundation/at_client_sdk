import 'package:at_follows_flutter/domain/atsign.dart';
import 'package:at_follows_flutter/domain/connection_model.dart';
import 'package:at_follows_flutter/exceptions/at_exception_handler.dart';
import 'package:at_follows_flutter/services/connections_service.dart';
import 'package:at_follows_flutter/utils/color_constants.dart';
import 'package:at_follows_flutter/utils/custom_textstyles.dart';
import 'package:at_follows_flutter/utils/strings.dart';
import 'package:at_follows_flutter/widgets/custom_button.dart';
import 'package:at_follows_flutter/widgets/web_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:at_follows_flutter/services/size_config.dart';
import 'package:provider/provider.dart';
import 'package:at_utils/at_logger.dart';

// a widget to show followers
class Followers extends StatefulWidget {
  final String? searchText;
  final bool isFollowing;
  final Function? count;
  Followers({
    this.searchText,
    this.isFollowing = false,
    this.count,
  });
  @override
  _FollowersState createState() => _FollowersState();
}

class _FollowersState extends State<Followers> {
  List<Atsign>? atsignsList = [];
  ConnectionsService _connectionsService = ConnectionsService();
  final _logger = AtSignLogger('Follows Widget');
  bool _isDialogOpen = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(builder: (context, provider, _) {
      _logger.info('provider status is ${provider.status}');
      if (provider.status == Status.loading) {
        return Padding(
          padding: EdgeInsets.only(top: SizeConfig().screenHeight * 0.15),
          child: Center(
            child: Column(
              children: [
                Container(
                  height: 50.toHeight,
                  width: 50.toHeight,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color?>(
                        ColorConstants.buttonHighLightColor),
                  ),
                ),
                SizedBox(height: 5.0.toHeight),
              ],
            ),
          ),
        );
      } else if (provider.status == Status.done) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          widget.count!();
        });
        if (_connectionsService.followerAtsign != null) {
          _followAtsign(context);
        }
        //  else if (_connectionsService.followAtsign != null) {
        //   _followAtsign(context, isFollow: true);
        // }
        atsignsList = widget.isFollowing
            ? provider.followingList
            : provider.followersList;
        if (atsignsList!.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                  widget.isFollowing
                      ? Strings.noFollowing
                      : Strings.noFollowers,
                  style: CustomTextStyles.fontR14primary),
            ],
          );
        }
        var tempAtsignList = [...atsignsList!];
        if (widget.searchText!.isNotEmpty) {
          tempAtsignList.retainWhere((atsign) {
            return atsign.title!
                .toUpperCase()
                .contains(widget.searchText!.toUpperCase());
          });
        }
        return Expanded(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(
                    widget.isFollowing
                        ? Strings.privateFollowingList
                        : Strings.privateFollowersList,
                    style: CustomTextStyles.fontBold14primary),
                value: widget.isFollowing
                    ? provider.connectionslistStatus.isFollowingPrivate
                    : provider.connectionslistStatus.isFollowersPrivate,
                onChanged: (value) {
                  provider.changeListStatus(widget.isFollowing, value);
                },
                inactiveTrackColor: ColorConstants.inactiveTrackColor,
                inactiveThumbColor: ColorConstants.inactiveThumbColor,
                activeTrackColor: ColorConstants.activeTrackColor,
                activeColor: ColorConstants.activeColor,
              ),
              SizedBox(height: 10.toHeight),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: 26,
                  itemBuilder: (_, alphabetIndex) {
                    List<Atsign> sortedListWithAlphabet = [];
                    String currentAlphabet =
                        String.fromCharCode(alphabetIndex + 65).toUpperCase();

                    tempAtsignList.forEach((atsign) {
                      var index = atsign.title!.indexOf(RegExp('[A-Z]|[a-z]'));
                      if (atsign.title![index].toUpperCase() ==
                          currentAlphabet) {
                        if (widget.searchText != null &&
                            atsign.title!
                                .toUpperCase()
                                .contains(widget.searchText!.toUpperCase())) {
                          sortedListWithAlphabet.add(atsign);
                        }
                      }
                    });
                    if (sortedListWithAlphabet.isEmpty) {
                      return Container();
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(currentAlphabet,
                                style: CustomTextStyles.fontR14primary),
                            Expanded(
                              child: Divider(
                                thickness: 0.8,
                                color: ColorConstants.borderColor,
                              ),
                            )
                          ],
                        ),
                        // SizedBox(
                        //   height: 2.toHeight,
                        // ),
                        ListView.separated(
                            physics: NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemBuilder: (_, index) {
                              Atsign currentAtsign =
                                  sortedListWithAlphabet[index];
                              return Padding(
                                padding:
                                    EdgeInsets.symmetric(vertical: 8.0.toFont),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => WebViewScreen(
                                                url:
                                                    '${Strings.directoryUrl}/${currentAtsign.title}',
                                                title: Strings
                                                    .publicContentAppbarTitle)));
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: ColorConstants.fillColor,
                                    radius: 20.toFont,
                                    child: currentAtsign.profilePicture != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                                20.toFont),
                                            child: Image.memory(
                                              currentAtsign.profilePicture,
                                            ),
                                          )
                                        : Icon(Icons.person_outline,
                                            color: Colors.black,
                                            size: 25.toFont),
                                  ),
                                  title: Text(currentAtsign.title!,
                                      style: CustomTextStyles.fontR16primary),
                                  subtitle: currentAtsign.subtitle != null
                                      ? Text(currentAtsign.subtitle!,
                                          style:
                                              CustomTextStyles.fontR14primary)
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CustomButton(
                                          height: 35.toHeight,
                                          // width: 70.toWidth,
                                          // width: 150.toWidth,
                                          isActive: !currentAtsign.isFollowing!,
                                          onPressedCallBack: (value) async {
                                            if (value) {
                                              provider.unfollow(
                                                  currentAtsign.title);
                                            } else {
                                              provider
                                                  .follow(currentAtsign.title);
                                            }
                                            sortedListWithAlphabet[index]
                                                .isFollowing = !value;
                                            setState(() {});
                                          },
                                          text: currentAtsign.isFollowing!
                                              ? Strings.Unfollow
                                              : Strings.Follow),
                                      // IconButton(
                                      //     iconSize: 20.toFont,
                                      //     icon: Icon(Icons.delete),
                                      //     onPressed: () async {
                                      //       await provider
                                      //           .delete(currentAtsign.title);
                                      //     }),
                                    ],
                                  ),
                                ),
                              );
                            },
                            separatorBuilder: (_, index) => Divider(
                                  thickness: 0.8,
                                  color: ColorConstants.borderColor,
                                ),
                            itemCount: sortedListWithAlphabet.length),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      } else if (provider.status == Status.error) {
        return AtExceptionHandler().handle(provider.error, context);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await provider.getAtsignsList(isFollowing: widget.isFollowing);
        });
        return SizedBox();
      }
    });
  }

  _followAtsign(BuildContext context) {
    var atsign = ConnectionsService().followerAtsign;
    bool exists = ConnectionProvider().containsFollowing(atsign);
    if (exists || _isDialogOpen) {
      _connectionsService.followerAtsign = null;

      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _isDialogOpen = true;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
                  content: Text(Strings.followBackDescription(atsign),
                      textAlign: TextAlign.center,
                      style: CustomTextStyles.fontR14dark),
                  actions: [
                    CustomButton(
                      width: SizeConfig().screenWidth! * 0.23,
                      isActive: false,
                      onPressedCallBack: (value) {
                        _connectionsService.followerAtsign = null;
                        _isDialogOpen = false;
                        // widget.isDialog();
                        Navigator.pop(context);
                      },
                      text: Strings.cancel,
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.17),
                    CustomButton(
                      width: SizeConfig().screenWidth! * 0.23,
                      isActive: true,
                      onPressedCallBack: (value) async {
                        _connectionsService.followerAtsign = null;
                        _isDialogOpen = false;
                        // widget.isDialog();
                        Navigator.pop(context);
                        await ConnectionProvider().follow(atsign);
                      },
                      text: Strings.followBack,
                    ),
                  ]));
    });
  }
}
