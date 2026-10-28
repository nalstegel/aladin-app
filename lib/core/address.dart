/// Samodejna povezava poštne številke in kraja za Naš prevzem (v3 spec §1).
///
/// Namenoma pokriva samo Ljubljano — večina naročil je od tam, za vse ostalo
/// delavec obe polji vpiše ročno.
const String _ljubljanaPostalCode = '1000';
const String _ljubljanaCity = 'Ljubljana';

/// Kraj, ki ga predlagamo za vpisano poštno številko, ali null, če je ne
/// poznamo.
String? cityForPostalCode(String postalCode) {
  return postalCode.trim() == _ljubljanaPostalCode ? _ljubljanaCity : null;
}

/// Poštna številka, ki jo predlagamo za vpisani kraj, ali null, če ga ne
/// poznamo.
String? postalCodeForCity(String city) {
  return city.trim().toLowerCase() == _ljubljanaCity.toLowerCase()
      ? _ljubljanaPostalCode
      : null;
}
