import 'package:aladin/data/push.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Povzetki prometa (functions/index.js → `admini`) smejo na telefon samo, če
/// je prijavljeni zaposleni administrator. Preizkus drži obe strani: da
/// administrator povzetke dobi in da jih nihče drug ne.
class _FakeMessaging implements FirebaseMessaging {
  final topics = <String>{};
  var permission = AuthorizationStatus.authorized;

  @override
  Future<void> subscribeToTopic(String topic) async => topics.add(topic);

  @override
  Future<void> unsubscribeFromTopic(String topic) async => topics.remove(topic);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #requestPermission) {
      const off = AppleNotificationSetting.notSupported;
      return Future.value(NotificationSettings(
        alert: off,
        announcement: off,
        authorizationStatus: permission,
        badge: off,
        carPlay: off,
        lockScreen: off,
        notificationCenter: off,
        showPreviews: AppleShowPreviewSetting.notSupported,
        timeSensitive: off,
        criticalAlert: off,
        sound: off,
        providesAppNotificationSettings: off,
      ));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late _FakeMessaging messaging;
  late PushService push;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = _FakeMessaging();
    push = PushService(messaging);
  });

  test('a worker gets order notifications but never the revenue summaries',
      () async {
    expect(await push.setEnabled(true, isAdmin: false), isTrue);
    expect(messaging.topics, {pushTopic});
  });

  test('an admin gets both topics', () async {
    expect(await push.setEnabled(true, isAdmin: true), isTrue);
    expect(messaging.topics, {pushTopic, adminPushTopic});
  });

  test('turning notifications off leaves no topic behind', () async {
    await push.setEnabled(true, isAdmin: true);
    expect(await push.setEnabled(false, isAdmin: true), isFalse);
    expect(messaging.topics, isEmpty);
  });

  test('denied permission subscribes to nothing', () async {
    messaging.permission = AuthorizationStatus.denied;
    expect(await push.setEnabled(true, isAdmin: true), isFalse);
    expect(messaging.topics, isEmpty);
    expect(await push.isEnabled(), isFalse);
  });

  test('restore follows the CURRENT role: promotion adds, demotion removes',
      () async {
    await push.setEnabled(true, isAdmin: false);

    await push.restore(isAdmin: true);
    expect(messaging.topics, {pushTopic, adminPushTopic});

    await push.restore(isAdmin: false);
    expect(messaging.topics, {pushTopic});
  });

  test('restore does nothing while notifications are switched off', () async {
    await push.restore(isAdmin: true);
    expect(messaging.topics, isEmpty);
  });

  test('signing out drops both topics', () async {
    await push.setEnabled(true, isAdmin: true);
    await push.signOut();
    expect(messaging.topics, isEmpty);
  });
}
