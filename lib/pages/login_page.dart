// 📄 lib/pages/login_page.dart (임의 계정 생성 기능 추가 버전)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:in_app_review/in_app_review.dart';
// ⭐ 추가
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/game_server_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  User? _user;
  bool _loading = false;
  String? _error;

  final TextEditingController _nicknameController = TextEditingController();

  // ✅ 서버 닉네임 저장/중복체크에 사용하는 값
  String? _uid;
  String? _email;


  bool get _isSupportedPlatform {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (_isSupportedPlatform) {
      _user = FirebaseAuth.instance.currentUser;

      final current = _user;
      if (current != null) {
        // ✅ 서버 닉네임 저장/체크에 사용할 값 보관
        _uid = current.uid;
        _email = current.email;

        // ✅ 로컬에 저장된 닉네임이 있으면 우선 사용
        _nicknameController.text =
            current.displayName ?? _defaultNicknameFromEmail(current.email);
        SharedPreferences.getInstance().then((prefs) {
          if (!mounted) return;
          final savedNick = (prefs.getString('nickname') ?? '').trim();
          if (savedNick.isNotEmpty) {
            setState(() {
              _nicknameController.text = savedNick;
            });
          }
        });

        // ⭐ 기존 계정도 서버 계좌 보장
        _ensureGameAccount(current.uid, current.displayName ?? "사용자",
            current.email);
      }
    }
  }


  String _defaultNicknameFromEmail(String? email) {
    if (email == null || email.isEmpty) return "사용자";
    return email.split("@").first;
  }
  void _showPolicyDialog({
    required String title,
    required String content,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("닫기"),
          ),
        ],
      ),
    );
  }

  // ⭐ 플레이스토어 리뷰 요청
  Future<void> _requestReview() async {
    final inAppReview = InAppReview.instance;

    try {
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await inAppReview.openStoreListing();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("리뷰 페이지를 열 수 없습니다: $e")),
      );
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

// ⭐ 서버 계좌 보장 함수
  Future<bool> _ensureGameAccount(
      String uid, String nickname, String? email) async {
    try {
      await GameServerApi.registerGameUser(
        uid: uid,
        nickname: nickname,
        email: email,
        mode: "both",
        initialBalance: 100000.0,
      );

      final prefs = await SharedPreferences.getInstance();

      // ✅ 메인에서 표시할 수 있도록 3개 키를 같이 저장
      await prefs.setString("uid", uid);
      await prefs.setString("game_uid", uid);
      await prefs.setString("log_uid", uid);

      // ✅ 로그인/닉네임 화면 재진입 시 표시용
      await prefs.setString("nickname", nickname);
      if (email != null && email.isNotEmpty) {
        await prefs.setString("email", email);
      }

      return true; // ✅ 성공

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("서버 계좌 생성 실패: $e")),
        );
      }
      return false; // ✅ 실패
    }
  }




// ⭐ 신규: 임의(랜덤) 계정 생성 기능
  Future<void> _createRandomAccount() async {
    if (!kDebugMode) return;

    final rand = Random();
    final uid = "guest_${rand.nextInt(99999999)}";
    final nickname = "guest_${rand.nextInt(9999)}";

    final ok = await _ensureGameAccount(uid, nickname, "$nickname@example.com");

    if (!ok) {
      // ✅ 실패했는데도 "완료"가 뜨는 문제 방지
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("임의 계정 생성 실패 (서버/저장 확인 필요)")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("임의 계정 생성 완료: $uid")),
    );

// ⭐ UI에서도 로그인된 것처럼 처리
    setState(() {
      _user = null; // Firebase 로그인 아님
      _nicknameController.text = nickname;
    });

// ✅ 메인으로 돌아가게 (메인이 prefs 다시 읽으면서 우측에 guest_ 표시됨)
    Navigator.pop(context, true);

  }


  // ⭐ 추가: 입력한 닉네임으로 테스트 계정 생성
  Future<void> _createTestAccountWithNickname() async {
    if (!kDebugMode) return;

    final raw = _nicknameController.text.trim();

    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("테스트 닉네임을 입력하세요.")),
      );
      return;
    }

    // uid로 쓰기 안전하게 정리 (공백 제거, 특수문자 일부 제거)
    final safeNick = raw.replaceAll(RegExp(r"\s+"), "_").replaceAll(RegExp(r"[^a-zA-Z0-9가-힣_\-]"), "");
    if (safeNick.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("닉네임에 사용할 수 없는 문자가 포함되어 있습니다.")),
      );
      return;
    }

    final uid = "guest_$safeNick";
    final email = "$safeNick@test.com";

    final ok = await _ensureGameAccount(uid, safeNick, email);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("테스트 계정 생성 실패 (서버/저장 확인 필요)")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("테스트 계정 생성 완료: $safeNick")),
    );

    setState(() {
      _user = null; // Firebase 로그인 아님
      _nicknameController.text = safeNick;
    });

    Navigator.pop(context, true);
  }



  // ------------------- 구글 로그인 -------------------

  Future<void> _signInWithGoogle() async {
    if (!_isSupportedPlatform) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('구글 로그인은 모바일/웹에서만 가능합니다.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred =
      await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;

      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });

      if (user != null) {
        _nicknameController.text =
            user.displayName ?? _defaultNicknameFromEmail(user.email);

        // ⭐ 서버 계좌도 생성/업데이트
        await _ensureGameAccount(
            user.uid,
            user.displayName ??
                _defaultNicknameFromEmail(user.email),
            user.email);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("환영합니다 ${user?.displayName ?? ''} 님!")),
      );

// ✅ 로그인 성공 → 이전 화면으로 복귀
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ------------------- 닉네임 저장 -------------------

  Future<void> _saveNickname() async {
    final user = _user;
    final name = _nicknameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("닉네임을 입력해 주세요.")),
      );
      return;
    }

    final uid = (_uid ?? user?.uid ?? '').trim();
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("uid가 없습니다. 다시 로그인 해주세요.")),
      );
      return;
    }

    try {
      // ✅ 1) 닉네임 중복 체크(본인 uid 제외)
      final available =
      await GameServerApi.checkNickname(nickname: name, uid: uid);
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("이미 사용 중인 닉네임입니다.")),
        );
        return;
      }

      // ✅ 2) 서버에 닉네임 저장
      await GameServerApi.setNickname(uid: uid, nickname: name);

      // ✅ 3) Firebase displayName도 같이 맞춤(있을 때만)
      if (user != null) {
        await user.updateDisplayName(name);
        await user.reload();
        final refreshed = FirebaseAuth.instance.currentUser;
        setState(() {
          _user = refreshed;
        });
      }

      // ✅ 4) 계좌/유저 보장 + 로컬 저장
      await _ensureGameAccount(uid, name, user?.email ?? _email);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nickname', name);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("닉네임 저장 완료")),
      );
    } catch (e) {
      final msg = e.toString();

      // ✅ 10분 제한(429) 한글 안내
      if (msg.contains('429') &&
          (msg.contains('once every 10 minutes') ||
              msg.contains('nickname can be changed once every 10 minutes'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("닉네임은 10분에 한 번만 변경할 수 있습니다.")),
        );
        return;
      }

      // 기본 에러
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("닉네임 저장 실패: $msg")),
      );
    }
  }



  // ------------------- 로그아웃 -------------------

  Future<void> _signOut() async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

// ✅ 로그인 관련 키 전부 삭제
    await prefs.remove("uid");
    await prefs.remove("game_uid");
    await prefs.remove("log_uid");


    setState(() {
      _user = null;
      _nicknameController.clear();
    });
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final nickname = _nicknameController.text;

    return Scaffold(
      appBar: AppBar(
        title: const Text("로그인"),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (user != null) ...[
                CircleAvatar(
                  radius: 32,
                  backgroundImage: user.photoURL != null
                      ? NetworkImage(user.photoURL!)
                      : null,
                  child: user.photoURL == null
                      ? Text(
                    (user.displayName ??
                        _defaultNicknameFromEmail(user.email))
                        .characters
                        .first
                        .toUpperCase(),
                    style: const TextStyle(fontSize: 16),
                  )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  nickname,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  user.email ?? "",
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      labelText: "닉네임",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: 260,
                  child: ElevatedButton.icon(
                    onPressed: _saveNickname,
                    icon: const Icon(Icons.save),
                    label: const Text("닉네임 저장"),
                  ),
                ),
                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text("로그아웃"),
                ),
              ] else ...[
                const Icon(Icons.person_outline,
                    size: 48, color: Colors.teal),
                const SizedBox(height: 16),
                const Text(
                  "로그인하세요.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // ⭐ 구글 로그인 버튼
                SizedBox(
                  width: 260,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: _loading
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : const Icon(Icons.login),
                    label:
                    Text(_loading ? "로그인 중..." : "Google 계정으로 로그인"),
                  ),
                ),
                const SizedBox(height: 16),

                if (kDebugMode) ...[
                  // ✅ 테스트 닉네임 입력
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(
                        labelText: "테스트 닉네임",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ✅ 입력 닉네임으로 테스트 계정 생성 버튼
                  SizedBox(
                    width: 260,
                    child: ElevatedButton.icon(
                      onPressed: _createTestAccountWithNickname,
                      icon: const Icon(Icons.person_add),
                      label: const Text("입력 닉네임으로 테스트 계정 생성"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ✅ 임의 계정 생성 버튼
                  SizedBox(
                    width: 260,
                    child: ElevatedButton.icon(
                      onPressed: _createRandomAccount,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text("임의 계정 생성 (테스트용)"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                )
              ],

              const SizedBox(height: 20),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "본 앱은 가상 투자 및 투자 기록 서비스이며 투자 자문 또는 매수·매도 추천을 제공하지 않습니다.\n"
                      "모든 투자 판단과 책임은 사용자 본인에게 있습니다.\n"
                      "계속 진행하면 이용약관, 개인정보처리방침 및 운영정책에 동의한 것으로 간주됩니다.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: _requestReview,
                    child: const Text("리뷰"),
                  ),
                  TextButton(
                    onPressed: () {
                      _showPolicyDialog(
                        title: "이용약관",
                        content: """
[stockarena 이용약관]

1. 서비스 개요
stockarena는 주식 및 가상자산 관련 매매 기록, 투자 연습, 거래 내역 관리, 랭킹, 토론 기능 등을 제공하는 서비스입니다.
본 앱은 실제 금융 거래를 중개하거나 투자 자문을 제공하지 않습니다.

2. 이용자의 의무
- 타인의 계정을 도용하거나 부정 사용하는 행위
- 허위 정보 입력
- 욕설, 비방, 혐오, 불쾌감을 주는 게시물 작성
- 도배, 광고, 스팸 행위
- 법령에 위반되는 행위
- 서비스 운영을 방해하는 행위

3. 게시물 및 콘텐츠
욕설, 허위 정보, 광고, 불법 콘텐츠 등은 사전 통보 없이 삭제 또는 제한될 수 있습니다.

4. 서비스 이용 제한
약관 위반 시 게시물 삭제, 이용 제한, 계정 차단 등의 조치가 적용될 수 있습니다.

5. 면책사항
본 앱은 투자 기록 및 시뮬레이션용 도구이며,
투자 판단과 책임은 전적으로 이용자 본인에게 있습니다.

문의: stockarena.help@gmail.com
                        """,
                      );
                    },
                    child: const Text("이용약관"),
                  ),
                  TextButton(
                    onPressed: () {
                      _showPolicyDialog(
                        title: "개인정보처리방침",
                        content: """
[stockarena 개인정보처리방침]

1. 수집하는 정보
- 이메일 주소
- 닉네임
- 로그인 식별 정보
- 서비스 이용 기록
- 기기 정보
- 거래 기록 / 토론 글 / 랭킹 기록 등

2. 수집 목적
- 로그인 및 회원 식별
- 거래 기록 저장
- 랭킹 / 토론 기능 제공
- 고객 문의 응대
- 서비스 운영 및 보안 유지

3. 외부 서비스
본 앱은 Firebase Authentication, Firebase Database, Google Play Services 등을 사용할 수 있습니다.

4. 이용자 권리
이용자는 자신의 개인정보에 대해 열람, 수정, 삭제 요청을 할 수 있습니다.

문의: stockarena.help@gmail.com
                        """,
                      );
                    },
                    child: const Text("개인정보처리방침"),
                  ),
                  TextButton(
                    onPressed: () {
                      _showPolicyDialog(
                        title: "운영정책",
                        content: """
[stockarena 커뮤니티 운영정책]

1. 목적
stockarena는 자유로운 의견 공유 공간을 제공하지만,
다른 이용자에게 피해를 주는 행위는 제한될 수 있습니다.

2. 제한되는 행위
- 욕설, 비방, 인신공격, 혐오 표현
- 허위 정보, 사기성 내용, 과도한 투자 선동
- 도배, 광고, 홍보, 스팸
- 불법 콘텐츠
- 반복적인 분쟁 유도 또는 운영 방해

3. 운영 조치
운영자는 위반 정도에 따라
- 게시물 숨김/삭제
- 댓글/토론 기능 제한
- 일정 기간 이용 제한
- 계정 차단
등의 조치를 할 수 있습니다.

4. 투자 관련 주의
토론 및 댓글의 내용은 작성자 개인 의견이며,
stockarena는 정확성, 수익성, 투자 결과를 보장하지 않습니다.

문의: stockarena.help@gmail.com
                        """,
                      );
                    },
                    child: const Text("운영정책"),
                  ),
                  TextButton(
                    onPressed: () {
                      _showPolicyDialog(
                        title: "투자유의사항",
                        content: """
[stockarena 투자유의사항]

1. 본 서비스는 가상 투자 및 투자 기록 관리 기능을 제공하는 서비스입니다.
실제 금융상품의 매매를 중개하거나 투자 자문을 제공하지 않습니다.

2. 앱 내 차트, 가격 정보, 랭킹, 토론, 사용자 의견은 참고용 정보이며,
정확성, 완전성, 수익성을 보장하지 않습니다.

3. 다른 사용자의 매매, 랭킹, 의견, 토론 글을 참고한 투자 판단과 결과에 대한 책임은
전적으로 이용자 본인에게 있습니다.

4. 본 서비스는 특정 종목 또는 자산에 대한 매수·매도 추천이나 수익 보장을 하지 않습니다.

문의: stockarena.help@gmail.com
                        """,
                      );
                    },
                    child: const Text("투자유의사항"),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("닫기"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
