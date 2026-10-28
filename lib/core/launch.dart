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
