// 📄 lib/services/auth_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 현재 유저 스트림 (로그인 상태 변경 감시용)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// ✅ 구글 로그인
  Future<UserCredential> signInWithGoogle() async {
    // 1) 구글 로그인 창 열기
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('사용자가 로그인 취소함');
    }

    // 2) 인증 토큰 가져오기
    final GoogleSignInAuthentication googleAuth =
    await googleUser.authentication;

    // 3) Firebase Auth credential 만들기
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // 4) Firebase 쪽으로 로그인
    return await _auth.signInWithCredential(credential);
  }

  /// ✅ 로그아웃 (Firebase + Google 둘 다)
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}
