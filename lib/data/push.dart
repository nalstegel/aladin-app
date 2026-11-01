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

/// Dnevni, tedenski in mesečni povzetek vsebujejo promet in cene, ki jih
/// zaposleni v aplikaciji ne vidijo (Statistika je samo za administratorje),
/// zato gredo na ločeno temo, na katero so naročeni samo administratorji.
const adminPushTopic = 'admini';

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
  Future<bool> setEnabled(bool enabled, {required bool isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      await _unsubscribe();
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

    await _subscribe(isAdmin: isAdmin);
    await prefs.setBool(_prefsKey, true);
    return true;
  }

  /// Ob zagonu obnovimo naročnino, če je bila vklopljena. Vlogo preverimo
  /// vsakič znova: administrator, ki je bil medtem degradiran, mora nehati
  /// dobivati promet, povišan zaposleni pa ga začeti.
  Future<void> restore({required bool isAdmin}) async {
    if (!await isEnabled()) return;
    await _subscribe(isAdmin: isAdmin);
  }

  /// Ob odjavi telefon ne sme več dobivati obvestil o naročilih — in ne
  /// povzetkov prometa.
  Future<void> signOut() => _unsubscribe();

  Future<void> _subscribe({required bool isAdmin}) async {
    await _safe(() => _messaging.subscribeToTopic(pushTopic));
    await _safe(() => isAdmin
        ? _messaging.subscribeToTopic(adminPushTopic)
        : _messaging.unsubscribeFromTopic(adminPushTopic));
  }

  Future<void> _unsubscribe() async {
    await _safe(() => _messaging.unsubscribeFromTopic(pushTopic));
    await _safe(() => _messaging.unsubscribeFromTopic(adminPushTopic));
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
