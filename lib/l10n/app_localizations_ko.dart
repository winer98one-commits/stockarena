// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => '투자 게임';

  @override
  String get searchHint => '검색';

  @override
  String get loading => '데이터 불러오는 중...';

  @override
  String get selectSymbol => '검색 후 종목을 선택하세요.';

  @override
  String get search => '검색';

  @override
  String get tradeHistory => '거래내역';

  @override
  String get profit => '수익';

  @override
  String get ranking => '랭킹';

  @override
  String get discussion => '토론';

  @override
  String get tradeLogTab => '매매일지';

  @override
  String get investmentGameTab => '투자 게임';

  @override
  String get favorites => '즐겨찾기';

  @override
  String get current => '현재';

  @override
  String get add => '추가';

  @override
  String get cancel => '취소';

  @override
  String get addFolder => '폴더 추가';

  @override
  String get folderName => '폴더 이름';

  @override
  String moveToFolder(Object name) {
    return '$name 이동';
  }

  @override
  String favoriteAddedSnack(Object name, Object symbol) {
    return '⭐ $name ($symbol) 즐겨찾기에 추가됨';
  }

  @override
  String movedToFolderSnack(Object folder, Object symbol) {
    return '📁 $symbol → $folder 이동';
  }

  @override
  String get login => '로그인';

  @override
  String get logout => '로그아웃';

  @override
  String get loggingIn => '로그인 중...';

  @override
  String get googleLogin => 'Google 계정으로 로그인';

  @override
  String get googleLoginOnlyMobileWeb => '구글 로그인은 모바일/웹에서만 가능합니다.';

  @override
  String get loginGuide => '구글 계정으로 로그인하세요.\n또는 테스트용 계정을 생성할 수 있습니다.';

  @override
  String get nickname => '닉네임';

  @override
  String get saveNickname => '닉네임 저장';

  @override
  String get nicknameSaved => '닉네임 저장 완료';

  @override
  String nicknameSaveFail(Object msg) {
    return '닉네임 저장 실패: $msg';
  }

  @override
  String get nicknameInvalidChars => '닉네임에 사용할 수 없는 문자가 포함되어 있습니다.';

  @override
  String get nicknameAlreadyUsed => '이미 사용 중인 닉네임입니다.';

  @override
  String get nicknameEnter => '닉네임을 입력해 주세요.';

  @override
  String get nicknameChangeLimit => '닉네임은 10분에 한 번만 변경할 수 있습니다.';

  @override
  String get close => '닫기';

  @override
  String get done => '완료';

  @override
  String get user => '사용자';

  @override
  String welcomeUser(Object name) {
    return '환영합니다 $name 님!';
  }

  @override
  String get noUidPleaseRelogin => 'uid가 없습니다. 다시 로그인 해주세요.';

  @override
  String serverAccountCreateFail(Object err) {
    return '서버 계좌 생성 실패: $err';
  }

  @override
  String get createRandomTestAccount => '임의 계정 생성 (테스트용)';

  @override
  String get createRandomFail => '임의 계정 생성 실패 (서버/저장 확인 필요)';

  @override
  String createRandomDone(Object uid) {
    return '임의 계정 생성 완료: $uid';
  }

  @override
  String get createTestAccountWithNickname => '입력 닉네임으로 테스트 계정 생성';

  @override
  String get testNickname => '테스트 닉네임';

  @override
  String get testNicknameHint => '테스트 닉네임을 입력하세요.';

  @override
  String get createTestFail => '테스트 계정 생성 실패 (서버/저장 확인 필요)';

  @override
  String createTestDone(Object nick) {
    return '테스트 계정 생성 완료: $nick';
  }

  @override
  String get rankingTitle => '투자 게임 랭킹';

  @override
  String get uidEmptyCannotLoad => 'UID가 비어있어 조회할 수 없습니다.';

  @override
  String get noRankingData => '랭킹 데이터가 없습니다.';

  @override
  String rankingLoadFail(Object err) {
    return '랭킹 데이터를 불러오지 못했습니다: $err';
  }

  @override
  String get selectSymbolFirst => '먼저 종목을 선택하세요.';

  @override
  String serverError(Object body, Object status) {
    return '서버 오류: $status $body';
  }

  @override
  String profitRateFmt(Object rate) {
    return '수익률 $rate%';
  }

  @override
  String get discussionRules => '토론 규칙';

  @override
  String get alert => '알림';

  @override
  String get confirm => '확인';

  @override
  String get refresh => '새로고침';

  @override
  String get loadingShort => '불러오는 중...';

  @override
  String get noPosts => '아직 글이 없습니다.';

  @override
  String get cannotConnectServer => '서버에 연결할 수 없습니다. (주소/서버상태/CORS/방화벽 확인)';

  @override
  String get unknownError => '알 수 없는 오류가 발생했습니다.';

  @override
  String get loginRequiredNoUid => '로그인 후 이용해주세요. (uid 없음)';

  @override
  String get register => '등록';

  @override
  String get enterContent => '내용을 입력하세요.';

  @override
  String get contentTooLong => '내용은 300자 이하만 가능합니다.';

  @override
  String get linkNotAllowed => '링크는 허용되지 않습니다.';

  @override
  String get writeHint => '토론 글을 입력하세요 (최대 300자)';

  @override
  String get ruleMax300 => '• 300자 이하만 작성 가능';

  @override
  String get ruleNoSpam => '• 너무 자주 작성 금지 (10초 간격 제한)';

  @override
  String get ruleNoLink => '• 링크/URL 입력 금지 (http, https, www, .com 등)';

  @override
  String get ruleNoHate => '• 욕설/비방/혐오 표현 금지 (금칙어 포함)';

  @override
  String rankSuffix(Object rank) {
    return '$rank위';
  }

  @override
  String profitLoadFail(Object err) {
    return '수익 데이터를 불러오지 못했습니다: $err';
  }

  @override
  String get totalProfitSummary => '총 수익 요약';

  @override
  String get initial => '초기';
}
