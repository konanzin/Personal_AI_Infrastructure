import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

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
    Locale('pt')
  ];

  /// No description provided for @appTitle.
  ///
  /// In pt, this message translates to:
  /// **'PAI — OpenCode AI'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In pt, this message translates to:
  /// **'Salvar'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In pt, this message translates to:
  /// **'Excluir'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In pt, this message translates to:
  /// **'Tentar novamente'**
  String get retry;

  /// No description provided for @dismiss.
  ///
  /// In pt, this message translates to:
  /// **'Dispensar'**
  String get dismiss;

  /// No description provided for @stop.
  ///
  /// In pt, this message translates to:
  /// **'Parar'**
  String get stop;

  /// No description provided for @copy.
  ///
  /// In pt, this message translates to:
  /// **'Copiar'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In pt, this message translates to:
  /// **'Copiado'**
  String get copied;

  /// No description provided for @rename.
  ///
  /// In pt, this message translates to:
  /// **'Renomear'**
  String get rename;

  /// No description provided for @allow.
  ///
  /// In pt, this message translates to:
  /// **'Permitir'**
  String get allow;

  /// No description provided for @once.
  ///
  /// In pt, this message translates to:
  /// **'Uma vez'**
  String get once;

  /// No description provided for @deny.
  ///
  /// In pt, this message translates to:
  /// **'Negar'**
  String get deny;

  /// No description provided for @answer.
  ///
  /// In pt, this message translates to:
  /// **'Responder'**
  String get answer;

  /// No description provided for @switchAction.
  ///
  /// In pt, this message translates to:
  /// **'Trocar'**
  String get switchAction;

  /// No description provided for @manage.
  ///
  /// In pt, this message translates to:
  /// **'Gerenciar'**
  String get manage;

  /// No description provided for @askPaiHint.
  ///
  /// In pt, this message translates to:
  /// **'Peça ao PAI...'**
  String get askPaiHint;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In pt, this message translates to:
  /// **'Como posso ajudar?'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptySubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Envie uma mensagem para começar'**
  String get chatEmptySubtitle;

  /// No description provided for @initializingChat.
  ///
  /// In pt, this message translates to:
  /// **'Inicializando o chat...'**
  String get initializingChat;

  /// No description provided for @generating.
  ///
  /// In pt, this message translates to:
  /// **'Gerando...'**
  String get generating;

  /// No description provided for @goToSettings.
  ///
  /// In pt, this message translates to:
  /// **'Ir para Configurações'**
  String get goToSettings;

  /// No description provided for @serverNotConfigured.
  ///
  /// In pt, this message translates to:
  /// **'Servidor não configurado. Acesse as Configurações.'**
  String get serverNotConfigured;

  /// No description provided for @savedSessionOtherDirectory.
  ///
  /// In pt, this message translates to:
  /// **'A sessão salva pertencia a outro diretório; começando do zero'**
  String get savedSessionOtherDirectory;

  /// No description provided for @failedLoadHistory.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao carregar o histórico da sessão: {error}'**
  String failedLoadHistory(String error);

  /// No description provided for @failedCreateSession.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao criar a sessão: {error}'**
  String failedCreateSession(String error);

  /// No description provided for @errorWithDetail.
  ///
  /// In pt, this message translates to:
  /// **'Erro: {error}'**
  String errorWithDetail(String error);

  /// No description provided for @camera.
  ///
  /// In pt, this message translates to:
  /// **'Câmera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In pt, this message translates to:
  /// **'Galeria'**
  String get gallery;

  /// No description provided for @file.
  ///
  /// In pt, this message translates to:
  /// **'Arquivo'**
  String get file;

  /// No description provided for @sessionSummarized.
  ///
  /// In pt, this message translates to:
  /// **'Sessão resumida'**
  String get sessionSummarized;

  /// No description provided for @noModelsAvailable.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum modelo disponível'**
  String get noModelsAvailable;

  /// No description provided for @selectModel.
  ///
  /// In pt, this message translates to:
  /// **'Selecionar modelo'**
  String get selectModel;

  /// No description provided for @defaultServerModel.
  ///
  /// In pt, this message translates to:
  /// **'Padrão (servidor)'**
  String get defaultServerModel;

  /// No description provided for @failedLoadModels.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao carregar modelos: {error}'**
  String failedLoadModels(String error);

  /// No description provided for @sessionTodos.
  ///
  /// In pt, this message translates to:
  /// **'Tarefas da sessão'**
  String get sessionTodos;

  /// No description provided for @noTodos.
  ///
  /// In pt, this message translates to:
  /// **'Sem tarefas nesta sessão'**
  String get noTodos;

  /// No description provided for @shareLinkMessage.
  ///
  /// In pt, this message translates to:
  /// **'Link de compartilhamento: {link}'**
  String shareLinkMessage(String link);

  /// No description provided for @shareCreated.
  ///
  /// In pt, this message translates to:
  /// **'Compartilhamento criado (veja as informações da sessão)'**
  String get shareCreated;

  /// No description provided for @noSessionInfo.
  ///
  /// In pt, this message translates to:
  /// **'Sem informações da sessão'**
  String get noSessionInfo;

  /// No description provided for @sessionInfo.
  ///
  /// In pt, this message translates to:
  /// **'Informações da sessão'**
  String get sessionInfo;

  /// No description provided for @modelLabel.
  ///
  /// In pt, this message translates to:
  /// **'Modelo'**
  String get modelLabel;

  /// No description provided for @childSessions.
  ///
  /// In pt, this message translates to:
  /// **'Sessões filhas ({count})'**
  String childSessions(int count);

  /// No description provided for @commandExecuted.
  ///
  /// In pt, this message translates to:
  /// **'Comando /{command} executado'**
  String commandExecuted(String command);

  /// No description provided for @commandFailed.
  ///
  /// In pt, this message translates to:
  /// **'Comando falhou: {error}'**
  String commandFailed(String error);

  /// No description provided for @todos.
  ///
  /// In pt, this message translates to:
  /// **'Tarefas'**
  String get todos;

  /// No description provided for @share.
  ///
  /// In pt, this message translates to:
  /// **'Compartilhar'**
  String get share;

  /// No description provided for @summarize.
  ///
  /// In pt, this message translates to:
  /// **'Resumir'**
  String get summarize;

  /// No description provided for @searchInChat.
  ///
  /// In pt, this message translates to:
  /// **'Buscar no chat...'**
  String get searchInChat;

  /// No description provided for @revertChanges.
  ///
  /// In pt, this message translates to:
  /// **'Reverter alterações'**
  String get revertChanges;

  /// No description provided for @revertChangesSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Desfaz as alterações de arquivos desta mensagem'**
  String get revertChangesSubtitle;

  /// No description provided for @reverted.
  ///
  /// In pt, this message translates to:
  /// **'Revertido'**
  String get reverted;

  /// No description provided for @revertFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao reverter'**
  String get revertFailed;

  /// No description provided for @forkFromHere.
  ///
  /// In pt, this message translates to:
  /// **'Ramificar a partir daqui'**
  String get forkFromHere;

  /// No description provided for @forkSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Cria uma nova sessão a partir deste ponto'**
  String get forkSubtitle;

  /// No description provided for @undo.
  ///
  /// In pt, this message translates to:
  /// **'Desfazer'**
  String get undo;

  /// No description provided for @yesterdayAt.
  ///
  /// In pt, this message translates to:
  /// **'Ontem {time}'**
  String yesterdayAt(String time);

  /// No description provided for @chats.
  ///
  /// In pt, this message translates to:
  /// **'Conversas'**
  String get chats;

  /// No description provided for @newChat.
  ///
  /// In pt, this message translates to:
  /// **'Nova conversa'**
  String get newChat;

  /// No description provided for @searchChats.
  ///
  /// In pt, this message translates to:
  /// **'Buscar conversas...'**
  String get searchChats;

  /// No description provided for @renameSession.
  ///
  /// In pt, this message translates to:
  /// **'Renomear sessão'**
  String get renameSession;

  /// No description provided for @name.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get name;

  /// No description provided for @enterSessionName.
  ///
  /// In pt, this message translates to:
  /// **'Digite o nome da sessão'**
  String get enterSessionName;

  /// No description provided for @deleteSessionTitle.
  ///
  /// In pt, this message translates to:
  /// **'Excluir sessão?'**
  String get deleteSessionTitle;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In pt, this message translates to:
  /// **'\"{name}\" será excluída permanentemente.'**
  String deleteConfirmBody(String name);

  /// No description provided for @noChatsYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma conversa ainda'**
  String get noChatsYet;

  /// No description provided for @startNewConversation.
  ///
  /// In pt, this message translates to:
  /// **'Comece uma nova conversa'**
  String get startNewConversation;

  /// No description provided for @sessionName.
  ///
  /// In pt, this message translates to:
  /// **'Nome da sessão'**
  String get sessionName;

  /// No description provided for @deleteQuestion.
  ///
  /// In pt, this message translates to:
  /// **'Excluir?'**
  String get deleteQuestion;

  /// No description provided for @terminal.
  ///
  /// In pt, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @aiProviders.
  ///
  /// In pt, this message translates to:
  /// **'Provedores de IA'**
  String get aiProviders;

  /// No description provided for @settings.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get settings;

  /// No description provided for @paiLocked.
  ///
  /// In pt, this message translates to:
  /// **'PAI está bloqueado'**
  String get paiLocked;

  /// No description provided for @authenticating.
  ///
  /// In pt, this message translates to:
  /// **'Autenticando...'**
  String get authenticating;

  /// No description provided for @unlock.
  ///
  /// In pt, this message translates to:
  /// **'Desbloquear'**
  String get unlock;

  /// No description provided for @unlockHintBiometrics.
  ///
  /// In pt, this message translates to:
  /// **'Desbloqueie com biometria ou PIN do aparelho'**
  String get unlockHintBiometrics;

  /// No description provided for @unlockHintPin.
  ///
  /// In pt, this message translates to:
  /// **'Desbloqueie com o PIN do aparelho'**
  String get unlockHintPin;

  /// No description provided for @authCancelledOrFailed.
  ///
  /// In pt, this message translates to:
  /// **'A autenticação foi cancelada ou falhou.'**
  String get authCancelledOrFailed;

  /// No description provided for @setupScreenLock.
  ///
  /// In pt, this message translates to:
  /// **'Configure um bloqueio de tela nas configurações do Android para usar o bloqueio do app.'**
  String get setupScreenLock;

  /// No description provided for @workspace.
  ///
  /// In pt, this message translates to:
  /// **'Workspace'**
  String get workspace;

  /// No description provided for @chooseWorkspace.
  ///
  /// In pt, this message translates to:
  /// **'Escolher workspace'**
  String get chooseWorkspace;

  /// No description provided for @favorites.
  ///
  /// In pt, this message translates to:
  /// **'Favoritos'**
  String get favorites;

  /// No description provided for @recent.
  ///
  /// In pt, this message translates to:
  /// **'Recentes'**
  String get recent;

  /// No description provided for @manualPath.
  ///
  /// In pt, this message translates to:
  /// **'Caminho manual'**
  String get manualPath;

  /// No description provided for @defaultHome.
  ///
  /// In pt, this message translates to:
  /// **'Padrão (~)'**
  String get defaultHome;

  /// No description provided for @switchWorkspaceTitle.
  ///
  /// In pt, this message translates to:
  /// **'Trocar de workspace?'**
  String get switchWorkspaceTitle;

  /// No description provided for @switchWorkspaceBodyStreaming.
  ///
  /// In pt, this message translates to:
  /// **'Um stream ativo será interrompido e o contexto do chat atual será fechado.'**
  String get switchWorkspaceBodyStreaming;

  /// No description provided for @switchWorkspaceBody.
  ///
  /// In pt, this message translates to:
  /// **'O contexto do chat atual será fechado.'**
  String get switchWorkspaceBody;

  /// No description provided for @machines.
  ///
  /// In pt, this message translates to:
  /// **'Máquinas'**
  String get machines;

  /// No description provided for @machinesSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Configure SSH, faça o bootstrap do OpenCode ou use um servidor direto'**
  String get machinesSubtitle;

  /// No description provided for @aiProvidersSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Gerencie os provedores da máquina ativa'**
  String get aiProvidersSubtitle;

  /// No description provided for @appearance.
  ///
  /// In pt, this message translates to:
  /// **'Aparência'**
  String get appearance;

  /// No description provided for @systemTheme.
  ///
  /// In pt, this message translates to:
  /// **'Sistema'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In pt, this message translates to:
  /// **'Claro'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In pt, this message translates to:
  /// **'Escuro'**
  String get darkTheme;

  /// No description provided for @dynamicColor.
  ///
  /// In pt, this message translates to:
  /// **'Cores dinâmicas'**
  String get dynamicColor;

  /// No description provided for @dynamicColorSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Seguir as cores do papel de parede (Material You)'**
  String get dynamicColorSubtitle;

  /// No description provided for @accentColor.
  ///
  /// In pt, this message translates to:
  /// **'Cor de destaque'**
  String get accentColor;

  /// No description provided for @pureBlack.
  ///
  /// In pt, this message translates to:
  /// **'Preto puro (OLED)'**
  String get pureBlack;

  /// No description provided for @pureBlackSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Superfícies pretas no tema escuro'**
  String get pureBlackSubtitle;

  /// No description provided for @showThinking.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar raciocínio'**
  String get showThinking;

  /// No description provided for @showThinkingSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Exibe as etapas de raciocínio do agente'**
  String get showThinkingSubtitle;

  /// No description provided for @security.
  ///
  /// In pt, this message translates to:
  /// **'Segurança'**
  String get security;

  /// No description provided for @appLock.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueio do app'**
  String get appLock;

  /// No description provided for @appLockSubtitleAvailable.
  ///
  /// In pt, this message translates to:
  /// **'Usa biometria, PIN, senha ou padrão do Android'**
  String get appLockSubtitleAvailable;

  /// No description provided for @appLockSubtitleUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Configure um bloqueio de tela no Android primeiro'**
  String get appLockSubtitleUnavailable;

  /// No description provided for @lockTimeout.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de bloqueio'**
  String get lockTimeout;

  /// No description provided for @permissionRequired.
  ///
  /// In pt, this message translates to:
  /// **'Permissão necessária'**
  String get permissionRequired;

  /// No description provided for @paiWantsToExecute.
  ///
  /// In pt, this message translates to:
  /// **'O PAI quer executar:'**
  String get paiWantsToExecute;

  /// No description provided for @patternsAffected.
  ///
  /// In pt, this message translates to:
  /// **'Padrões afetados:'**
  String get patternsAffected;

  /// No description provided for @question.
  ///
  /// In pt, this message translates to:
  /// **'Pergunta'**
  String get question;

  /// No description provided for @answered.
  ///
  /// In pt, this message translates to:
  /// **'Respondida'**
  String get answered;

  /// No description provided for @customAnswerHint.
  ///
  /// In pt, this message translates to:
  /// **'Resposta personalizada...'**
  String get customAnswerHint;

  /// No description provided for @micPermissionNeeded.
  ///
  /// In pt, this message translates to:
  /// **'Permissão de microfone necessária'**
  String get micPermissionNeeded;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Seu assistente pessoal de IA'**
  String get welcomeSubtitle;

  /// No description provided for @setUpMachine.
  ///
  /// In pt, this message translates to:
  /// **'Configurar máquina'**
  String get setUpMachine;

  /// No description provided for @browseFolders.
  ///
  /// In pt, this message translates to:
  /// **'Procurar pastas'**
  String get browseFolders;

  /// No description provided for @useThisFolder.
  ///
  /// In pt, this message translates to:
  /// **'Usar esta pasta'**
  String get useThisFolder;

  /// No description provided for @couldNotListFolder.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível listar a pasta'**
  String get couldNotListFolder;

  /// No description provided for @noSubfolders.
  ///
  /// In pt, this message translates to:
  /// **'Sem subpastas'**
  String get noSubfolders;

  /// No description provided for @colorStyle.
  ///
  /// In pt, this message translates to:
  /// **'Estilo de cor'**
  String get colorStyle;

  /// No description provided for @colorStyleSoft.
  ///
  /// In pt, this message translates to:
  /// **'Suave'**
  String get colorStyleSoft;

  /// No description provided for @colorStyleVibrant.
  ///
  /// In pt, this message translates to:
  /// **'Vibrante'**
  String get colorStyleVibrant;

  /// No description provided for @colorStyleFaithful.
  ///
  /// In pt, this message translates to:
  /// **'Fiel'**
  String get colorStyleFaithful;

  /// No description provided for @colorStyleExpressive.
  ///
  /// In pt, this message translates to:
  /// **'Expressivo'**
  String get colorStyleExpressive;

  /// No description provided for @pulseSectionTitle.
  ///
  /// In pt, this message translates to:
  /// **'PAI Pulse (voz)'**
  String get pulseSectionTitle;

  /// No description provided for @pulseEnableTitle.
  ///
  /// In pt, this message translates to:
  /// **'Notificações em segundo plano'**
  String get pulseEnableTitle;

  /// No description provided for @pulseEnableSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Ouça o progresso dos agentes mesmo com o app em segundo plano'**
  String get pulseEnableSubtitle;

  /// No description provided for @pulseMilestones.
  ///
  /// In pt, this message translates to:
  /// **'Falar marcos (milestones)'**
  String get pulseMilestones;

  /// No description provided for @pulseAttention.
  ///
  /// In pt, this message translates to:
  /// **'Falar alertas (attention)'**
  String get pulseAttention;

  /// No description provided for @pulseDigests.
  ///
  /// In pt, this message translates to:
  /// **'Falar resumos de sessão'**
  String get pulseDigests;
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
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
