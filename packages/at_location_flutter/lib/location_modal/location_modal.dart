class LocationModal {
  String? lat, long;
  String? displayName, state, city, postalCode;

  LocationModal({
    this.lat,
    this.long,
    this.displayName,
    this.state,
    this.city,
    this.postalCode,
  });

  LocationModal.fromJson(Map<dynamic, dynamic> ad) {
    lat = ad['position'][0].toString(); // 0th index is latitude
    long = ad['position'][1].toString(); // 1st index is longitude
    displayName = ad['title'].toString();
    displayName = '''${(displayName ?? '')},
${ad['vicinity'].toString().replaceAll('<br/>', ' ')}
    ''';
    city = (ad['vicinity'] ?? '')
        .replaceAll('<br/>', ' '); // [vicinity] gives entire address
  }
}
