import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Potisna obvestila.
///
/// Vsi zaposleni dobijo ista obvestila, zato uporabljamo **temo** (topic) in
/// ne seznama žetonov po napravah: brez tega bi bilo treba žetone hraniti,
/// osveževati in čistiti, koristi pa nobene — naročila niso dodeljena
/// posameznim zaposlenim.
const pushTopic = 'zaposleni';

class PushService {
  PushService(this._messaging);

  final FirebaseMessaging _messaging;

  static const _prefsKey = 'push_enabled';

  /// Ali je zaposleni obvestila vklopil na TEM telefonu. Tako kot prijava je
  /// to nastavitev naprave — Ana si obvestil ne more izklopiti Marku.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Vklop zahteva dovoljenje uporabnika. Če ga ne da, ostane izklopljeno —
  /// vrnjena vrednost pove dejansko stanje, ne želenega.
  Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      await _safe(() => _messaging.unsubscribeFromTopic(pushTopic));
      await prefs.setBool(_prefsKey, false);
      return false;
    }

    final settings = await _messaging.requestPermission();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!granted) {
      await prefs.setBool(_prefsKey, false);
      return false;
    }

    await _safe(() => _messaging.subscribeToTopic(pushTopic));
    await prefs.setBool(_prefsKey, true);
    return true;
  }

  /// Ob zagonu obnovimo naročnino, če je bila vklopljena.
  Future<void> restore() async {
    if (!await isEnabled()) return;
    await _safe(() => _messaging.subscribeToTopic(pushTopic));
  }

  /// Ob odjavi telefon ne sme več dobivati obvestil o naročilih.
  Future<void> signOut() async {
    await _safe(() => _messaging.unsubscribeFromTopic(pushTopic));
  }

  /// Obvestila ne smejo podreti aplikacije. Brez omrežja ali brez nastavljene
  /// storitve naročanje na temo vrže napako — delo v obratu se zaradi tega
  /// ne sme ustaviti.
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Potisna obvestila niso na voljo: $e');
    }
  }
}

final pushServiceProvider =
    Provider<PushService>((ref) => PushService(FirebaseMessaging.instance));

final pushEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(pushServiceProvider).isEnabled(),
);
