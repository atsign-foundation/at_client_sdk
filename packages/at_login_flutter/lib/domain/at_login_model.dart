class AtLoginObj {
  bool? allowLogin;
  String? atsign;
  String? challenge;
  String? key;
  String? location;
  String? requestorUrl;
  String? requestorLogoUrl;
  bool? validCert;

  AtLoginObj({
    this.allowLogin,
    this.atsign,
    this.challenge,
    this.key,
    this.location,
    this.requestorUrl,
    this.requestorLogoUrl,
    this.validCert,
  });

  Map<String, dynamic> toJson() => {
        'allowLogin': allowLogin,
        'atsign': atsign,
        'challenge': challenge,
        'key': key,
        'location': location,
        'validCert': validCert,
        'requestorUrl': requestorUrl,
        'requestorLogoUrl': requestorLogoUrl,
      };

  factory AtLoginObj.fromJson(Map<String, dynamic> json) {
    return AtLoginObj(
      allowLogin: json['allowLogin'] as bool,
      atsign: json['atsign'] as String,
      challenge: json['challenge'] as String,
      key: json['key'] as String,
      location: json['location'] as String,
      validCert: json['certificate'] as bool,
      requestorLogoUrl: json['requestorLogoUrl'] as String,
      requestorUrl: json['requestorUrl'] as String,
    );
  }
}
