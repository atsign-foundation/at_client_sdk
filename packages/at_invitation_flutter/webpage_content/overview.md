# **at_invitation_widget**

This Flutter package is designed to invite one's contacts who are not on atPlatform. This can also be used in case the inviter is not aware of the contact's atSign.

### Overview
This package provides a function called `shareAndinvite` in the app. Using this, a link is generated which can be shared with the invitee via SMS or email. To avoid misuse, a passcode is also sent along with it.
When the invitee taps on this link, the webpage provided is loaded with two url parameters - `key` and `atsign`. The javascript `cookieManager.js` parses the url for parameters and writes the information in a cookie.
The web page can contain links to download and install the app.
Once the app is installed and run, the app needs to load the webpage. Here, the same javascript `cookieManager.js` reads the cookie stored earlier and passes the information contained therein to the app using deep link.
The package also provides a function `fetchInviteData`. A call to this function with the data and authorising it with the passcode, completes the flow to inform the inviter to share the intended data though the app.

### System design

![User flow](./userFlow.png?raw=true "Title")

![Website flow](./websiteFlow.png?raw=true "Title")