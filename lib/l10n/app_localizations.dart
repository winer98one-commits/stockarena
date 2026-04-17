import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Investment Game'**
  String get appTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search symbol (Stock / Coin / ETF / Index)'**
  String get searchHint;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading data...'**
  String get loading;

  /// No description provided for @selectSymbol.
  ///
  /// In en, this message translates to:
  /// **'Select a symbol after search.'**
  String get selectSymbol;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @tradeHistory.
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get tradeHistory;

  /// No description provided for @profit.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get profit;

  /// No description provided for @ranking.
  ///
  /// In en, this message translates to:
  /// **'Ranking'**
  String get ranking;

  /// No description provided for @discussion.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get discussion;

  /// No description provided for @tradeLogTab.
  ///
  /// In en, this message translates to:
  /// **'Trade Log'**
  String get tradeLogTab;

  /// No description provided for @investmentGameTab.
  ///
  /// In en, this message translates to:
  /// **'Investment Game'**
  String get investmentGameTab;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get addFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to {name}'**
  String moveToFolder(Object name);

  /// No description provided for @favoriteAddedSnack.
  ///
  /// In en, this message translates to:
  /// **'⭐ Added to favorites: {name} ({symbol})'**
  String favoriteAddedSnack(Object name, Object symbol);

  /// No description provided for @movedToFolderSnack.
  ///
  /// In en, this message translates to:
  /// **'📁 Moved: {symbol} → {folder}'**
  String movedToFolderSnack(Object folder, Object symbol);

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @loggingIn.
  ///
  /// In en, this message translates to:
  /// **'Logging in...'**
  String get loggingIn;

  /// No description provided for @googleLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get googleLogin;

  /// No description provided for @googleLoginOnlyMobileWeb.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is available only on mobile/web.'**
  String get googleLoginOnlyMobileWeb;

  /// No description provided for @loginGuide.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google.\nOr create a test account.'**
  String get loginGuide;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @saveNickname.
  ///
  /// In en, this message translates to:
  /// **'Save nickname'**
  String get saveNickname;

  /// No description provided for @nicknameSaved.
  ///
  /// In en, this message translates to:
  /// **'Nickname saved'**
  String get nicknameSaved;

  /// No description provided for @nicknameSaveFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to save nickname: {msg}'**
  String nicknameSaveFail(Object msg);

  /// No description provided for @nicknameInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Nickname contains invalid characters.'**
  String get nicknameInvalidChars;

  /// No description provided for @nicknameAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This nickname is already in use.'**
  String get nicknameAlreadyUsed;

  /// No description provided for @nicknameEnter.
  ///
  /// In en, this message translates to:
  /// **'Please enter a nickname.'**
  String get nicknameEnter;

  /// No description provided for @nicknameChangeLimit.
  ///
  /// In en, this message translates to:
  /// **'You can change your nickname only once every 10 minutes.'**
  String get nicknameChangeLimit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @welcomeUser.
  ///
  /// In en, this message translates to:
  /// **'Welcome {name}!'**
  String welcomeUser(Object name);

  /// No description provided for @noUidPleaseRelogin.
  ///
  /// In en, this message translates to:
  /// **'No uid. Please sign in again.'**
  String get noUidPleaseRelogin;

  /// No description provided for @serverAccountCreateFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create server account: {err}'**
  String serverAccountCreateFail(Object err);

  /// No description provided for @createRandomTestAccount.
  ///
  /// In en, this message translates to:
  /// **'Create random test account'**
  String get createRandomTestAccount;

  /// No description provided for @createRandomFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create random account (check server/storage)'**
  String get createRandomFail;

  /// No description provided for @createRandomDone.
  ///
  /// In en, this message translates to:
  /// **'Random account created: {uid}'**
  String createRandomDone(Object uid);

  /// No description provided for @createTestAccountWithNickname.
  ///
  /// In en, this message translates to:
  /// **'Create test account with nickname'**
  String get createTestAccountWithNickname;

  /// No description provided for @testNickname.
  ///
  /// In en, this message translates to:
  /// **'Test nickname'**
  String get testNickname;

  /// No description provided for @testNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a test nickname.'**
  String get testNicknameHint;

  /// No description provided for @createTestFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create test account (check server/storage)'**
  String get createTestFail;

  /// No description provided for @createTestDone.
  ///
  /// In en, this message translates to:
  /// **'Test account created: {nick}'**
  String createTestDone(Object nick);

  /// No description provided for @rankingTitle.
  ///
  /// In en, this message translates to:
  /// **'Investment Game Ranking'**
  String get rankingTitle;

  /// No description provided for @uidEmptyCannotLoad.
  ///
  /// In en, this message translates to:
  /// **'UID is empty. Cannot load.'**
  String get uidEmptyCannotLoad;

  /// No description provided for @noRankingData.
  ///
  /// In en, this message translates to:
  /// **'No ranking data.'**
  String get noRankingData;

  /// No description provided for @rankingLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load ranking: {err}'**
  String rankingLoadFail(Object err);

  /// No description provided for @selectSymbolFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a symbol first.'**
  String get selectSymbolFirst;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error: {status} {body}'**
  String serverError(Object body, Object status);

  /// No description provided for @profitRateFmt.
  ///
  /// In en, this message translates to:
  /// **'Profit rate {rate}%'**
  String profitRateFmt(Object rate);

  /// No description provided for @discussionRules.
  ///
  /// In en, this message translates to:
  /// **'Discussion Rules'**
  String get discussionRules;

  /// No description provided for @alert.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get alert;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get confirm;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @loadingShort.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingShort;

  /// No description provided for @noPosts.
  ///
  /// In en, this message translates to:
  /// **'No posts yet.'**
  String get noPosts;

  /// No description provided for @cannotConnectServer.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to server. (URL/status/CORS/firewall)'**
  String get cannotConnectServer;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred.'**
  String get unknownError;

  /// No description provided for @loginRequiredNoUid.
  ///
  /// In en, this message translates to:
  /// **'Please sign in. (no uid)'**
  String get loginRequiredNoUid;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get register;

  /// No description provided for @enterContent.
  ///
  /// In en, this message translates to:
  /// **'Please enter content.'**
  String get enterContent;

  /// No description provided for @contentTooLong.
  ///
  /// In en, this message translates to:
  /// **'Content must be 300 characters or less.'**
  String get contentTooLong;

  /// No description provided for @linkNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Links are not allowed.'**
  String get linkNotAllowed;

  /// No description provided for @writeHint.
  ///
  /// In en, this message translates to:
  /// **'Write a post (max 300 chars)'**
  String get writeHint;

  /// No description provided for @ruleMax300.
  ///
  /// In en, this message translates to:
  /// **'• Max 300 characters'**
  String get ruleMax300;

  /// No description provided for @ruleNoSpam.
  ///
  /// In en, this message translates to:
  /// **'• No spamming (10s cooldown)'**
  String get ruleNoSpam;

  /// No description provided for @ruleNoLink.
  ///
  /// In en, this message translates to:
  /// **'• No links/URLs (http, https, www, .com etc.)'**
  String get ruleNoLink;

  /// No description provided for @ruleNoHate.
  ///
  /// In en, this message translates to:
  /// **'• No hate/abuse/harassment'**
  String get ruleNoHate;

  /// No description provided for @rankSuffix.
  ///
  /// In en, this message translates to:
  /// **'#{rank}'**
  String rankSuffix(Object rank);

  /// No description provided for @profitLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load profit data: {err}'**
  String profitLoadFail(Object err);

  /// No description provided for @totalProfitSummary.
  ///
  /// In en, this message translates to:
  /// **'Total Profit Summary'**
  String get totalProfitSummary;

  /// No description provided for @initial.
  ///
  /// In en, this message translates to:
  /// **'Initial'**
  String get initial;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
