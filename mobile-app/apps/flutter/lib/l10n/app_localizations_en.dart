// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PAI — OpenCode AI';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get stop => 'Stop';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get rename => 'Rename';

  @override
  String get allow => 'Allow';

  @override
  String get once => 'Once';

  @override
  String get deny => 'Deny';

  @override
  String get answer => 'Answer';

  @override
  String get switchAction => 'Switch';

  @override
  String get manage => 'Manage';

  @override
  String get askPaiHint => 'Ask PAI...';

  @override
  String get chatEmptyTitle => 'How can I help?';

  @override
  String get chatEmptySubtitle => 'Send a message to get started';

  @override
  String get initializingChat => 'Initializing chat...';

  @override
  String get generating => 'Generating...';

  @override
  String get goToSettings => 'Go to Settings';

  @override
  String get serverNotConfigured =>
      'Server not configured. Please go to Settings.';

  @override
  String get savedSessionOtherDirectory =>
      'Saved session belonged to another directory; starting fresh';

  @override
  String failedLoadHistory(String error) {
    return 'Failed to load session history: $error';
  }

  @override
  String failedCreateSession(String error) {
    return 'Failed to create session: $error';
  }

  @override
  String errorWithDetail(String error) {
    return 'Error: $error';
  }

  @override
  String get camera => 'Camera';

  @override
  String get gallery => 'Gallery';

  @override
  String get file => 'File';

  @override
  String get sessionSummarized => 'Session summarized';

  @override
  String get noModelsAvailable => 'No models available';

  @override
  String get selectModel => 'Select Model';

  @override
  String get defaultServerModel => 'Default (server)';

  @override
  String failedLoadModels(String error) {
    return 'Failed to load models: $error';
  }

  @override
  String get sessionTodos => 'Session Todos';

  @override
  String get noTodos => 'No todos in this session';

  @override
  String shareLinkMessage(String link) {
    return 'Share link: $link';
  }

  @override
  String get shareCreated => 'Share created (check session info)';

  @override
  String get noSessionInfo => 'No session info available';

  @override
  String get sessionInfo => 'Session Info';

  @override
  String get modelLabel => 'Model';

  @override
  String childSessions(int count) {
    return 'Child Sessions ($count)';
  }

  @override
  String commandExecuted(String command) {
    return 'Command /$command executed';
  }

  @override
  String commandFailed(String error) {
    return 'Command failed: $error';
  }

  @override
  String get todos => 'Todos';

  @override
  String get share => 'Share';

  @override
  String get summarize => 'Summarize';

  @override
  String get searchInChat => 'Search in chat...';

  @override
  String get revertChanges => 'Revert changes';

  @override
  String get revertChangesSubtitle => 'Undo file changes from this message';

  @override
  String get reverted => 'Reverted';

  @override
  String get revertFailed => 'Revert failed';

  @override
  String get forkFromHere => 'Fork from here';

  @override
  String get forkSubtitle => 'Branch into a new session';

  @override
  String get undo => 'Undo';

  @override
  String yesterdayAt(String time) {
    return 'Yesterday $time';
  }

  @override
  String get chats => 'Chats';

  @override
  String get newChat => 'New chat';

  @override
  String get searchChats => 'Search chats...';

  @override
  String get renameSession => 'Rename Session';

  @override
  String get name => 'Name';

  @override
  String get enterSessionName => 'Enter session name';

  @override
  String get deleteSessionTitle => 'Delete Session?';

  @override
  String deleteConfirmBody(String name) {
    return '\"$name\" will be permanently deleted.';
  }

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get startNewConversation => 'Start a new conversation';

  @override
  String get sessionName => 'Session name';

  @override
  String get deleteQuestion => 'Delete?';

  @override
  String get terminal => 'Terminal';

  @override
  String get aiProviders => 'AI Providers';

  @override
  String get settings => 'Settings';

  @override
  String get paiLocked => 'PAI is locked';

  @override
  String get authenticating => 'Authenticating...';

  @override
  String get unlock => 'Unlock';

  @override
  String get unlockHintBiometrics => 'Unlock with biometrics or device PIN';

  @override
  String get unlockHintPin => 'Unlock with device PIN';

  @override
  String get authCancelledOrFailed => 'Authentication was cancelled or failed.';

  @override
  String get setupScreenLock =>
      'Set up a screen lock in Android settings to use app lock.';

  @override
  String get workspace => 'Workspace';

  @override
  String get favorites => 'Favorites';

  @override
  String get recent => 'Recent';

  @override
  String get manualPath => 'Manual path';

  @override
  String get defaultHome => 'Default (~)';

  @override
  String get switchWorkspaceTitle => 'Switch workspace?';

  @override
  String get switchWorkspaceBodyStreaming =>
      'An active stream will be stopped and the current chat context will be closed.';

  @override
  String get switchWorkspaceBody => 'Current chat context will be closed.';

  @override
  String get machines => 'Machines';

  @override
  String get machinesSubtitle =>
      'Set up SSH, bootstrap OpenCode, or use a direct server';

  @override
  String get aiProvidersSubtitle => 'Manage providers on the active machine';

  @override
  String get appearance => 'Appearance';

  @override
  String get systemTheme => 'System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get dynamicColor => 'Dynamic color';

  @override
  String get dynamicColorSubtitle =>
      'Follow the wallpaper colors (Material You)';

  @override
  String get accentColor => 'Accent color';

  @override
  String get pureBlack => 'Pure black (OLED)';

  @override
  String get pureBlackSubtitle => 'Black surfaces in the dark theme';

  @override
  String get showThinking => 'Show thinking';

  @override
  String get showThinkingSubtitle => 'Display agent reasoning steps';

  @override
  String get security => 'Security';

  @override
  String get appLock => 'App Lock';

  @override
  String get appLockSubtitleAvailable =>
      'Uses Android biometrics, PIN, password, or pattern';

  @override
  String get appLockSubtitleUnavailable =>
      'Set up a screen lock in Android settings first';

  @override
  String get lockTimeout => 'Lock Timeout';

  @override
  String get permissionRequired => 'Permission Required';

  @override
  String get paiWantsToExecute => 'PAI wants to execute:';

  @override
  String get patternsAffected => 'Patterns affected:';

  @override
  String get question => 'Question';

  @override
  String get answered => 'Answered';

  @override
  String get customAnswerHint => 'Custom answer...';

  @override
  String get micPermissionNeeded => 'Microphone permission needed';

  @override
  String get welcomeSubtitle => 'Your Personal AI Assistant';

  @override
  String get setUpMachine => 'Set Up Machine';

  @override
  String get browseFolders => 'Browse folders';

  @override
  String get useThisFolder => 'Use this folder';

  @override
  String get couldNotListFolder => 'Could not list this folder';

  @override
  String get noSubfolders => 'No subfolders';

  @override
  String get colorStyle => 'Color style';

  @override
  String get colorStyleSoft => 'Soft';

  @override
  String get colorStyleVibrant => 'Vibrant';

  @override
  String get colorStyleFaithful => 'Faithful';

  @override
  String get colorStyleExpressive => 'Expressive';
}
