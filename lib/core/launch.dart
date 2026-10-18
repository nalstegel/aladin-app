import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

/// Odpre klicanje za številko stranke. Vrne false, če naprava tega ne zna.
Future<bool> callPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return Future.value(false);
  return launchUrl(Uri(scheme: 'tel', path: digits));
}

/// Odpre naslov v zemljevidih / navigaciji — na iPhonu v Apple Maps, drugje
/// v Google Maps (aplikacija, če je nameščena, sicer brskalnik).
Future<bool> openMaps(String address) {
  final query = address.trim();
  if (query.isEmpty) return Future.value(false);
  final uri = Platform.isIOS
      ? Uri.https('maps.apple.com', '/', {'q': query})
      : Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': query,
        });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Največ postankov na eni poti v Google Maps (cilj + 9 vmesnih).
const maxRouteStops = 10;

/// Odpre pot z več postanki (današnji naslovi iz Dostav). Začne na trenutni
/// lokaciji. Google Maps URL prenese največ [maxRouteStops] naslovov — klicatelj
/// je odgovoren, da jih ne pošlje več.
Future<bool> openMapsRoute(List<String> addresses) {
  final stops = addresses
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .take(maxRouteStops)
      .toList();
  if (stops.isEmpty) return Future.value(false);
  final params = <String, String>{
    'api': '1',
    'destination': stops.last,
    'travelmode': 'driving',
    if (stops.length > 1) 'waypoints': stops.sublist(0, stops.length - 1).join('|'),
  };
  return launchUrl(
    Uri.https('www.google.com', '/maps/dir/', params),
    mode: LaunchMode.externalApplication,
  );
}
