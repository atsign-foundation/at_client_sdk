import 'package:at_follows_flutter/services/connections_service.dart';

class Atsign {
  String? title;
  dynamic profilePicture;
  String? subtitle;
  bool? isFollowing;

  bool _isValid(String? value) {
    return value != null && value != '' && value != 'null';
  }

  setData(AtFollowsValue followsValue) {
    switch (followsValue.atKey.key) {
      case PublicData.image:
      case PublicData.imagePersona:
        profilePicture = followsValue.value;
        break;
      case PublicData.firstname:
      case PublicData.firstnamePersona:
        subtitle = _isValid(followsValue.value) ? followsValue.value + ' ' : '';
        break;
      case PublicData.lastname:
      case PublicData.lastnamePersona:
        subtitle = _isValid(followsValue.value)
            ? subtitle! + followsValue.value
            : subtitle;
        break;
      default:
        break;
    }
  }

  Atsign({
    this.title,
    this.isFollowing,
    this.subtitle,
    this.profilePicture,
  });

  factory Atsign.fromJson(Map<String, dynamic> json) {
    return Atsign(
        title: json['title'] as String?,
        subtitle: json['subtitle'] as String?,
        isFollowing: json['isFollowing'] as bool?,
        profilePicture: json['profilePicture'] as dynamic);
  }
}

class PublicData {
  static const String image = 'image.wavi';
  static const String firstname = 'firstname.wavi';
  static const String lastname = 'lastname.wavi';

  static const String imagePersona = 'image.persona';
  static const String firstnamePersona = 'firstname.persona';
  static const String lastnamePersona = 'lastname.persona';

  static List<String> list = [image, firstname, lastname];

  static Map<String, String> personaMap = {
    image: imagePersona,
    firstname: firstnamePersona,
    lastname: lastnamePersona
  };
}
