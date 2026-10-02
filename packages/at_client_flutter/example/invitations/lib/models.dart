/// Someone this app knows. A contact made through an invitation takes the
/// invitation's id as its own, on both sides.
class Contact {
  final String name;

  /// Their atSign, once they have one and the invitation is accepted.
  final String? atSign;

  const Contact({required this.name, this.atSign});

  factory Contact.fromJson(Map<String, dynamic> json) =>
      Contact(name: json['name'], atSign: json['atSign']);

  Map<String, dynamic> toJson() => {
    'name': name,
    if (atSign != null) 'atSign': atSign,
  };
}

/// What an invitation shows before it is accepted. It travels in the
/// preview, so anyone holding the link can read it.
class InviteDetails {
  final String inviterName;
  final String message;

  const InviteDetails({required this.inviterName, this.message = ''});

  factory InviteDetails.fromJson(Map<String, dynamic> json) => InviteDetails(
    inviterName: json['inviterName'] ?? '',
    message: json['message'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'inviterName': inviterName,
    'message': message,
  };
}

/// What the invitee tells the inviter when accepting.
class AcceptanceDetails {
  final String name;

  const AcceptanceDetails({required this.name});

  factory AcceptanceDetails.fromJson(Map<String, dynamic> json) =>
      AcceptanceDetails(name: json['name'] ?? '');

  Map<String, dynamic> toJson() => {'name': name};
}

/// The private content an invitation carries: here, a piece of text.
class PrivateContent {
  final String text;

  const PrivateContent(this.text);

  factory PrivateContent.fromJson(Map<String, dynamic> json) =>
      PrivateContent(json['text'] ?? '');

  Map<String, dynamic> toJson() => {'text': text};
}
