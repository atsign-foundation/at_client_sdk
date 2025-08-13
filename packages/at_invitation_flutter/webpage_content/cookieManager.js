function checkAndWriteCookie() {
    // IMPORTANT: change this value to your app's deeplink
    var iosDeepLink = "atcompany-atmosphere://";
    var androidDeepLink = "https://www.atcompany-atmosphere.com/";

    const urlSearchParams = new URLSearchParams(window.location.search);
    const params = Object.fromEntries(urlSearchParams.entries());
    if (params['key'] != undefined && params['atsign'] != undefined) {
        custom = ((navigator.userAgent.match(/Android/i) == 'Android') ? androidDeepLink : iosDeepLink) + '?key=' + params['key'] + '&atsign=' + params['atsign'];

        var now = new Date();
        var time = now.getTime();
        var expireTime = time + 1000 * 3600;
        now.setTime(expireTime);
        document.cookie = 'inviteKey=' + custom + ';expires=' + now.toGMTString();
    } else {
        var cookieValue = getCookie("inviteKey");
        if (cookieValue) {
            location.href = cookieValue;
        } else {
            console.log("No Cookies...");
            location.href = iosDeepLink;
        }
        // for Android
        // As the script initiated redirection does not work for chrome
        if ((navigator.userAgent.match(/Android/i) == 'Android')) {
            var elemCenter = document.createElement('center');
            var elemA = document.createElement('a');
            elemA.href = cookieValue ? cookieValue : androidDeepLink;
            var text = "Return to app";
            elemA.append(text);
            elemCenter.append(elemA);
            document.body.prepend(elemCenter);
        }
    }
}

function getCookie(name) {
    var re = new RegExp(name + "=([^;]+)");
    var value = re.exec(document.cookie);
    return (value != null) ? unescape(value[1]) : null;
}
