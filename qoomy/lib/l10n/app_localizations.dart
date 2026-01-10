import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // App
      'appName': 'Qoomy',
      'appTagline': "Let's answer questions together",

      // Auth
      'signIn': 'Sign In',
      'signUp': 'Sign Up',
      'createAccount': 'Create Account',
      'joinQoomy': 'Join Qoomy and start playing',
      'email': 'Email',
      'password': 'Password',
      'confirmPassword': 'Confirm Password',
      'displayName': 'Display Name',
      'displayNameHint': 'How others will see you',
      'continueWithGoogle': 'Continue with Google',
      'or': 'or',
      'noAccount': "Don't have an account?",
      'haveAccount': 'Already have an account?',
      'logout': 'Logout',
      'pleaseLogin': 'Please log in',

      // Validation
      'enterEmail': 'Please enter your email',
      'validEmail': 'Please enter a valid email',
      'enterPassword': 'Please enter your password',
      'enterName': 'Please enter your name',
      'nameTooShort': 'Name must be at least 2 characters',
      'passwordTooShort': 'Password must be at least 6 characters',
      'confirmYourPassword': 'Please confirm your password',
      'passwordsNotMatch': 'Passwords do not match',

      // Home
      'myRooms': 'My Questions',
      'joinedRooms': 'Joined Rooms',
      'noRoomsYet': 'No rooms yet',
      'noRoomsDescription': 'Create a room to host a quiz or join an existing one',
      'joinRoom': 'Join Room',
      'createRoom': 'Create Room',
      'games': 'Games',
      'wins': 'Wins',

      // Room status
      'waiting': 'Waiting',
      'playing': 'Playing',
      'finished': 'Finished',
      'host': 'Host',
      'correctAnswerGiven': 'Correct answer given',
      'noCorrectAnswer': 'No correct answer',

      // Room modes
      'aiMode': 'AI Mode',
      'manual': 'Manual',

      // Time
      'justNow': 'Just now',
      'minutesAgo': 'm ago',
      'hoursAgo': 'h ago',
      'daysAgo': 'd ago',
      'yesterday': 'Yesterday',

      // Create room
      'createNewRoom': 'Create New Room',
      'question': 'Question',
      'questionHint': 'Enter the question for players',
      'answer': 'Answer',
      'answerHint': 'Enter the correct answer',
      'commentOptional': 'Comment (optional)',
      'commentHint': 'Additional info about the answer',
      'evaluationMode': 'Evaluation Mode',
      'aiEvaluation': 'AI Evaluation',
      'aiEvaluationDesc': 'AI will automatically evaluate answers',
      'manualEvaluation': 'Manual Evaluation',
      'manualEvaluationDesc': 'You will manually mark answers',
      'addImage': 'Add Image',
      'changeImage': 'Change Image',
      'create': 'Create',
      'creating': 'Creating...',
      'enterQuestion': 'Please enter a question',
      'enterAnswer': 'Please enter an answer',

      // Join room
      'enterRoomCode': 'Enter Room Code',
      'roomCodeHint': 'e.g. ABC123',
      'join': 'Join',
      'joining': 'Joining...',
      'enterCode': 'Please enter a room code',
      'roomNotFound': 'Room not found',

      // Game
      'quizGame': 'Quiz Game',
      'chat': 'Chat',
      'noMessagesYet': 'No messages yet',
      'sendAnswerOrComment': 'Send an answer or comment below',
      'typeAnswer': 'Type your answer...',
      'typeComment': 'Type a comment...',
      'typeMessage': 'Type a message...',
      'answerLabel': 'Answer',
      'giveAnswer': 'Give answer!',
      'comment': 'Comment',
      'aiEvaluating': 'AI is evaluating...',
      'correct': 'Correct!',
      'wrong': 'Wrong',
      'you': 'You',
      'hiddenAnswer': 'Answer hidden',
      'answerHiddenUntilEvaluated': 'Answer will be revealed after evaluation',
      'tapToRevealCorrectAnswer': 'Tap to reveal the correct answer',
      'youGotItRight': 'You got it right!',
      'revealAnswerTitle': 'Reveal Answer?',
      'revealAnswerWarning': 'If you reveal the correct answer, you will no longer be able to submit your own answer.',
      'reveal': 'Reveal',
      'cancel': 'Cancel',
      'youRevealedAnswer': 'You revealed the answer',
      'replyingTo': 'Replying to',
      'reply': 'Reply',
      'longPressToReply': 'Long press a message to reply',

      // Host screen
      'accessCode': 'Access Code',
      'codeCopied': 'Code copied!',
      'hostPanel': 'Host Panel',
      'players': 'Players',
      'noPlayersYet': 'No players yet',
      'waitingForPlayers': 'Share the room code to invite players',
      'shareCode': 'Share Code',
      'endGame': 'End Game',
      'correctAnswer': 'Correct Answer',
      'markAsCorrect': 'Mark as correct',
      'markAsWrong': 'Mark as wrong',
      'show': 'Show',
      'hide': 'Hide',
      'onlyHostCanSee': 'Only you can see this',

      // Results
      'gameResults': 'Game Results',
      'winner': 'Winner',
      'noWinner': 'No winner',
      'backToHome': 'Back to Home',
      'playAgain': 'Play Again',

      // Settings
      'settings': 'Settings',
      'language': 'Language',
      'english': 'English',
      'russian': 'Russian',

      // Filters
      'all': 'All',
      'asHost': 'Host',
      'asPlayer': 'Player',
      'active': 'Active',
      'unread': 'Unread',
      'noMatchingQuestions': 'No matching questions',

      // Teams
      'teams': 'Teams',
      'myTeams': 'My Teams',
      'createTeam': 'Create Team',
      'joinTeam': 'Join Team',
      'teamName': 'Team Name',
      'teamNameHint': 'Enter team name',
      'enterTeamName': 'Please enter team name',
      'inviteCode': 'Invite Code',
      'inviteCodeCopied': 'Invite code copied!',
      'shareInvite': 'Share Invite',
      'members': 'Members',
      'member': 'Member',
      'owner': 'Owner',
      'leaveTeam': 'Leave Team',
      'deleteTeam': 'Delete Team',
      'confirmLeaveTeam': 'Are you sure you want to leave this team?',
      'confirmDeleteTeam': 'Are you sure you want to delete this team? All members will be removed.',
      'noTeamsYet': 'No teams yet',
      'noTeamsDescription': 'Create a team or join an existing one using an invite code',
      'selectTeam': 'Select Team',
      'selectTeamDescription': 'Team members will automatically join this room',
      'noTeam': 'No Team',
      'teamNotFound': 'Team not found or invalid invite code',
      'enterTeamCode': 'Enter Team Code',
      'teamCodeHint': 'e.g. ABCD1234',
      'addMember': 'Add Member',
      'searchByEmail': 'Search by email',
      'userNotFound': 'User not found',
      'memberAdded': 'Member added',
      'enterEmailToSearch': 'Enter email to search for users',
      'add': 'Add',
      'alreadyMember': 'Already a member',

      // Create room extended
      'imageOptional': 'Image (Optional)',
      'onlyYouSeeThis': 'Only you will see this',
      'commentDescription': 'Shown to players after the answer is revealed',
      'addExplanation': 'Add explanation or fun fact...',
      'aiAssisted': 'AI Assisted',
      'aiAssistedDesc': 'AI suggests correctness, you confirm',
      'manualDesc': 'You mark answers as correct or incorrect',
      'failedToCreateRoom': 'Failed to create room',

      // Profile
      'profile': 'Profile',
      'statistics': 'Statistics',
      'questionsAsHost': 'Questions as Host',
      'questionsAsPlayer': 'Questions as Player',
      'correctAnswersTotal': 'Correct Answers',
      'wrongAnswers': 'Wrong Answers',
      'correctFirst': 'First to Answer',
      'correctNotFirst': 'Not First',
      'totalPoints': 'Total Points',
      'notLoggedIn': 'Not logged in',
      'confirmLogout': 'Are you sure you want to log out?',
    },
    'ru': {
      // App
      'appName': 'Qoomy',
      'appTagline': 'Давайте отвечать на вопросы вместе',

      // Auth
      'signIn': 'Войти',
      'signUp': 'Регистрация',
      'createAccount': 'Создать аккаунт',
      'joinQoomy': 'Присоединяйтесь к Qoomy',
      'email': 'Email',
      'password': 'Пароль',
      'confirmPassword': 'Подтвердите пароль',
      'displayName': 'Имя',
      'displayNameHint': 'Как вас будут видеть другие',
      'continueWithGoogle': 'Продолжить с Google',
      'or': 'или',
      'noAccount': 'Нет аккаунта?',
      'haveAccount': 'Уже есть аккаунт?',
      'logout': 'Выйти',
      'pleaseLogin': 'Пожалуйста, войдите',

      // Validation
      'enterEmail': 'Введите email',
      'validEmail': 'Введите корректный email',
      'enterPassword': 'Введите пароль',
      'enterName': 'Введите имя',
      'nameTooShort': 'Имя должно быть минимум 2 символа',
      'passwordTooShort': 'Пароль должен быть минимум 6 символов',
      'confirmYourPassword': 'Подтвердите пароль',
      'passwordsNotMatch': 'Пароли не совпадают',

      // Home
      'myRooms': 'Мои вопросы',
      'joinedRooms': 'Комнаты участника',
      'noRoomsYet': 'Пока нет комнат',
      'noRoomsDescription': 'Создайте комнату или присоединитесь к существующей',
      'joinRoom': 'Присоединиться',
      'createRoom': 'Задать вопрос',
      'games': 'Игр',
      'wins': 'Побед',

      // Room status
      'waiting': 'Ожидание',
      'playing': 'Идёт игра',
      'finished': 'Завершено',
      'host': 'Ведущий',
      'correctAnswerGiven': 'Есть правильный ответ',
      'noCorrectAnswer': 'Нет правильного ответа',

      // Room modes
      'aiMode': 'AI режим',
      'manual': 'Вручную',

      // Time
      'justNow': 'Только что',
      'minutesAgo': ' мин назад',
      'hoursAgo': ' ч назад',
      'daysAgo': ' д назад',
      'yesterday': 'Вчера',

      // Create room
      'createNewRoom': 'Новая комната',
      'question': 'Вопрос',
      'questionHint': 'Введите вопрос для игроков',
      'answer': 'Ответ',
      'answerHint': 'Введите правильный ответ',
      'commentOptional': 'Комментарий (необязательно)',
      'commentHint': 'Дополнительная информация',
      'evaluationMode': 'Режим оценки',
      'aiEvaluation': 'AI оценка',
      'aiEvaluationDesc': 'AI автоматически оценит ответы',
      'manualEvaluation': 'Ручная оценка',
      'manualEvaluationDesc': 'Вы будете оценивать ответы вручную',
      'addImage': 'Добавить изображение',
      'changeImage': 'Изменить изображение',
      'create': 'Создать',
      'creating': 'Создание...',
      'enterQuestion': 'Введите вопрос',
      'enterAnswer': 'Введите ответ',

      // Join room
      'enterRoomCode': 'Введите код комнаты',
      'roomCodeHint': 'например ABC123',
      'join': 'Войти',
      'joining': 'Вход...',
      'enterCode': 'Введите код комнаты',
      'roomNotFound': 'Комната не найдена',

      // Game
      'quizGame': 'Викторина',
      'chat': 'Чат',
      'noMessagesYet': 'Пока нет сообщений',
      'sendAnswerOrComment': 'Отправьте ответ или комментарий',
      'typeAnswer': 'Введите ответ...',
      'typeComment': 'Введите комментарий...',
      'typeMessage': 'Введите сообщение...',
      'answerLabel': 'Ответ',
      'giveAnswer': 'Дать ответ!',
      'comment': 'Комментарий',
      'aiEvaluating': 'AI оценивает...',
      'correct': 'Правильно!',
      'wrong': 'Неправильно',
      'you': 'Вы',
      'hiddenAnswer': 'Ответ скрыт',
      'answerHiddenUntilEvaluated': 'Ответ будет показан после проверки',
      'tapToRevealCorrectAnswer': 'Нажмите чтобы увидеть правильный ответ',
      'youGotItRight': 'Вы ответили правильно!',
      'revealAnswerTitle': 'Показать ответ?',
      'revealAnswerWarning': 'Если вы откроете правильный ответ, вы больше не сможете отправить свой ответ.',
      'reveal': 'Показать',
      'cancel': 'Отмена',
      'youRevealedAnswer': 'Вы открыли ответ',
      'replyingTo': 'Ответ на',
      'reply': 'Ответить',
      'longPressToReply': 'Долгое нажатие для ответа на сообщение',

      // Host screen
      'accessCode': 'Код доступа',
      'codeCopied': 'Код скопирован!',
      'hostPanel': 'Панель ведущего',
      'players': 'Игроки',
      'noPlayersYet': 'Пока нет игроков',
      'waitingForPlayers': 'Поделитесь кодом комнаты',
      'shareCode': 'Поделиться кодом',
      'endGame': 'Завершить игру',
      'correctAnswer': 'Правильный ответ',
      'markAsCorrect': 'Отметить как правильный',
      'markAsWrong': 'Отметить как неправильный',
      'show': 'Показать',
      'hide': 'Скрыть',
      'onlyHostCanSee': 'Ответ виден только ведущему',

      // Results
      'gameResults': 'Результаты',
      'winner': 'Победитель',
      'noWinner': 'Нет победителя',
      'backToHome': 'На главную',
      'playAgain': 'Играть снова',

      // Settings
      'settings': 'Настройки',
      'language': 'Язык',
      'english': 'English',
      'russian': 'Русский',

      // Filters
      'all': 'Все',
      'asHost': 'Ведущий',
      'asPlayer': 'Игрок',
      'active': 'Активные',
      'unread': 'Непрочитанные',
      'noMatchingQuestions': 'Нет подходящих вопросов',

      // Teams
      'teams': 'Команды',
      'myTeams': 'Мои команды',
      'createTeam': 'Создать команду',
      'joinTeam': 'Присоединиться к команде',
      'teamName': 'Название команды',
      'teamNameHint': 'Введите название команды',
      'enterTeamName': 'Введите название команды',
      'inviteCode': 'Код приглашения',
      'inviteCodeCopied': 'Код скопирован!',
      'shareInvite': 'Поделиться приглашением',
      'members': 'Участники',
      'member': 'Участник',
      'owner': 'Владелец',
      'leaveTeam': 'Выйти из команды',
      'deleteTeam': 'Удалить команду',
      'confirmLeaveTeam': 'Вы уверены, что хотите выйти из этой команды?',
      'confirmDeleteTeam': 'Вы уверены, что хотите удалить эту команду? Все участники будут удалены.',
      'noTeamsYet': 'Пока нет команд',
      'noTeamsDescription': 'Создайте команду или присоединитесь к существующей по коду приглашения',
      'selectTeam': 'Выбрать команду',
      'selectTeamDescription': 'Участники команды автоматически присоединятся к комнате',
      'noTeam': 'Без команды',
      'teamNotFound': 'Команда не найдена или неверный код',
      'enterTeamCode': 'Введите код команды',
      'teamCodeHint': 'например ABCD1234',
      'addMember': 'Добавить участника',
      'searchByEmail': 'Поиск по email',
      'userNotFound': 'Пользователь не найден',
      'memberAdded': 'Участник добавлен',
      'enterEmailToSearch': 'Введите email для поиска пользователей',
      'add': 'Добавить',
      'alreadyMember': 'Уже участник',

      // Create room extended
      'imageOptional': 'Изображение (необязательно)',
      'onlyYouSeeThis': 'Виден только вам',
      'commentDescription': 'Показывается игрокам после раскрытия ответа',
      'addExplanation': 'Добавьте пояснение или интересный факт...',
      'aiAssisted': 'AI помощник',
      'aiAssistedDesc': 'AI предлагает оценку, вы подтверждаете',
      'manualDesc': 'Вы отмечаете ответы как правильные или неправильные',
      'failedToCreateRoom': 'Не удалось создать комнату',

      // Profile
      'profile': 'Профиль',
      'statistics': 'Статистика',
      'questionsAsHost': 'Вопросов задано',
      'questionsAsPlayer': 'Вопросов отвечено',
      'correctAnswersTotal': 'Правильных ответов',
      'wrongAnswers': 'Неправильных ответов',
      'correctFirst': 'Первый ответ',
      'correctNotFirst': 'Не первый',
      'totalPoints': 'Всего очков',
      'notLoggedIn': 'Не авторизован',
      'confirmLogout': 'Вы уверены, что хотите выйти?',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
           _localizedValues['en']?[key] ??
           key;
  }

  // Convenience getters
  String get appName => get('appName');
  String get appTagline => get('appTagline');
  String get signIn => get('signIn');
  String get signUp => get('signUp');
  String get createAccount => get('createAccount');
  String get joinQoomy => get('joinQoomy');
  String get email => get('email');
  String get password => get('password');
  String get confirmPassword => get('confirmPassword');
  String get displayName => get('displayName');
  String get displayNameHint => get('displayNameHint');
  String get continueWithGoogle => get('continueWithGoogle');
  String get or => get('or');
  String get noAccount => get('noAccount');
  String get haveAccount => get('haveAccount');
  String get logout => get('logout');
  String get pleaseLogin => get('pleaseLogin');
  String get enterEmail => get('enterEmail');
  String get validEmail => get('validEmail');
  String get enterPassword => get('enterPassword');
  String get enterName => get('enterName');
  String get nameTooShort => get('nameTooShort');
  String get passwordTooShort => get('passwordTooShort');
  String get confirmYourPassword => get('confirmYourPassword');
  String get passwordsNotMatch => get('passwordsNotMatch');
  String get myRooms => get('myRooms');
  String get joinedRooms => get('joinedRooms');
  String get noRoomsYet => get('noRoomsYet');
  String get noRoomsDescription => get('noRoomsDescription');
  String get joinRoom => get('joinRoom');
  String get createRoom => get('createRoom');
  String get games => get('games');
  String get wins => get('wins');
  String get waiting => get('waiting');
  String get playing => get('playing');
  String get finished => get('finished');
  String get host => get('host');
  String get correctAnswerGiven => get('correctAnswerGiven');
  String get noCorrectAnswer => get('noCorrectAnswer');
  String get aiMode => get('aiMode');
  String get manual => get('manual');
  String get justNow => get('justNow');
  String get minutesAgo => get('minutesAgo');
  String get hoursAgo => get('hoursAgo');
  String get daysAgo => get('daysAgo');
  String get yesterday => get('yesterday');
  String get createNewRoom => get('createNewRoom');
  String get question => get('question');
  String get questionHint => get('questionHint');
  String get answer => get('answer');
  String get answerHint => get('answerHint');
  String get commentOptional => get('commentOptional');
  String get commentHint => get('commentHint');
  String get evaluationMode => get('evaluationMode');
  String get aiEvaluation => get('aiEvaluation');
  String get aiEvaluationDesc => get('aiEvaluationDesc');
  String get manualEvaluation => get('manualEvaluation');
  String get manualEvaluationDesc => get('manualEvaluationDesc');
  String get addImage => get('addImage');
  String get changeImage => get('changeImage');
  String get create => get('create');
  String get creating => get('creating');
  String get enterQuestion => get('enterQuestion');
  String get enterAnswer => get('enterAnswer');
  String get enterRoomCode => get('enterRoomCode');
  String get roomCodeHint => get('roomCodeHint');
  String get join => get('join');
  String get joining => get('joining');
  String get enterCode => get('enterCode');
  String get roomNotFound => get('roomNotFound');
  String get quizGame => get('quizGame');
  String get chat => get('chat');
  String get noMessagesYet => get('noMessagesYet');
  String get sendAnswerOrComment => get('sendAnswerOrComment');
  String get typeAnswer => get('typeAnswer');
  String get typeComment => get('typeComment');
  String get typeMessage => get('typeMessage');
  String get answerLabel => get('answerLabel');
  String get giveAnswer => get('giveAnswer');
  String get comment => get('comment');
  String get aiEvaluating => get('aiEvaluating');
  String get correct => get('correct');
  String get wrong => get('wrong');
  String get you => get('you');
  String get hiddenAnswer => get('hiddenAnswer');
  String get answerHiddenUntilEvaluated => get('answerHiddenUntilEvaluated');
  String get tapToRevealCorrectAnswer => get('tapToRevealCorrectAnswer');
  String get youGotItRight => get('youGotItRight');
  String get revealAnswerTitle => get('revealAnswerTitle');
  String get revealAnswerWarning => get('revealAnswerWarning');
  String get reveal => get('reveal');
  String get cancel => get('cancel');
  String get youRevealedAnswer => get('youRevealedAnswer');
  String get replyingTo => get('replyingTo');
  String get reply => get('reply');
  String get longPressToReply => get('longPressToReply');
  String get accessCode => get('accessCode');
  String get hostPanel => get('hostPanel');
  String get players => get('players');
  String get noPlayersYet => get('noPlayersYet');
  String get waitingForPlayers => get('waitingForPlayers');
  String get shareCode => get('shareCode');
  String get endGame => get('endGame');
  String get correctAnswer => get('correctAnswer');
  String get markAsCorrect => get('markAsCorrect');
  String get markAsWrong => get('markAsWrong');
  String get show => get('show');
  String get hide => get('hide');
  String get onlyHostCanSee => get('onlyHostCanSee');
  String get gameResults => get('gameResults');
  String get winner => get('winner');
  String get noWinner => get('noWinner');
  String get backToHome => get('backToHome');
  String get playAgain => get('playAgain');
  String get settings => get('settings');
  String get language => get('language');
  String get english => get('english');
  String get russian => get('russian');
  String get all => get('all');
  String get asHost => get('asHost');
  String get asPlayer => get('asPlayer');
  String get active => get('active');
  String get unread => get('unread');
  String get noMatchingQuestions => get('noMatchingQuestions');
  String get teams => get('teams');
  String get myTeams => get('myTeams');
  String get createTeam => get('createTeam');
  String get joinTeam => get('joinTeam');
  String get teamName => get('teamName');
  String get teamNameHint => get('teamNameHint');
  String get enterTeamName => get('enterTeamName');
  String get inviteCode => get('inviteCode');
  String get inviteCodeCopied => get('inviteCodeCopied');
  String get shareInvite => get('shareInvite');
  String get members => get('members');
  String get member => get('member');
  String get owner => get('owner');
  String get leaveTeam => get('leaveTeam');
  String get deleteTeam => get('deleteTeam');
  String get confirmLeaveTeam => get('confirmLeaveTeam');
  String get confirmDeleteTeam => get('confirmDeleteTeam');
  String get noTeamsYet => get('noTeamsYet');
  String get noTeamsDescription => get('noTeamsDescription');
  String get selectTeam => get('selectTeam');
  String get selectTeamDescription => get('selectTeamDescription');
  String get noTeam => get('noTeam');
  String get teamNotFound => get('teamNotFound');
  String get enterTeamCode => get('enterTeamCode');
  String get teamCodeHint => get('teamCodeHint');
  String get addMember => get('addMember');
  String get searchByEmail => get('searchByEmail');
  String get userNotFound => get('userNotFound');
  String get memberAdded => get('memberAdded');
  String get enterEmailToSearch => get('enterEmailToSearch');
  String get add => get('add');
  String get alreadyMember => get('alreadyMember');
  String get imageOptional => get('imageOptional');
  String get onlyYouSeeThis => get('onlyYouSeeThis');
  String get commentDescription => get('commentDescription');
  String get addExplanation => get('addExplanation');
  String get aiAssisted => get('aiAssisted');
  String get aiAssistedDesc => get('aiAssistedDesc');
  String get manualDesc => get('manualDesc');
  String get failedToCreateRoom => get('failedToCreateRoom');
  String get profile => get('profile');
  String get statistics => get('statistics');
  String get questionsAsHost => get('questionsAsHost');
  String get questionsAsPlayer => get('questionsAsPlayer');
  String get correctAnswersTotal => get('correctAnswersTotal');
  String get wrongAnswers => get('wrongAnswers');
  String get correctFirst => get('correctFirst');
  String get correctNotFirst => get('correctNotFirst');
  String get totalPoints => get('totalPoints');
  String get notLoggedIn => get('notLoggedIn');
  String get confirmLogout => get('confirmLogout');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
