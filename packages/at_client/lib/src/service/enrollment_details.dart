class EnrollmentDetails {
  late Map<String, dynamic> namespace;

  static EnrollmentDetails fromJSON(Map<String, dynamic> json) {
    return EnrollmentDetails()..namespace = json['namespace'];
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = {};
    map['namespace'] = namespace;
    return map;
  }
}
