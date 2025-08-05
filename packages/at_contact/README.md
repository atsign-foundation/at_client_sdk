# at_contact

<!---
Adding the atPlatform logos gives a nice look for your readme
-->
<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

<!---
Add a badge bar for your package by replacing at_contact below with
your package name below and at_libraries with the name of the repo
-->

[![pub package](https://img.shields.io/pub/v/at_contact)](https://pub.dev/packages/at_contact) [![pub points](https://img.shields.io/pub/points/at_contact?logo=dart)](https://pub.dev/packages/at_contact/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

<!--- this is a table version
| [![pub package](https://img.shields.io/pub/v/at_contact)](https://pub.dev/packages/at_contact) | [![pub points](https://badges.bar/at_contact/pub%20points)](https://pub.dev/packages/at_contact/score) | [![build status](https://github.com/atsign-foundation/at_libraries/actions/workflows/at_libraries.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_libraries/actions/workflows/at_libraries.yaml) | [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)
|------|------|------|------|------| 
-->
## Overview
<!---
## Who is this for?
The README should be addressed to somebody who's never seen this before.
But also don't assume that they're a novice.
-->
The at_contact package is for Flutter developers who would like to persist contacts in their atPlatform application. The at_contact library provides features to add, update, and delete contacts on the atPlatform.

<!---
Give some context and state the intent - we welcome contributions - we want
pull requests and to hear about issues. Include the boilerplate language
below to add some context to atPlatform packages 
-->
This open source package is written in Dart, supports Flutter and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data “flipping the internet”
and you can learn more about how it works by reading this
[overview](https://atsign.dev/docs/overview/).

<!---
Does this package publish to pub.dev or similar? This README will be the
first thing that developers see there and should be written such that it
lets them quickly assess if it fits their need.
-->
## Get started
There are three options to get started using this package.

<!---
If the package has a template that at_app uses to generate a skeleton app,
that is the quickest way for a developer to assess it and get going with
their app.
-->
<!-- ### 1. Quick start - generate a skeleton app with at_app
This package includes a working sample application in the
[Example](./example) directory that you can use to create a personalized
copy using ```at_app create``` in four commands.

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run ```flutter pub global activate``` once
2. Use ```at_app.bat``` for Windows -->


<!---
Cloning the repo and example app from GitHub is the next option for a
developer to get started.
-->
### 1. Clone it from GitHub
<!---
Make sure to edit the link below to refer to your package repo.
-->
Feel free to fork a copy of the source from the [GitHub repo](https://github.com/atsign-foundation/at_libraries).

```sh
$ git clone https://github.com/YOUR-USERNAME/YOUR-REPOSITORY
```

<!---
The last option is to use the traditionaL instructions for adding the package to a project which can be found on pub.dev. 
Please be sure to replace the package name in the url below the right one for this package.
-->
### 2. Manually add the package to a project

Instructions on how to manually add this package to you project can be found on pub.dev [here](https://pub.dev/packages/at_client/install).

<!---
Include an explanation on how to setup and use the package
-->
## How it works

<!---
Add details on how to setup the package
-->
### Setup

```sh
$ dart pub add at_contact

```
### Usage

- Create an instance of `AtContactsImpl`, We make use of `AtClientManager` for `AtClient` to be passed.

```dart
// Create an instance of AtClient.
AtClient atClientInstance = AtClientManager.getInstance().atClient;

// Create an instance of AtContactsImpl.
// It takes 2 positional arguments called AtClient and atSign.
// One optional argument called regexType.
AtContactsImpl _atContact = AtContactsImpl(atClientInstance, atClientInstance.getCurrentAtSign());
```

#### Contacts

- If the user wants to add a contact, call `add()` function from the `_atContact` instance. Provide the contact details to `add()` function.

```dart

Future<void> _addContact() async {
    // Pass the user input data to respective fields of AtContact.
    AtContact contact = AtContact()
    // Pass the user atSign here
    ..atSign = atSign
    ..createdOn = DateTime.now()
    // Pass this value if you want to make the contact your favourite.
    ..favourite = _isFavouriteSelected
    // Contact type can be - Individual / Institute / Other
    ..type = ContactType.Individual;
    bool isContactAdded = await _atContact.add(contact);
    print(isContactAdded ? 'Contact added successfully' : 'Failed to add contact');
}
```

- If user wants to get the data of a contact, call `get()` function by passing the user's atSign as the positional argument.

```dart
AtContact? userContact;

@override
Future<void> _getContactDetails() async {
    // Optionally pass the atKeys.
    AtContact? _contact = await _atContact.get(atSign);
    if(_contact == null){
        print("Failed to fetch contact data.");
    } else {
        // Assign the fetched contact value to userContact.
        // And use the value accordingly in the UI.
        setState(() => userContact = _contact);
    }
}
```

- If user wants to delete a contact, Call `deleteContact()` or `delete()` function.

- You can implement deleting a contact functionality using either of the functions.

  - If you use `deleteContact()` function, It needs the user's contact as a positional parameter.

  - If you use `delete()` function, It needs just the atSign of the user's contact. And it can be fetched from the user contact itself.

  - Let us see the both implementations.

```dart
/// Using `delete()` function.
Future<void> _deleteContact(String _atSign) async {
    if(_atSign == null || _atSign.isEmpty){
        print("AtSign was't passed or empty.");
    } else {
        bool _isContactDeleted = await _atContact.delete(_atSign);
        print(_isContactDeleted ? 'Contact deleted successfully' : 'Failed to delete contact.');
    }
}
```

```dart
/// Using `deleteContact()` function.
Future<void> _deleteContact(AtContact _contact) async {
    bool _isContactDeleted = await _atContact.deleteContact(_contact);
    print(_isContactDeleted ? 'Contact deleted successfully' : 'Failed to delete contact.');
}
```

- Show the list of the user's contacts. Then call the `listContacts()` function.

```dart
/// In Contacts list screen, call the `listContacts()`.
List<AtContact> contactsList = await _atContact.listContacts();

// Use this contactsList in the UI part and render the data as you wish.
// Or use FutureBuilder and ListView to show the contact data as a list.
```

- If the user wants to list out their favorite contacts, Then call `listFavoriteContacts()` function.

```dart
Future<void> _listFavoriteContacts() async {
    List<AtContact> _favContactsList = await _atContact.listFavoriteContacts();
    if(_favContactsList.isEmpty){
        print("No favorite contacts found");
    } else {
        setState(() => favContactsList = _favContactsList);
    }
}
```

#### Groups

- So far we have looked into contacts, Now let us know how `AtGroup`s to be used.

- If the user wants to create a group, Then call `createGroup()` function where it take a `AtGroup` as a positional argument.

```dart
// Pass the user input data to respective fields of AtGroup.
AtGroup myGroup = AtGroup('The atPlatform team')
    ..createdBy = _myAtSign
    ..createdOn = DateTime.now()
    ..description = 'Team with awesome spirit'
    ..updatedOn = DateTime.now()
    ..groupId = 'T@PT101'
    ..displayName = 'at_contact team';
Future<void> _createGroup(AtGroup group) async {
    AtGroup? myGroup = await _atContact.createGroup(group);
    if(myGroup == null){
        print('Failed to create group')
    } else {
        print(group.id + ' has been created successfully');
    }
}
```

- If the user wants to update a group, Then call `updateGroup()` function where it take a `AtGroup` as a positional argument.

```dart
// Pass the user input data to respective fields of AtGroup.
AtGroup myGroup = AtGroup('The atPlatform team')
    ..createdBy = _myAtSign
    ..createdOn = DateTime.now()
    ..description = 'Team with awesome spirit'
    ..updatedOn = DateTime.now()
    ..groupId = 'T@PT101'
    ..displayName = 'at_contact team';
Future<void> _updateGroup(AtGroup group) async {
    try{
        AtGroup? myGroup = await _atContact.updateGroup(group);
        if(myGroup == null){
            print('Failed to create group')
        } else {
            print(group.id + ' has been created successfully');
        }
    } catch(e){
        if(e is GroupNotExistsException){
            print('Group not exists. Please create the group first.');
        } else {
            print('Failed to update group');
        }
    }
}
```

- If the user wants to get the details about group, Then call `getGroup()` function with `groupID` as positional argument.

```dart
String myGroupId = 'T@PT101';

Future<void> _getGroup(String groupId) async {
    AtGroup? myGroup = await _atContact.getGroup(groupName);
    if(myGroup == null){
        print('Failed to get group details')
    } else {
        print('Group Name: ${myGroup.groupName}\n'
        'Group ID : ${myGroup.groupId}\n'
        'Created by : ${myGroup.createdBy}\n'
        'Created on : ${myGroup.createdOn}');
    }
}
```

- If the user wants to delete the group, Then call `deleteGroup()` function with `AtGroup` as positional argument.

```dart
Future<void> _deleteGroup(AtGroup groupName) async {
    AtGroup? _myGroup = await _atContact.getGroup(groupName);
    if(_myGroup == null){
        print('Failed to get group details');
    } else {
        bool _isGroupDeleted = await _atContact.deleteGroup(_myGroup);
        print(_isGroupDeleted ? _myGroup.groupName + ' group deleted' : 'Failed to delete group');
    }
}
```

- If user wants to get the list of group names, Then call `listGroupNames()` function.

```dart
Future<void> _listGroupNames() async {
    List<String?> _groupNames = await _atContact.listGroupNames();
    if(_groupNames.isEmpty){
        print('No groups found');
    } else {
        // Iterate through the list and print names 
        for(String _groupName in _groupNames){
            print(_groupName);
        }
    }
}
```

- If user wants to get the list of group names, Then call `listGroupIds()` function.

```dart
Future<void> _listGroupIds() async {
    List<String?> _groupIds = await _atContact.listGroupIds();
    if(_groupIds == null){
        print('No groups found');
    } else {
        // Iterate through the list and print ids 
        for(String _groupId in _groupIds){
            print(_groupId);
        }
    }
}
```

- If user wants to add someone to the group, then call `addMembers()` function. This function needs `Set<AtContact>` and `AtGroup` as positional arguments.

```dart
Set<AtContact> selectedContacts = <AtContact>{};

for(String _atSign in selectedAtSignsList){
    AtContact? _fetchedContact = await _atContact.get(_atSign);
    if(_fetchedContact != null){
        selectedContacts.add(_fetchedContact);
    } else{
        print('Failed to get contact for $_atSign');
    }
}
// Get your group details if you have the group id
AtGroup? _myGroup = await _atContact.getGroup(myGroupID);

Future<void> _addMembers(Set<AtContact> contacts, AtGroup group) async {
    bool _isMembersAdded = await _atContact.addMembers(contacts, group);
    print(_isMembersAdded ? 'Members added to the group' : 'Failed to add members to the group');
}
```

- If a user wants to delete a contact from the group , Then call `deleteMembers()` function.

```dart
Set<AtContact> selectedContacts = <AtContact>{};

for(String _atSign in selectedAtSignsList){
    AtContact? _fetchedContact = await _atContact.get(_atSign);
    if(_fetchedContact != null){
        selectedContacts.add(_fetchedContact);
    } else{
        print('Failed to get contact for $_atSign');
    }
}
AtGroup? _myGroup = await _atContact.getGroup(myGroupID);

Future<void> _deleteMembers(Set<AtContact> contacts, AtGroup group) async {
    bool _isMembersRemoved = await _atContact.deleteMembers(contacts, group);
    print(_isMembersRemoved ? 'Member removed from the group' : 'Failed to remove member from the group')
}
```

- To check if the user is a member of the group you are looking for, Then call `isMember()` function.

```dart
AtContact? _userContact = await _atContact.get(atSign);
bool isAMember = await _atContact.isMember(_userContact, myGroup);
print(atSign + ' is ${isAMember ? '' : 'not'} a member of ' + myGroup.groupName); 
// @colin is a member of The atPlatform team 
// @somerandomatsign is not a member of The atPlatform team
```

For more information, please see the API documentation listed on pub.dev.

<!---
If we have any pages for these docs on atsign.dev site, it would be 
good to add links.(optional)
-->
### Additional content

- We have developed some realtime Applications using this library called [@mosphere-pro](https://atsign.com/apps/atmosphere-pro/), [@buzz](https://atsign.com/apps/buzz/), [@rrive (Google play store)](https://play.google.com/store/apps/details?id=com.atsign.arrive) / [@rrive (App Store)](https://apps.apple.com/in/app/rrive/id1542050548).

- Flutter implementation of this library can be found in [at_contacts_flutter](https://pub.dev/packages/at_contacts_flutter) package.
<!---
You should include language like below if you would like others to contribute
to your package.
-->

## Open source usage and contributions
This is  open source code, so feel free to use it as is, suggest changes or 
enhancements or create your own version. See [CONTRIBUTING.md](CONTRIBUTING.md) 
for detailed guidance on how to setup tools, tests and make a pull request.

<!---
Have we correctly acknowledged the work of others (and their Trademarks etc.)
where appropriate (per the conditions of their LICENSE?
-->
<!-- ## Acknowledgement/attribution -->

<!---
Who created this?  
Do they have complete GitHub profiles?  
How can they be contacted?  
Who is going to respond to pull requests?  
-->
<!-- ## Maintainers -->

<!---
## Checklist

- [ ] Writing and style
Does the writing flow, with proper grammar and correct spelling?

- [ ] SEO
Always keep in mind that developers will often use search to find solutions
to their needs. Make sure and add in terms that will help get this package to
the top of the search results for google, pub.dev and medium.com as a minimum.

- [ ] Links
Are the links to external resources correct?
Are the links to other parts of the project correct
(beware stuff carried over from previous repos where the
project might have lived during earlier development)?

- [ ] LICENSE
Which LICENSE are we using?  
Is the LICENSE(.md) file present?  
Does it have the correct dates, legal entities etc.?
-->
