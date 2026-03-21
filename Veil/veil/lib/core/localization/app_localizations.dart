import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  final Locale locale;
  
  AppLocalizations(this.locale);
  
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }
  
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
  
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ru'),
  ];
  
  late Map<String, String> _localizedStrings;
  
  Future<bool> load() async {
    _localizedStrings = _translations[locale.languageCode] ?? _translations['en']!;
    return true;
  }
  
  String translate(String key, [Map<String, dynamic>? args]) {
    var text = _localizedStrings[key] ?? key;
    
    if (args != null) {
      args.forEach((key, value) {
        text = text.replaceAll('{$key}', value.toString());
        
        if (text.contains('{count, plural')) {
          text = _processPlural(text, key, value);
        }
      });
    }
    
    return text;
  }
  
  String _processPlural(String text, String key, dynamic value) {
    final count = value is int ? value : int.tryParse(value.toString()) ?? 0;
    
    if (locale.languageCode == 'ru') {
      return _processRussianPlural(text, count);
    }
    return _processEnglishPlural(text, count);
  }
  
  String _processRussianPlural(String text, int count) {
    final forms = <String, String>{};
    final regex = RegExp(r'=(\d+)\{([^}]+)\}|(\w+)\{([^}]+)\}');
    final matches = regex.allMatches(text);
    
    for (final match in matches) {
      if (match.group(1) != null) {
        forms['=${match.group(1)}'] = match.group(2)!;
      } else {
        forms[match.group(3)!] = match.group(4)!;
      }
    }
    
    final lastDigit = count % 10;
    final lastTwoDigits = count % 100;
    
    if (forms.containsKey('=$count')) {
      return forms['=$count']!.replaceAll('{count}', count.toString());
    }
    
    if (lastTwoDigits >= 11 && lastTwoDigits <= 19) {
      return forms['other']!.replaceAll('{count}', count.toString());
    }
    
    if (lastDigit == 1) {
      return (forms['=1'] ?? forms['other'])!.replaceAll('{count}', count.toString());
    }
    
    if (lastDigit >= 2 && lastDigit <= 4) {
      return (forms['=2'] ?? forms['other'])!.replaceAll('{count}', count.toString());
    }
    
    return forms['other']!.replaceAll('{count}', count.toString());
  }
  
  String _processEnglishPlural(String text, int count) {
    final forms = <String, String>{};
    final regex = RegExp(r'=(\d+)\{([^}]+)\}|(\w+)\{([^}]+)\}');
    final matches = regex.allMatches(text);
    
    for (final match in matches) {
      if (match.group(1) != null) {
        forms['=${match.group(1)}'] = match.group(2)!;
      } else {
        forms[match.group(3)!] = match.group(4)!;
      }
    }
    
    if (forms.containsKey('=$count')) {
      return forms['=$count']!.replaceAll('{count}', count.toString());
    }
    
    if (count == 1 && forms.containsKey('=1')) {
      return forms['=1']!.replaceAll('{count}', count.toString());
    }
    
    return forms['other']!.replaceAll('{count}', count.toString());
  }
  
  static final Map<String, Map<String, String>> _translations = {
    'en': {
      'appName': 'Veil Messenger',
      'tabChats': 'Chats',
      'tabContacts': 'Contacts',
      'tabSettings': 'Settings',
      'tabProfile': 'Profile',
      'statusOnline': 'Online',
      'statusOffline': 'Offline',
      'statusAway': 'Away',
      'statusTyping': 'typing...',
      'statusJustNow': 'Just now',
      'statusMinutesAgo': '{count, plural, =1{1 minute ago} other{{count} minutes ago}}',
      'statusHoursAgo': '{count, plural, =1{1 hour ago} other{{count} hours ago}}',
      'statusDaysAgo': '{count, plural, =1{1 day ago} other{{count} days ago}}',
      'connectionConnected': 'Connected',
      'connectionDisconnected': 'Disconnected',
      'connectionNoConnection': 'No connection. Waiting for network...',
      'chatEmptyTitle': 'No chats yet',
      'chatEmptySubtitle': 'Find users to start messaging',
      'chatEmptyButton': 'Find users',
      'chatDeleteTitle': 'Delete chat',
      'chatDeleteForBoth': 'Delete for both',
      'chatDeleteForMe': 'Delete for me',
      'chatDeleteCancel': 'Cancel',
      'chatDeleteConfirm': 'Chat with {name} deleted for both',
      'messagePlaceholder': 'Message',
      'messageEncrypted': 'Encrypted message',
      'messageNoMessages': 'No messages',
      'messageEdited': 'edited',
      'messageForwardedFrom': 'Forwarded from',
      'messageForwardedHidden': 'Forwarded (hidden)',
      'actionReply': 'Reply',
      'actionForward': 'Forward',
      'actionCopy': 'Copy',
      'actionEdit': 'Edit',
      'actionDelete': 'Delete',
      'actionDeleteForMe': 'Delete for me',
      'actionReport': 'Report',
      'actionRetry': 'Tap to retry',
      'searchTitle': 'Find people',
      'searchHint': 'Search by username...',
      'searchEmpty': 'No users found',
      'searchEmptyHint': 'Try a different search term',
      'searchStartChat': 'Chat',
      'settingsTitle': 'Settings',
      'settingsDarkMode': 'Dark mode',
      'settingsDarkModeOn': 'Enabled',
      'settingsDarkModeOff': 'Disabled',
      'settingsColorTheme': 'Color theme',
      'settingsWallpaper': 'Chat wallpaper',
      'settingsAbout': 'About Veil Messenger',
      'settingsLanguage': 'Language',
      'profileTitle': 'Profile',
      'profileEdit': 'Edit Profile',
      'profileEditSubtitle': 'Change your name, bio and photo',
      'profilePrivacy': 'Privacy',
      'profilePrivacySubtitle': 'Control your privacy settings',
      'profileLogout': 'Log Out',
      'mediaGallery': 'Gallery',
      'mediaCamera': 'Camera',
      'mediaVideo': 'Video',
      'mediaRecord': 'Record',
      'mediaNoCompression': 'Send without compression',
      'errorGeneric': 'Something went wrong',
      'errorNetwork': 'Network error',
      'errorSessionExpired': 'Session expired. Please login again.',
      'newMessageFrom': 'New message from {name}',
      'reactionLike': 'like',
      'reactionDislike': 'dislike',
      'reactionHeart': 'heart',
      'reactionFire': 'fire',
      'reactionBrokenHeart': 'broken_heart',
      'reactionLaugh': 'laugh',
      'reactionCry': 'cry',

      'usernameBanned': 'This username is banned',
'registrationBanned': 'Registration is banned for this account',
'accessDenied': 'Access denied',
'emailAlreadyExists': 'Email already exists',
'invalidData': 'Invalid data provided',
'serverError': 'Server error, please try again',
      // Цветовые темы - добавьте после settingsAbout
'colorThemeRed': 'Bloody Sunset',
'colorThemeBirch': 'Woodland Spirit',
'colorThemeBlue': 'Icy Abyss',
'colorThemeShimmering': 'Cosmic Dust',
'colorThemeDarkOrange': 'Fire Night',
'colorThemeDarkYellow': 'Amber Ghost',
'colorThemeLightYellow': 'Solar Honey',
'colorThemeLightOrange': 'Peach Dawn',
'colorThemeAvailableForDark': 'Available for dark theme:',
'colorThemeAvailableForLight': 'Available for light theme:',
'colorThemeSelect': 'Select theme',
      'welcomeTitle': 'Welcome to Veil',
'welcomeDescription1': 'Secure, end-to-end encrypted messaging. Your privacy is our priority.',
'welcomeDescription2': 'All messages are encrypted with AES-256. Only you and the recipient can read them.',
'welcomeDescription3': 'We don\'t store your messages on our servers. Everything stays on your device.',
'welcomeDescription4': 'Set timers for messages to disappear after being read. Leave no trace.',
'militaryGradeEncryption': 'Military-Grade Encryption',
'noDataCollection': 'No Data Collection',
'selfDestructingMessages': 'Self-Destructing Messages',
'privacyPolicy': 'Privacy Policy',
'iHaveReadAndAgree': 'I have read and agree to the ',
'createAccount': 'Create Account',
'signIn': 'Sign In',
'lightMode': 'Light Mode',
'darkMode': 'Dark Mode',
'messageMedia': 'Media',

// Login Screen
'signInTitle': 'Sign In',
'signInSubtitle': 'Enter your credentials to continue',
'username': 'Username',
'password': 'Password',
'invalidCredentials': 'Invalid username or password',
'fillAllFields': 'Fill all fields',

// Register Screen
'createAccountTitle': 'Create Account',
'email': 'Email',
'displayName': 'Display Name',
'bio': 'Bio',
'bioOptional': 'Bio (optional)',
'confirmPassword': 'Confirm Password',
'secretCodeWord': 'Secret Code Word',
'codeWordHint': 'Code Word Hint',
'codeWordHintOptional': 'Code Word Hint (optional)',
'codeWordHelper': 'Used for password recovery',
'minCharacters': 'Min {count} characters',
'usernameTaken': 'Username taken',
'usernameAvailable': 'Username available',
'checkFailed': 'Check failed',
'enterValidEmail': 'Enter valid email',
'passwordMinChars': 'Password min {count} characters',
'passwordsDoNotMatch': 'Passwords do not match',
'registrationFailed': 'Registration failed: {error}',

// Code Word Confirmation
'rememberThisInformation': 'REMEMBER THIS INFORMATION',
'yourSecretCodeWord': 'Your Secret Code Word:',
'iUnderstandCreateAccount': 'I UNDERSTAND, CREATE ACCOUNT',
'goBack': 'GO BACK',

// Privacy Policy Dialog
'privacyPolicyTitle': 'Privacy Policy',
'privacyPolicyText': '''Veil Messenger Privacy Policy

1. Data Collection
We collect minimal data: username, email, and profile information. We do NOT collect message content.

2. Encryption
All messages are end-to-end encrypted using AES-256. We cannot read your messages.

3. Data Storage
Messages are stored only on your device and your chat partner's device. Our servers only relay encrypted data.

4. Your Rights
You can delete your account and all associated data at any time.

5. Security
Your code word is used for password recovery. We cannot reset your password without it.

By using Veil, you agree to these terms.''',
'close': 'Close',
'iAgree': 'I Agree',

 'settingsMoodEffects': 'Mood effects',
      'moodEffectNone': 'None',
      'moodEffectSnow': 'Snowflakes',
      'moodEffectSummer': 'Summer vibes',
      'moodEffectRain': 'Rain',
      'moodEffectSelect': 'Select mood effect',

      'donationTitle': 'Support the project',
'donationSubtitle': 'For server rental',
'supportProject': 'Donate',
'hideDonation': 'Hide',
'donationHiddenTitle': 'Donation hidden',
'donationHiddenMessage': 'Donation block hidden from profile. You can enable it back in settings.',
'gotIt': 'Got it',
'settingsShowDonation': 'Show donation block',

// Language Selection
'selectLanguage': 'Select Language',
    },
    'ru': {
  'appName': 'Veil Messenger',
  'tabChats': 'Чаты',
  'tabContacts': 'Контакты',
  'tabSettings': 'Настройки',
  'tabProfile': 'Профиль',
  
  'statusOnline': 'В сети',
  'statusOffline': 'Не в сети',
  'statusAway': 'Не беспокоить',
  'statusTyping': 'печатает...',
  'statusJustNow': 'Только что',
  'statusMinutesAgo': '{count, plural, =1{1 минуту назад} =2{2 минуты назад} =3{3 минуты назад} =4{4 минуты назад} other{{count} минут назад}}',
  'statusHoursAgo': '{count, plural, =1{1 час назад} =2{2 часа назад} =3{3 часа назад} =4{4 часа назад} other{{count} часов назад}}',
  'statusDaysAgo': '{count, plural, =1{1 день назад} =2{2 дня назад} =3{3 дня назад} =4{4 дня назад} other{{count} дней назад}}',
  
  'connectionConnected': 'Подключено',
  'connectionDisconnected': 'Отключено',
  'connectionNoConnection': 'Нет подключения. Ожидание сети...',
  
  'chatEmptyTitle': 'Пока нет чатов',
  'chatEmptySubtitle': 'Найдите пользователей, чтобы начать общение',
  'chatEmptyButton': 'Найти пользователей',
  'chatDeleteTitle': 'Удалить чат',
  'chatDeleteForBoth': 'Удалить для всех',
  'chatDeleteForMe': 'Удалить для меня',
  'chatDeleteCancel': 'Отмена',
  'chatDeleteConfirm': 'Чат с {name} удалён для всех',
  
  'messagePlaceholder': 'Сообщение',
  'messageEncrypted': 'Зашифрованное сообщение',
  'messageNoMessages': 'Нет сообщений',
  'messageEdited': 'изменено',
  'messageForwardedFrom': 'Переслано от',
  'messageForwardedHidden': 'Переслано (скрыто)',
  'messageMedia': 'Медиа',
  
  'actionReply': 'Ответить',
  'actionForward': 'Переслать',
  'actionCopy': 'Копировать',
  'actionEdit': 'Изменить',
  'actionDelete': 'Удалить',
  'actionDeleteForMe': 'Удалить для меня',
  'actionReport': 'Пожаловаться',
  'actionRetry': 'Нажмите, чтобы повторить',
  
  'searchTitle': 'Найти людей',
  'searchHint': 'Поиск по имени пользователя...',
  'searchEmpty': 'Пользователи не найдены',
  'searchEmptyHint': 'Попробуйте другой запрос',
  'searchStartChat': 'Написать',
  
  'settingsTitle': 'Настройки',
  'settingsDarkMode': 'Тёмная тема',
  'settingsDarkModeOn': 'Включена',
  'settingsDarkModeOff': 'Выключена',
  'settingsColorTheme': 'Цветовая тема',
  'settingsWallpaper': 'Обои чата',
  'settingsAbout': 'О Veil Messenger',
  'settingsLanguage': 'Язык',
  'settingsMoodEffects': 'Эффекты настроения',
  'settingsShowDonation': 'Показывать блок пожертвований',
  
  'profileTitle': 'Профиль',
  'profileEdit': 'Редактировать профиль',
  'profileEditSubtitle': 'Измените имя, биографию и фото',
  'profilePrivacy': 'Приватность',
  'profilePrivacySubtitle': 'Управление настройками приватности',
  'profileLogout': 'Выйти',
  
  'mediaGallery': 'Галерея',
  'mediaCamera': 'Камера',
  'mediaVideo': 'Видео',
  'mediaRecord': 'Запись',
  'mediaNoCompression': 'Отправить без сжатия',
  
  'errorGeneric': 'Что-то пошло не так',
  'errorNetwork': 'Ошибка сети',
  'errorSessionExpired': 'Сессия истекла. Пожалуйста, войдите снова.',
  
  'newMessageFrom': 'Новое сообщение от {name}',
  
  'reactionLike': 'нравится',
  'reactionDislike': 'не нравится',
  'reactionHeart': 'сердце',
  'reactionFire': 'огонь',
  'reactionBrokenHeart': 'разбитое сердце',
  'reactionLaugh': 'смех',
  'reactionCry': 'плач',
  
  'colorThemeRed': 'Кровавый закат',
  'colorThemeBirch': 'Древесный дух',
  'colorThemeBlue': 'Ледяная бездна',
  'colorThemeShimmering': 'Космическая пыль',
  'colorThemeDarkOrange': 'Огненная ночь',
  'colorThemeDarkYellow': 'Янтарный призрак',
  'colorThemeLightYellow': 'Солнечный мед',
  'colorThemeLightOrange': 'Персиковый рассвет',
  'colorThemeAvailableForDark': 'Доступны для тёмной темы:',
  'colorThemeAvailableForLight': 'Доступны для светлой темы:',
  'colorThemeSelect': 'Выберите тему',
  
  'welcomeTitle': 'Добро пожаловать в Veil',
  'welcomeDescription1': 'Безопасный мессенджер со сквозным шифрованием. Ваша конфиденциальность - наш приоритет.',
  'welcomeDescription2': 'Все сообщения шифруются AES-256. Только вы и получатель можете их прочитать.',
  'welcomeDescription3': 'Мы не храним ваши сообщения на серверах. Всё остаётся на вашем устройстве.',
  'welcomeDescription4': 'Устанавливайте таймер для самоуничтожения сообщений после прочтения.',
  'militaryGradeEncryption': 'Военное шифрование',
  'noDataCollection': 'Без сбора данных',
  'selfDestructingMessages': 'Самоуничтожение',
  'privacyPolicy': 'Политика конфиденциальности',
  'iHaveReadAndAgree': 'Я прочитал и согласен с ',
  'createAccount': 'Создать аккаунт',
  'signIn': 'Войти',
  'lightMode': 'Светлая тема',
  'darkMode': 'Тёмная тема',
  'selectLanguage': 'Выберите язык',
  
  'usernameBanned': 'Это имя пользователя заблокировано',
  'registrationBanned': 'Регистрация заблокирована для этого аккаунта',
  'accessDenied': 'Доступ запрещён',
  'emailAlreadyExists': 'Email уже существует',
  'invalidData': 'Неверные данные',
  'serverError': 'Ошибка сервера, попробуйте позже',
  
  'signInTitle': 'Вход',
  'signInSubtitle': 'Введите ваши данные для входа',
  'username': 'Имя пользователя',
  'password': 'Пароль',
  'invalidCredentials': 'Неверное имя пользователя или пароль',
  'fillAllFields': 'Заполните все поля',
  
  'createAccountTitle': 'Создать аккаунт',
  'email': 'Email',
  'displayName': 'Отображаемое имя',
  'bio': 'О себе',
  'bioOptional': 'О себе (необязательно)',
  'confirmPassword': 'Подтвердите пароль',
  'secretCodeWord': 'Секретное кодовое слово',
  'codeWordHint': 'Подсказка для кодового слова',
  'codeWordHintOptional': 'Подсказка (необязательно)',
  'codeWordHelper': 'Используется для восстановления пароля',
  'minCharacters': 'Минимум {count} символов',
  'usernameTaken': 'Имя занято',
  'usernameAvailable': 'Имя доступно',
  'checkFailed': 'Ошибка проверки',
  'enterValidEmail': 'Введите корректный email',
  'passwordMinChars': 'Пароль минимум {count} символов',
  'passwordsDoNotMatch': 'Пароли не совпадают',
  'registrationFailed': 'Ошибка регистрации: {error}',
  
  'appearance': 'Внешний вид',
  'language_region': 'Язык и регион',
  'about': 'О приложении',
  'support': 'Поддержка',
  'coming_soon': 'Скоро',
  'visible': 'Видимо',
  'hidden': 'Скрыто',
  
  'rememberThisInformation': 'ЗАПОМНИТЕ ЭТУ ИНФОРМАЦИЮ',
  'yourSecretCodeWord': 'Ваше секретное кодовое слово:',
  'iUnderstandCreateAccount': 'Я ПОНИМАЮ, СОЗДАТЬ АККАУНТ',
  'goBack': 'НАЗАД',
  
  'privacyPolicyTitle': 'Политика конфиденциальности',
  'privacyPolicyText': 'Политика конфиденциальности Veil Messenger\n\n1. Сбор данных\nМы собираем минимум данных: имя пользователя, email и информацию профиля. Мы НЕ собираем содержимое сообщений.\n\n2. Шифрование\nВсе сообщения шифруются сквозным шифрованием AES-256. Мы не можем прочитать ваши сообщения.\n\n3. Хранение данных\nСообщения хранятся только на вашем устройстве и устройстве собеседника. Наши серверы только передают зашифрованные данные.\n\n4. Ваши права\nВы можете удалить свой аккаунт и все связанные данные в любое время.\n\n5. Безопасность\nВаше кодовое слово используется для восстановления пароля. Мы не можем сбросить ваш пароль без него.\n\nИспользуя Veil, вы соглашаетесь с этими условиями.',
  'close': 'Закрыть',
  'iAgree': 'Согласен',
  
  'moodEffectNone': 'Нет',
  'moodEffectSnow': 'Снежинки',
  'moodEffectSummer': 'Летнее настроение',
  'moodEffectRain': 'Дождь',
  'moodEffectSelect': 'Выберите эффект настроения',
  
  'donationTitle': 'Поддержать проект',
  'donationSubtitle': 'На аренду серверов',
  'supportProject': 'Пожертвовать',
  'hideDonation': 'Скрыть',
  'donationHiddenTitle': 'Пожертвование скрыто',
  'donationHiddenMessage': 'Блок пожертвований скрыт из профиля. Включить обратно можно в настройках.',
  'gotIt': 'Понятно',
},
  };
  
  String get appName => translate('appName');
  String get tabChats => translate('tabChats');
  String get tabContacts => translate('tabContacts');
  String get tabSettings => translate('tabSettings');
  String get tabProfile => translate('tabProfile');
  String get statusOnline => translate('statusOnline');
  String get statusOffline => translate('statusOffline');
  String get statusAway => translate('statusAway');
  String get statusTyping => translate('statusTyping');
  String statusMinutesAgo(int count) => translate('statusMinutesAgo', {'count': count});
  String statusHoursAgo(int count) => translate('statusHoursAgo', {'count': count});
  String statusDaysAgo(int count) => translate('statusDaysAgo', {'count': count});
  String get connectionConnected => translate('connectionConnected');
  String get connectionDisconnected => translate('connectionDisconnected');
  String get connectionNoConnection => translate('connectionNoConnection');
  String get chatEmptyTitle => translate('chatEmptyTitle');
  String get chatEmptySubtitle => translate('chatEmptySubtitle');
  String get chatEmptyButton => translate('chatEmptyButton');
  String get chatDeleteTitle => translate('chatDeleteTitle');
  String get chatDeleteForBoth => translate('chatDeleteForBoth');
  String get chatDeleteForMe => translate('chatDeleteForMe');
  String get chatDeleteCancel => translate('chatDeleteCancel');
  String chatDeleteConfirm(String name) => translate('chatDeleteConfirm', {'name': name});
  String get messagePlaceholder => translate('messagePlaceholder');
  String get messageEncrypted => translate('messageEncrypted');
  String get messageNoMessages => translate('messageNoMessages');
  String get messageEdited => translate('messageEdited');
  String get messageForwardedFrom => translate('messageForwardedFrom');
  String get messageForwardedHidden => translate('messageForwardedHidden');
  String get actionReply => translate('actionReply');
  String get actionForward => translate('actionForward');
  String get actionCopy => translate('actionCopy');
  String get actionEdit => translate('actionEdit');
  String get actionDelete => translate('actionDelete');
  String get actionDeleteForMe => translate('actionDeleteForMe');
  String get actionReport => translate('actionReport');
  String get actionRetry => translate('actionRetry');
  String get searchTitle => translate('searchTitle');
  String get searchHint => translate('searchHint');
  String get searchEmpty => translate('searchEmpty');
  String get searchEmptyHint => translate('searchEmptyHint');
  String get searchStartChat => translate('searchStartChat');
  String get settingsTitle => translate('settingsTitle');
  String get settingsDarkMode => translate('settingsDarkMode');
  String get settingsDarkModeOn => translate('settingsDarkModeOn');
  String get settingsDarkModeOff => translate('settingsDarkModeOff');
  String get settingsColorTheme => translate('settingsColorTheme');
  String get settingsWallpaper => translate('settingsWallpaper');
  String get settingsAbout => translate('settingsAbout');
  String get settingsLanguage => translate('settingsLanguage');
  String get profileTitle => translate('profileTitle');
  String get profileEdit => translate('profileEdit');
  String get profileEditSubtitle => translate('profileEditSubtitle');
  String get profilePrivacy => translate('profilePrivacy');
  String get profilePrivacySubtitle => translate('profilePrivacySubtitle');
  String get profileLogout => translate('profileLogout');
  String get mediaGallery => translate('mediaGallery');
  String get mediaCamera => translate('mediaCamera');
  String get mediaVideo => translate('mediaVideo');
  String get mediaRecord => translate('mediaRecord');
  String get mediaNoCompression => translate('mediaNoCompression');
  String get errorGeneric => translate('errorGeneric');
  String get errorNetwork => translate('errorNetwork');
  String get errorSessionExpired => translate('errorSessionExpired');
  String newMessageFrom(String name) => translate('newMessageFrom', {'name': name});
  String get reactionLike => translate('reactionLike');
  String get reactionDislike => translate('reactionDislike');
  String get reactionHeart => translate('reactionHeart');
  String get reactionFire => translate('reactionFire');
  String get reactionBrokenHeart => translate('reactionBrokenHeart');
  String get reactionLaugh => translate('reactionLaugh');
  String get reactionCry => translate('reactionCry');
  String get statusJustNow => translate('statusJustNow');
  // Добавьте после других геттеров
String get colorThemeRed => translate('colorThemeRed');
String get colorThemeBirch => translate('colorThemeBirch');
String get colorThemeBlue => translate('colorThemeBlue');
String get colorThemeShimmering => translate('colorThemeShimmering');
String get colorThemeDarkOrange => translate('colorThemeDarkOrange');
String get colorThemeDarkYellow => translate('colorThemeDarkYellow');
String get colorThemeLightYellow => translate('colorThemeLightYellow');
String get colorThemeLightOrange => translate('colorThemeLightOrange');
String get colorThemeAvailableForDark => translate('colorThemeAvailableForDark');
String get colorThemeAvailableForLight => translate('colorThemeAvailableForLight');
String get colorThemeSelect => translate('colorThemeSelect');
// Добавьте эти геттеры в класс AppLocalizations
String get welcomeTitle => translate('welcomeTitle');
String get welcomeDescription1 => translate('welcomeDescription1');
String get welcomeDescription2 => translate('welcomeDescription2');
String get welcomeDescription3 => translate('welcomeDescription3');
String get welcomeDescription4 => translate('welcomeDescription4');
String get militaryGradeEncryption => translate('militaryGradeEncryption');
String get noDataCollection => translate('noDataCollection');
String get selfDestructingMessages => translate('selfDestructingMessages');
String get privacyPolicy => translate('privacyPolicy');
String get iHaveReadAndAgree => translate('iHaveReadAndAgree');
String get createAccount => translate('createAccount');
String get signIn => translate('signIn');
String get lightMode => translate('lightMode');
String get darkMode => translate('darkMode');
String get donationTitle => translate('donationTitle');
String get donationSubtitle => translate('donationSubtitle');
String get supportProject => translate('supportProject');
String get hideDonation => translate('hideDonation');
String get donationHiddenTitle => translate('donationHiddenTitle');
String get donationHiddenMessage => translate('donationHiddenMessage');
String get gotIt => translate('gotIt');
String get settingsShowDonation => translate('settingsShowDonation');

// Login Screen
String get signInTitle => translate('signInTitle');
String get signInSubtitle => translate('signInSubtitle');
String get username => translate('username');
String get password => translate('password');
String get invalidCredentials => translate('invalidCredentials');
String get fillAllFields => translate('fillAllFields');

// Register Screen
String get createAccountTitle => translate('createAccountTitle');
String get email => translate('email');
String get displayName => translate('displayName');
String get bio => translate('bio');
String get bioOptional => translate('bioOptional');
String get confirmPassword => translate('confirmPassword');
String get secretCodeWord => translate('secretCodeWord');
String get codeWordHint => translate('codeWordHint');
String get codeWordHintOptional => translate('codeWordHintOptional');
String get codeWordHelper => translate('codeWordHelper');
String get minCharacters => translate('minCharacters');
String get usernameTaken => translate('usernameTaken');
String get usernameAvailable => translate('usernameAvailable');
String get checkFailed => translate('checkFailed');
String get enterValidEmail => translate('enterValidEmail');
String get passwordMinChars => translate('passwordMinChars');
String get passwordsDoNotMatch => translate('passwordsDoNotMatch');
String get registrationFailed => translate('registrationFailed');

// Code Word Confirmation
String get rememberThisInformation => translate('rememberThisInformation');
String get yourSecretCodeWord => translate('yourSecretCodeWord');
String get iUnderstandCreateAccount => translate('iUnderstandCreateAccount');
String get goBack => translate('goBack');

// Новые геттеры для настроек
String get appearance => translate('appearance');
String get languageRegion => translate('language_region');
String get about => translate('about');
String get support => translate('support');
String get comingSoon => translate('coming_soon');
String get visible => translate('visible');
String get hidden => translate('hidden');

// Privacy Policy Dialog
String get privacyPolicyTitle => translate('privacyPolicyTitle');
String get privacyPolicyText => translate('privacyPolicyText');
String get close => translate('close');
String get iAgree => translate('iAgree');

String get settingsMoodEffects => translate('settingsMoodEffects');
  String get moodEffectNone => translate('moodEffectNone');
  String get moodEffectSnow => translate('moodEffectSnow');
  String get moodEffectSummer => translate('moodEffectSummer');
  String get moodEffectRain => translate('moodEffectRain');
  String get moodEffectSelect => translate('moodEffectSelect');
  String get messageMedia => translate('messageMedia');
  // Error messages
String get usernameBanned => translate('usernameBanned');
String get registrationBanned => translate('registrationBanned');
String get accessDenied => translate('accessDenied');
String get emailAlreadyExists => translate('emailAlreadyExists');
String get invalidData => translate('invalidData');
String get serverError => translate('serverError');



// Language Selection
String get selectLanguage => translate('selectLanguage');
  
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}