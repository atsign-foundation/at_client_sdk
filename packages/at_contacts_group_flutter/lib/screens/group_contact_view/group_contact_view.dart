// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_flutter/utils/text_strings.dart';
import 'package:at_contacts_flutter/widgets/custom_search_field.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/add_contacts_group_dialog.dart';
import 'package:at_contacts_group_flutter/widgets/circular_contacts.dart';
import 'package:at_contacts_group_flutter/widgets/contacts_selction_bottom_sheet.dart';
import 'package:at_contacts_group_flutter/widgets/custom_list_tile.dart';
import 'package:at_contacts_group_flutter/widgets/horizontal_circular_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// This widget gives a screen view for displaying contacts and group details
// ignore: must_be_immutable
class GroupContactView extends StatefulWidget {
  /// Boolean flag to set view to show contacts
  final bool showContacts;

  /// Boolean flag to set view to show groups
  final bool showGroups;

  /// Boolean flag to set view to show single selection
  final bool singleSelection;

  /// Boolean flag to set view as selection screen
  final bool asSelectionScreen;

  final bool isDesktop;
  Function(List<GroupContactsModel?>?)? onBackArrowTap;
  Function? onDoneTap;

  /// Callback to get the list of selected contacts back to the app
  final ValueChanged<List<GroupContactsModel?>>? selectedList;

  /// When contacts are tapped, the selected list is sent to app
  final ValueChanged<List<GroupContactsModel?>>? onContactsTap;

  /// to show already selected contacts.
  final List<GroupContactsModel>? contactSelectedHistory;

  GroupContactView(
      {Key? key,
      this.showContacts = false,
      this.showGroups = false,
      this.singleSelection = false,
      this.asSelectionScreen = true,
      this.selectedList,
      this.isDesktop = false,
      this.onBackArrowTap,
      this.onDoneTap,
      this.contactSelectedHistory,
      this.onContactsTap})
      : super(key: key);
  @override
  _GroupContactViewState createState() => _GroupContactViewState();
}

class _GroupContactViewState extends State<GroupContactView> {
  /// Instance of group service
  late GroupService _groupService;

  /// Text from the search field
  String searchText = '';

  /// Boolean indicator of blocking action in progress
  bool blockingContact = false;

  /// List to hold the last saved contacts of a group
  List<GroupContactsModel?> unmodifiedSelectedGroupContacts = [];

  /// Instance of contact service
  late ContactService _contactService;

  /// Boolean indicator of deleting action in progress
  bool deletingContact = false;
  ContactTabs contactTabs = ContactTabs.ALL;

  @override
  void initState() {
    _groupService = GroupService();
    _contactService = ContactService();
    _groupService.fetchGroupsAndContacts(isDesktop: widget.isDesktop);
    unmodifiedSelectedGroupContacts = List.from(_groupService.selectedGroupContacts);

    if (widget.contactSelectedHistory != null) {
      _groupService.selectedGroupContacts = [...widget.contactSelectedHistory!];
    }

    super.initState();
  }

  List<AtContact> selectedList = [];
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      bottomSheet: (widget.singleSelection)
          ? Container(
              height: 0,
            )
          : (widget.asSelectionScreen)
              ? ContactSelectionBottomSheet(
                  onPressed: () {
                    if (widget.isDesktop) {
                      widget.onDoneTap!();
                      _groupService.selectedGroupContacts = [];
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  selectedList: (s) {
                    if (widget.selectedList != null) {
                      widget.selectedList!(s);
                    }
                  },
                  isDesktop: widget.isDesktop,
                )
              : Container(
                  height: 0,
                ),
      appBar: CustomAppBar(
        isDesktop: widget.isDesktop,
        showTitle: true,
        titleText: 'Contacts',
        leadingIcon: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.black,
          ),
          onPressed: () {
            if (!widget.isDesktop) {
              Navigator.pop(context);
            }

            if (widget.onBackArrowTap != null) {
              widget.onBackArrowTap!(_groupService.selectedGroupContacts);
            }
          },
          tooltip: 'Back',
          padding: EdgeInsets.zero,
        ),
        showBackButton: false,
        showLeadingIcon: true,
        showTrailingIcon: true,
        trailingIcon: const Icon(
          Icons.add,
          color: Colors.black,
          semanticLabel: 'Add contact',
        ),
        onTrailingIconPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddContactDialog(),
          );
        },
      ),
      body: Container(
        padding: EdgeInsets.only(left: 16.toHeight, right: 16.toHeight, bottom: 16.toHeight),
        height: double.infinity,
        child: ListView(
          children: [
            widget.isDesktop
                ? Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: contactTabs == ContactTabs.FAVS
                              ? ColorConstants.orangeColor
                              : ColorConstants.fadedGreyBackground,
                          borderRadius: BorderRadius.circular(30.toWidth),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              contactTabs = ContactTabs.FAVS;
                            });
                          },
                          child: Text('Favourites',
                              style: contactTabs == ContactTabs.FAVS
                                  ? const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.normal,
                                    )
                                  : null),
                        ),
                      ),
                      SizedBox(width: 15.toHeight),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: contactTabs == ContactTabs.ALL
                              ? ColorConstants.orangeColor
                              : ColorConstants.fadedGreyBackground,
                          borderRadius: BorderRadius.circular(30.toWidth),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              contactTabs = ContactTabs.ALL;
                            });
                          },
                          child: Text('All Members',
                              style: contactTabs == ContactTabs.ALL
                                  ? const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.normal,
                                    )
                                  : null),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(),
            SizedBox(height: widget.isDesktop ? 20.toHeight : 0),
            ContactSearchField(
              TextStrings().searchContact,
              (text) => setState(() {
                searchText = text;
              }),
            ),
            SizedBox(
              height: 15.toHeight,
            ),
            (widget.asSelectionScreen)
                ? (widget.singleSelection)
                    ? Container()
                    : HorizontalCircularList(onContactsTap: widget.onContactsTap)
                : Container(),
            StreamBuilder<List<GroupContactsModel?>>(
                stream: _groupService.allContactsStream,
                initialData: _groupService.allContacts,
                builder: (context, snapshot) {
                  if ((snapshot.connectionState == ConnectionState.waiting)) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  } else {
                    if ((snapshot.data == null || snapshot.data!.isEmpty)) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            TextStrings().noContacts,
                            style: CustomTextStyles.primaryBold16,
                          ),
                          const SizedBox(height: 20.0),
                          CustomButton(
                            fontColor: AllColors().WHITE,
                            buttonColor: AllColors().ORANGE,
                            buttonText: 'Add',
                            height: 40.toHeight,
                            width: 115.toWidth,
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => const AddContactDialog(),
                              );
                            },
                          ),
                        ],
                      );
                    } else {
                      // filtering contacts and groups
                      var _filteredList = <GroupContactsModel?>[];
                      _filteredList = getAllContactList(snapshot.data ?? []);

                      if (contactTabs == ContactTabs.FAVS) {
                        _filteredList = filterFavContacts(_filteredList);
                      }

                      if (_filteredList.isEmpty) {
                        return Center(
                          child: Text(
                            TextStrings().noContactsFound,
                            style: TextStyle(
                              fontSize: 15.toFont,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        );
                      }

                      // renders contacts according to the initial alphabet
                      return ListView.builder(
                        padding: EdgeInsets.only(bottom: 80.toHeight),
                        itemCount: 27,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, alphabetIndex) {
                          var contactsForAlphabet = <GroupContactsModel?>[];
                          var currentChar = String.fromCharCode(alphabetIndex + 65).toUpperCase();

                          if (alphabetIndex == 26) {
                            currentChar = 'Others';
                          }

                          contactsForAlphabet = getContactsForAlphabets(
                            _filteredList,
                            currentChar,
                            alphabetIndex,
                          );

                          if (_filteredList.isEmpty) {
                            return Center(
                              child: Text(TextStrings().noContactsFound),
                            );
                          }

                          if (contactsForAlphabet.isEmpty) {
                            return Container();
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  Text(
                                    currentChar,
                                    style: TextStyle(
                                      color: AllColors().BLUE_TEXT,
                                      fontSize: 16.toFont,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 4.toWidth),
                                  Expanded(
                                    child: Divider(
                                      color: AllColors().DIVIDER_COLOR.withValues(alpha: 0.2),
                                      height: 1.toHeight,
                                    ),
                                  ),
                                ],
                              ),
                              contactListBuilder(contactsForAlphabet)
                            ],
                          );
                        },
                      );
                    }
                  }
                })
          ],
        ),
      ),
    );
  }

  Widget contactListBuilder(
    List<GroupContactsModel?> contactsForAlphabet,
  ) {
    return ListView.separated(
        itemCount: contactsForAlphabet.length,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        separatorBuilder: (context, _) => Divider(
              color: AllColors().DIVIDER_COLOR.withValues(alpha: 0.2),
              height: 1.toHeight,
            ),
        itemBuilder: (context, index) {
          return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                child: (contactsForAlphabet[index]!.contact != null)
                    ? Slidable(
                        endActionPane: ActionPane(
                          motion: const ScrollMotion(),
                          children: [
                            SlidableAction(
                              label: TextStrings().block,
                              backgroundColor: ColorConstants.inputFieldColor,
                              icon: Icons.block,
                              onPressed: (_context) async {
                                blockUnblockContact(contactsForAlphabet[index]!.contact!);
                              },
                            ),
                            SlidableAction(
                              label: TextStrings().delete,
                              backgroundColor: Colors.red,
                              icon: Icons.delete,
                              onPressed: (_context) async {
                                deleteAtSign(contactsForAlphabet[index]!.contact!);
                              },
                            )
                          ],
                        ),
                        child: CustomListTile(
                          key: UniqueKey(),
                          onTap: () {},
                          asSelectionTile: widget.asSelectionScreen,
                          selectSingle: widget.singleSelection,
                          item: contactsForAlphabet[index],
                          selectedList: (s) {
                            widget.selectedList!(s);
                          },
                          onTrailingPressed: () {
                            if (contactsForAlphabet[index]!.contact != null) {
                              Navigator.pop(context);

                              _groupService.addGroupContact(contactsForAlphabet[index]);
                              widget.selectedList!(GroupService().selectedGroupContacts);
                            }
                          },
                        ),
                      )
                    : CustomListTile(
                        key: UniqueKey(),
                        onTap: () {},
                        asSelectionTile: widget.asSelectionScreen,
                        selectSingle: widget.singleSelection,
                        item: contactsForAlphabet[index],
                        selectedList: (s) {
                          widget.selectedList!(s);
                        },
                        onTrailingPressed: () {
                          if (contactsForAlphabet[index]!.group != null) {
                            Navigator.pop(context);

                            _groupService.addGroupContact(contactsForAlphabet[index]);
                            widget.selectedList!(GroupService().selectedGroupContacts);
                          }
                        },
                      ),
              ));
        });
  }

  Widget gridViewContactList(List<GroupContactsModel?> contactsForAlphabet, BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: SizeConfig().isTablet(context) ? 4 : 3,
          childAspectRatio: 1 / (SizeConfig().isTablet(context) ? 1.2 : 1.3)),
      shrinkWrap: true,
      itemCount: contactsForAlphabet.length,
      itemBuilder: (context, alphabetIndex) {
        return CircularContacts(
          asSelectionTile: widget.asSelectionScreen,
          selectSingle: widget.singleSelection,
          selectedList: (s) {
            widget.selectedList!(s);
          },
          onTap: () {
            if (contactsForAlphabet[alphabetIndex]!.group != null) {
              Navigator.pop(context);
              _groupService.addGroupContact(contactsForAlphabet[alphabetIndex]);
              widget.selectedList!(GroupService().selectedGroupContacts);
            }
          },
          onLongPressed: () {
            showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                clipBehavior: Clip.antiAliasWithSaveLayer,
                builder: (builder) {
                  return Container(
                    height: 200.0,
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Delete'),
                            onTap: () {
                              deleteAtSign(
                                contactsForAlphabet[alphabetIndex]!.contact!,
                                closeBottomSheet: true,
                              );
                            },
                            leading: const Icon(Icons.delete),
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('Block'),
                            onTap: () {
                              blockUnblockContact(
                                contactsForAlphabet[alphabetIndex]!.contact!,
                                closeBottomSheet: true,
                              );
                            },
                            leading: const Icon(Icons.block),
                          )
                        ],
                      ),
                    ),
                  );
                });
          },
          onCrossPressed: () {
            if (contactsForAlphabet[alphabetIndex]!.group != null) {
              Navigator.pop(context);
              _groupService.addGroupContact(contactsForAlphabet[alphabetIndex]);
              widget.selectedList!(GroupService().selectedGroupContacts);
            }
          },
          groupContact: contactsForAlphabet[alphabetIndex],
        );
      },
    );
  }

  blockUnblockContact(AtContact contact, {bool closeBottomSheet = false}) async {
    setState(() {
      blockingContact = true;
    });
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Center(
          child: Text(TextStrings().blockContact),
        ),
        content: SizedBox(
          height: 100.toHeight,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    var _res = await _contactService.blockUnblockContact(contact: contact, blockAction: true);
    await _groupService.fetchGroupsAndContacts();
    setState(() {
      blockingContact = true;
      Navigator.pop(context);
    });

    if (_res && closeBottomSheet) {
      if (mounted) {
        /// to close bottomsheet
        Navigator.pop(context);
      }
    }
  }

  deleteAtSign(AtContact contact, {bool closeBottomSheet = false}) async {
    setState(() {
      deletingContact = true;
    });
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Center(
          child: Text(TextStrings().deleteContact),
        ),
        content: SizedBox(
          height: 100.toHeight,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    var _res = await _contactService.deleteAtSign(atSign: contact.atSign!);
    if (_res) {
      await _groupService.removeContact(contact.atSign!);
    }
    setState(() {
      deletingContact = false;
      Navigator.pop(context);
    });

    if (_res && closeBottomSheet) {
      if (mounted) {
        /// to close bottomsheet
        Navigator.pop(context);
      }
    }
  }

// creates a list of contacts by merging atsigns and groups.
  List<GroupContactsModel?> getAllContactList(List<GroupContactsModel?> allGroupContactData) {
    var _filteredList = <GroupContactsModel?>[];
    for (var c in allGroupContactData) {
      if (widget.showContacts &&
          c!.contact != null &&
          c.contact!.atSign.toString().toUpperCase().contains(searchText.toUpperCase())) {
        _filteredList.add(c);
      }
      if (widget.showGroups &&
          c!.group != null &&
          c.group!.displayName != null &&
          c.group!.displayName!.toUpperCase().contains(searchText.toUpperCase())) {
        _filteredList.add(c);
      }
    }

    return _filteredList;
  }

  List<GroupContactsModel?> filterFavContacts(List<GroupContactsModel?> _filteredList) {
    _filteredList.removeWhere((groupContact) {
      if (groupContact != null && groupContact.contact != null) {
        return groupContact.contact!.favourite == false;
      } else if (groupContact != null && groupContact.contact == null) {
        return true;
      } else {
        return false;
      }
    });

    return _filteredList;
  }

  /// returns list of atsigns, that matches with [currentChar] in [_filteredList]
  List<GroupContactsModel?> getContactsForAlphabets(
      List<GroupContactsModel?> _filteredList, String currentChar, int alphabetIndex) {
    var contactsForAlphabet = <GroupContactsModel?>[];

    /// contacts, groups that does not starts with alphabets
    if (alphabetIndex == 26) {
      for (var c in _filteredList) {
        if (widget.showContacts &&
            c!.contact != null &&
            !RegExp(r'^[a-z]+$').hasMatch(
              c.contact!.atSign![1].toLowerCase(),
            )) {
          contactsForAlphabet.add(c);
        }
      }
      for (var c in _filteredList) {
        if (widget.showGroups &&
            c!.group != null &&
            !RegExp(r'^[a-z]+$').hasMatch(
              c.group!.displayName![0].toLowerCase(),
            )) {
          contactsForAlphabet.add(c);
        }
      }
    } else {
      for (var c in _filteredList) {
        if (widget.showContacts && c!.contact != null && c.contact?.atSign![1].toUpperCase() == currentChar) {
          contactsForAlphabet.add(c);
        }
      }
      for (var c in _filteredList) {
        if (widget.showGroups && c!.group != null && c.group?.displayName![0].toUpperCase() == currentChar) {
          contactsForAlphabet.add(c);
        }
      }
    }

    return contactsForAlphabet;
  }
}
