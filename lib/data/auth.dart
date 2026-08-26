import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Napaka prijave s sporočilom, ki ga lahko pokažemo zaposlenemu.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Kdo je prijavljen na tej napravi. Firebase sejo hrani sam, zato ostane
/// zaposleni prijavljen tudi po zaprtju aplikacije.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(firebaseAuthProvider)),
);

class AuthService {
  const AuthService(this._auth);

  final FirebaseAuth _auth;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  /// Firebase vrne angleške kode — zaposlenim pokažemo slovensko razlago.
  static String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'Neveljaven e-naslov.',
        'user-disabled' => 'Ta račun je onemogočen. Obrni se na vodjo.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Napačen e-naslov ali geslo.',
        'too-many-requests' =>
          'Preveč poskusov. Počakaj nekaj minut in poskusi znova.',
        'network-request-failed' =>
          'Ni povezave. Preveri internet in poskusi znova.',
        _ => 'Prijava ni uspela (${e.code}).',
      };
}
