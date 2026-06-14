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
  String get chooseWorkspace => 'Choose workspace';

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
  String get noMachinesConfigured => 'No machines configured';

  @override
  String get addMachine => 'Add Machine';

  @override
  String get editMachine => 'Edit Machine';

  @override
  String get saveAndStart => 'Save & Start';

  @override
  String get starting => 'Starting...';

  @override
  String get deleteMachineTitle => 'Delete machine?';

  @override
  String deleteMachineBody(String name) {
    return '\"$name\" and its settings will be removed.';
  }

  @override
  String get validationRequired => 'Required';

  @override
  String get defaultDirectory => 'Default Directory';

  @override
  String get homeDirectoryOnServer => 'Home directory on the server';

  @override
  String get sshSetup => 'SSH Setup';

  @override
  String get sshSetupSubtitle =>
      'Primary path: connect, start OpenCode, then chat';

  @override
  String get sshHost => 'SSH Host';

  @override
  String get sshPort => 'SSH Port';

  @override
  String get sshUsername => 'SSH Username';

  @override
  String get privateKeyPem => 'Private Key (PEM)';

  @override
  String get privateKeyPemHelper =>
      'Paste the full PEM content, or use password below';

  @override
  String get sshPassword => 'SSH Password';

  @override
  String get sshPasswordHelper =>
      'Optional fallback for normal SSH password auth';

  @override
  String get testSsh => 'Test SSH';

  @override
  String get setupOpenCodeViaSsh => 'Setup PAI/OpenCode via SSH';

  @override
  String get directOpenCodeServer => 'Direct OpenCode Server (optional)';

  @override
  String get directOpenCodeServerSubtitle =>
      'Use only if OpenCode is already running';

  @override
  String get openCodeServerUrl => 'OpenCode Server URL';

  @override
  String get openCodeServerUrlHint => 'Auto-derived from SSH host if blank';

  @override
  String get openCodeUsername => 'OpenCode Username';

  @override
  String get openCodeUsernameHelper => 'Defaults to opencode';

  @override
  String get openCodeServerPassword => 'OpenCode Server Password';

  @override
  String get openCodeServerPasswordHelper =>
      'Leave empty to generate a random password on setup';

  @override
  String get timeoutSeconds => 'Timeout (seconds)';

  @override
  String get testDirectServer => 'Test Direct Server';

  @override
  String get connected => 'Connected!';

  @override
  String get fillSshCredentials =>
      'Fill SSH host, username, and password or private key';

  @override
  String sshConnectedAs(String user) {
    return 'SSH connected as $user';
  }

  @override
  String get sshConnectionFailed => 'SSH connection failed';

  @override
  String get settingUpOpenCode => 'Setting up PAI ecosystem';

  @override
  String get connectingOverSsh => 'Connecting over SSH...';

  @override
  String get provisioningDedicatedSshKey =>
      'Generating and installing a dedicated SSH key...';

  @override
  String get installingPaiEcosystem =>
      'Installing or updating the PAI ecosystem...';

  @override
  String get startingPulseBroker => 'Starting the Pulse Broker...';

  @override
  String get locatingOpenCode => 'Locating opencode on the remote machine...';

  @override
  String get installingPaiController =>
      'Installing the pai-opencode controller...';

  @override
  String get startingOpenCodeService => 'Starting the OpenCode service...';

  @override
  String waitingForHttpAttempt(int attempt, int maxAttempts) {
    return 'Waiting for HTTP, attempt $attempt/$maxAttempts...';
  }

  @override
  String get openCodeRunningReachable => 'OpenCode is running and reachable';

  @override
  String openCodeStartedHttpFailed(String message) {
    return 'OpenCode started, but HTTP check failed: $message';
  }

  @override
  String get openCodeMissingRemote =>
      'opencode is not installed on the remote machine';

  @override
  String remoteSetupFailedExit(int exitCode) {
    return 'Remote setup failed (exit $exitCode)';
  }

  @override
  String get remoteSetupFailed => 'Remote setup failed';

  @override
  String get sshBootstrapFailed => 'SSH bootstrap failed';

  @override
  String get serverUrlRequiredUnlessSsh => 'Required unless SSH host is set';

  @override
  String get serverUrlMustStartHttp => 'Must start with http:// or https://';

  @override
  String get timeoutRange => '5-300';

  @override
  String get discardMachineChangesTitle => 'Discard changes?';

  @override
  String get discardMachineChangesBody => 'This machine has unsaved changes.';

  @override
  String get discardProviderChangesBody => 'This provider has unsaved changes.';

  @override
  String get continueEditing => 'Continue editing';

  @override
  String get discard => 'Discard';

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
  String get voiceSectionTitle => 'Voice input';

  @override
  String get voiceConfirmBeforeSendTitle => 'Confirm before sending';

  @override
  String get voiceConfirmBeforeSendSubtitle =>
      'Put speech transcripts in the input box so you can edit them first';

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

  @override
  String get pulseSectionTitle => 'PAI Pulse (voice)';

  @override
  String get pulseEnableTitle => 'Background notifications';

  @override
  String get pulseEnableSubtitle =>
      'Listen to agent progress even with the app in the background';

  @override
  String get pulseMilestones => 'Speak milestones';

  @override
  String get pulseAttention => 'Speak alerts (attention)';

  @override
  String get pulseDigests => 'Speak session digests';
}
