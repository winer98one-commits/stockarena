// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Investment Game';

  @override
  String get searchHint => 'Search symbol (Stock / Coin / ETF / Index)';

  @override
  String get loading => 'Loading data...';

  @override
  String get selectSymbol => 'Select a symbol after search.';

  @override
  String get search => 'Search';

  @override
  String get tradeHistory => 'Trade';

  @override
  String get profit => 'Profit';

  @override
  String get ranking => 'Ranking';

  @override
  String get discussion => 'Discussion';

  @override
  String get tradeLogTab => 'Trade Log';

  @override
  String get investmentGameTab => 'Investment Game';

  @override
  String get favorites => 'Favorites';

  @override
  String get current => 'Current';

  @override
  String get add => 'Add';

  @override
  String get cancel => 'Cancel';

  @override
  String get addFolder => 'Add Folder';

  @override
  String get folderName => 'Folder name';

  @override
  String moveToFolder(Object name) {
    return 'Move to $name';
  }

  @override
  String favoriteAddedSnack(Object name, Object symbol) {
    return '⭐ Added to favorites: $name ($symbol)';
  }

  @override
  String movedToFolderSnack(Object folder, Object symbol) {
    return '📁 Moved: $symbol → $folder';
  }

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get loggingIn => 'Logging in...';

  @override
  String get googleLogin => 'Sign in with Google';

  @override
  String get googleLoginOnlyMobileWeb =>
      'Google sign-in is available only on mobile/web.';

  @override
  String get loginGuide => 'Sign in with Google.\nOr create a test account.';

  @override
  String get nickname => 'Nickname';

  @override
  String get saveNickname => 'Save nickname';

  @override
  String get nicknameSaved => 'Nickname saved';

  @override
  String nicknameSaveFail(Object msg) {
    return 'Failed to save nickname: $msg';
  }

  @override
  String get nicknameInvalidChars => 'Nickname contains invalid characters.';

  @override
  String get nicknameAlreadyUsed => 'This nickname is already in use.';

  @override
  String get nicknameEnter => 'Please enter a nickname.';

  @override
  String get nicknameChangeLimit =>
      'You can change your nickname only once every 10 minutes.';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get user => 'User';

  @override
  String welcomeUser(Object name) {
    return 'Welcome $name!';
  }

  @override
  String get noUidPleaseRelogin => 'No uid. Please sign in again.';

  @override
  String serverAccountCreateFail(Object err) {
    return 'Failed to create server account: $err';
  }

  @override
  String get createRandomTestAccount => 'Create random test account';

  @override
  String get createRandomFail =>
      'Failed to create random account (check server/storage)';

  @override
  String createRandomDone(Object uid) {
    return 'Random account created: $uid';
  }

  @override
  String get createTestAccountWithNickname =>
      'Create test account with nickname';

  @override
  String get testNickname => 'Test nickname';

  @override
  String get testNicknameHint => 'Enter a test nickname.';

  @override
  String get createTestFail =>
      'Failed to create test account (check server/storage)';

  @override
  String createTestDone(Object nick) {
    return 'Test account created: $nick';
  }

  @override
  String get rankingTitle => 'Investment Game Ranking';

  @override
  String get uidEmptyCannotLoad => 'UID is empty. Cannot load.';

  @override
  String get noRankingData => 'No ranking data.';

  @override
  String rankingLoadFail(Object err) {
    return 'Failed to load ranking: $err';
  }

  @override
  String get selectSymbolFirst => 'Please select a symbol first.';

  @override
  String serverError(Object body, Object status) {
    return 'Server error: $status $body';
  }

  @override
  String profitRateFmt(Object rate) {
    return 'Profit rate $rate%';
  }

  @override
  String get discussionRules => 'Discussion Rules';

  @override
  String get alert => 'Notice';

  @override
  String get confirm => 'OK';

  @override
  String get refresh => 'Refresh';

  @override
  String get loadingShort => 'Loading...';

  @override
  String get noPosts => 'No posts yet.';

  @override
  String get cannotConnectServer =>
      'Cannot connect to server. (URL/status/CORS/firewall)';

  @override
  String get unknownError => 'An unknown error occurred.';

  @override
  String get loginRequiredNoUid => 'Please sign in. (no uid)';

  @override
  String get register => 'Post';

  @override
  String get enterContent => 'Please enter content.';

  @override
  String get contentTooLong => 'Content must be 300 characters or less.';

  @override
  String get linkNotAllowed => 'Links are not allowed.';

  @override
  String get writeHint => 'Write a post (max 300 chars)';

  @override
  String get ruleMax300 => '• Max 300 characters';

  @override
  String get ruleNoSpam => '• No spamming (10s cooldown)';

  @override
  String get ruleNoLink => '• No links/URLs (http, https, www, .com etc.)';

  @override
  String get ruleNoHate => '• No hate/abuse/harassment';

  @override
  String rankSuffix(Object rank) {
    return '#$rank';
  }

  @override
  String profitLoadFail(Object err) {
    return 'Failed to load profit data: $err';
  }

  @override
  String get totalProfitSummary => 'Total Profit Summary';

  @override
  String get initial => 'Initial';
}
