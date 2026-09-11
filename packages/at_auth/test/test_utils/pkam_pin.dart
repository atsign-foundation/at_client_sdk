/// The one frozen PKAM signature this package's tests pin against, so every
/// path that signs a PKAM challenge is held to the same bytes.

/// The demo key maps are keyed on the emoji atSigns, so PKAM can sign for real
/// with [pkamPinAtSign]'s demo PKAM private key rather than with placeholder
/// material.
const pkamPinAtSign = '@alice🛠';

/// A `from:` challenge naming [pkamPinAtSign], as the atServer issues one.
const pkamPinChallenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581@alice🛠'
    ':c3d345fc-5691-4f90-bc34-17cba31f060f';

/// FROZEN: the base64 PKCS#1 v1.5 SHA-256 signature the `pkam:` verb carries
/// for [pkamPinChallenge] under [pkamPinAtSign]'s demo PKAM private key. The
/// atServer verifies it against the key it holds, so these bytes are a
/// cross-implementation contract rather than an implementation detail: an
/// intended change edits this literal, and that edit is the review.
///
/// Captured with `openssl dgst -sha256 -sign <key> -keyform DER` over the raw
/// challenge bytes, so the expectation does not come from the code it is
/// checking.
const expectedPkamSignature =
    'Y9uoEs+F2k/cZ285RGbPx9yShG5Ea/e0FcYiXZ7MDeO/BFxop7s4c7EHCpvH5x0TEquq'
    '1XY/524q+CLq7JyeA8noCaQZB04T3F7EWZp3GFnad4rX3OwUICb/TM4YDWt+H21eXsKX'
    'LktwSHYqhRcZcil0M2XrT+sqekN1nj0/mRWL09JyTMNxDbfgvndXzBKdHt8t1ihlRdoQ'
    'AnZn16qWrwj9EI0X4WsuNxDEB+J6oPMYUmiVsPGNhZvFjyYqtKuxtQRsWcVc962trwZa'
    'b9jovcMeERuTqOCiUxsER60e1x94AjiAK7V8Rx5+01q3Lp5IVwnn3Ungd5hgMLngHXXg'
    'Uw==';
