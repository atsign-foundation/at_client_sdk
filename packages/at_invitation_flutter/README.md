<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_invitation_flutter)](https://pub.dev/packages/at_invitation_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview

The at_invitation_flutter package is for Flutter developers who want to share
data and invite contacts using SMS or email to the atPlatform.


This open source package is written in Dart, supports Flutter and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity
- Ability to send an invite to people not on the apps built on atPlatform

We call giving people control of access to their data “flipping the internet”
and you can learn more about how it works by reading this
[overview](https://atsign.dev/docs/overview/).

## Get started

There are three options to get started using this package:

### 1. Quick start - generate a skeleton app with at_app

This package includes a working sample application in the
[Example](https://github.com/atsign-foundation/at_widgets/tree/trunk/at_invitation_flutter/example)
directory that you can use to create a personalized copy using
`at_app create` in four commands:

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run `flutter pub global activate` once
2. Use `at_app.bat` for Windows

### 2. Clone it from GitHub

Feel free to fork a copy of the source from the
[GitHub repo](https://github.com/atsign-foundation/at_widgets).
The example code contained there is the same as the template that is used by
at_app above.

```sh
git clone https://github.com/atsign-foundation/at_widgets.git
```

### 3. Manually add the package to a project

Instructions on how to manually add this package to you project can be found
on pub.dev [here](https://pub.dev/packages/at_invitation_flutter/install).

## How it works

### Setup
### Initialising:

It is expected that the app will first create an AtClientService instance
and authenticate an atsign.

The invitation service needs to be initialised with the `AtClientService`
instance, current atsign, a global navigator key and a url of web page to use
for launching and redirection.

```
initializeInvitationService(
        navkey: scaffoldKey,
        atClientInstance: clientSdkService.atClientServiceInstance?.atClient,
        currentAtSign: activeAtSign,
        webPage: 'https://xxxx',
        rootDomain: MixedConstants.ROOT_DOMAIN);
```

The app also needs to handle deep links and handle incoming link with
parameters.
The [uni_links](https://pub.dev/packages/uni_links) package can be used for
this.

### Webpage requirements

A webpage with app information like store links will be required. It also
needs to have the javascript functions provided in this
[file](https://github.com/atsign-foundation/at_widgets/tree/trunk/at_invitation_flutter/webpage_content/cookieManager.js).
The function `checkAndWriteCookie` needs to be called on the `onLoad` event
of the webpage.

### Caveats

- This will not work if the the user disables cookies in browser.
- In Android, Chrome browser does not support automatic redirection back to
app. User will have to tap on the link at top of the page to return to the app.
  
### Usage

### Share an invite

```
onPressed: () 
{
  shareAndInvite(context, 'welcome');
}
```

### Fetch an invite

```
fetchInviteData(context, queryParameters['key'] ?? '',
              queryParameters['atsign'] ?? '');
```


## Open source usage and contributions

This is open source code, so feel free to use it as is, suggest changes
or enhancements or create your own version. See
[CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md)
for detailed guidance on how to setup tools, tests and make a pull request.
