// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'PAI — OpenCode AI';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Salvar';

  @override
  String get delete => 'Excluir';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get dismiss => 'Dispensar';

  @override
  String get stop => 'Parar';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado';

  @override
  String get rename => 'Renomear';

  @override
  String get allow => 'Permitir';

  @override
  String get once => 'Uma vez';

  @override
  String get deny => 'Negar';

  @override
  String get answer => 'Responder';

  @override
  String get switchAction => 'Trocar';

  @override
  String get manage => 'Gerenciar';

  @override
  String get askPaiHint => 'Peça ao PAI...';

  @override
  String get chatEmptyTitle => 'Como posso ajudar?';

  @override
  String get chatEmptySubtitle => 'Envie uma mensagem para começar';

  @override
  String get initializingChat => 'Inicializando o chat...';

  @override
  String get generating => 'Gerando...';

  @override
  String get goToSettings => 'Ir para Configurações';

  @override
  String get serverNotConfigured =>
      'Servidor não configurado. Acesse as Configurações.';

  @override
  String get savedSessionOtherDirectory =>
      'A sessão salva pertencia a outro diretório; começando do zero';

  @override
  String failedLoadHistory(String error) {
    return 'Falha ao carregar o histórico da sessão: $error';
  }

  @override
  String failedCreateSession(String error) {
    return 'Falha ao criar a sessão: $error';
  }

  @override
  String errorWithDetail(String error) {
    return 'Erro: $error';
  }

  @override
  String get camera => 'Câmera';

  @override
  String get gallery => 'Galeria';

  @override
  String get file => 'Arquivo';

  @override
  String get sessionSummarized => 'Sessão resumida';

  @override
  String get noModelsAvailable => 'Nenhum modelo disponível';

  @override
  String get selectModel => 'Selecionar modelo';

  @override
  String get defaultServerModel => 'Padrão do servidor (sem modelo fixo)';

  @override
  String failedLoadModels(String error) {
    return 'Falha ao carregar modelos: $error';
  }

  @override
  String get sessionTodos => 'Tarefas da sessão';

  @override
  String get noTodos => 'Sem tarefas nesta sessão';

  @override
  String shareLinkMessage(String link) {
    return 'Link de compartilhamento: $link';
  }

  @override
  String get shareCreated =>
      'Compartilhamento criado (veja as informações da sessão)';

  @override
  String get noSessionInfo => 'Sem informações da sessão';

  @override
  String get sessionInfo => 'Informações da sessão';

  @override
  String get modelLabel => 'Modelo';

  @override
  String childSessions(int count) {
    return 'Sessões filhas ($count)';
  }

  @override
  String commandExecuted(String command) {
    return 'Comando /$command executado';
  }

  @override
  String commandFailed(String error) {
    return 'Comando falhou: $error';
  }

  @override
  String get todos => 'Tarefas';

  @override
  String get share => 'Compartilhar';

  @override
  String get summarize => 'Resumir';

  @override
  String get searchInChat => 'Buscar no chat...';

  @override
  String get revertChanges => 'Reverter alterações';

  @override
  String get revertChangesSubtitle =>
      'Desfaz as alterações de arquivos desta mensagem';

  @override
  String get reverted => 'Revertido';

  @override
  String get revertFailed => 'Falha ao reverter';

  @override
  String get forkFromHere => 'Ramificar a partir daqui';

  @override
  String get forkSubtitle => 'Cria uma nova sessão a partir deste ponto';

  @override
  String get undo => 'Desfazer';

  @override
  String yesterdayAt(String time) {
    return 'Ontem $time';
  }

  @override
  String get chats => 'Conversas';

  @override
  String get newChat => 'Nova conversa';

  @override
  String get searchChats => 'Buscar conversas...';

  @override
  String get renameSession => 'Renomear sessão';

  @override
  String get name => 'Nome';

  @override
  String get enterSessionName => 'Digite o nome da sessão';

  @override
  String get deleteSessionTitle => 'Excluir sessão?';

  @override
  String deleteConfirmBody(String name) {
    return '\"$name\" será excluída permanentemente.';
  }

  @override
  String get noChatsYet => 'Nenhuma conversa ainda';

  @override
  String get startNewConversation => 'Comece uma nova conversa';

  @override
  String get sessionName => 'Nome da sessão';

  @override
  String get deleteQuestion => 'Excluir?';

  @override
  String get terminal => 'Terminal';

  @override
  String get aiProviders => 'Provedores de IA';

  @override
  String get settings => 'Configurações';

  @override
  String get paiLocked => 'PAI está bloqueado';

  @override
  String get authenticating => 'Autenticando...';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get unlockHintBiometrics =>
      'Desbloqueie com biometria ou PIN do aparelho';

  @override
  String get unlockHintPin => 'Desbloqueie com o PIN do aparelho';

  @override
  String get authCancelledOrFailed => 'A autenticação foi cancelada ou falhou.';

  @override
  String get setupScreenLock =>
      'Configure um bloqueio de tela nas configurações do Android para usar o bloqueio do app.';

  @override
  String get workspace => 'Workspace';

  @override
  String get chooseWorkspace => 'Escolher workspace';

  @override
  String get favorites => 'Favoritos';

  @override
  String get recent => 'Recentes';

  @override
  String get manualPath => 'Caminho manual';

  @override
  String get defaultHome => 'Padrão (~)';

  @override
  String get switchWorkspaceTitle => 'Trocar de workspace?';

  @override
  String get switchWorkspaceBodyStreaming =>
      'Um stream ativo será interrompido e o contexto do chat atual será fechado.';

  @override
  String get switchWorkspaceBody => 'O contexto do chat atual será fechado.';

  @override
  String get machines => 'Máquinas';

  @override
  String get machinesSubtitle =>
      'Configure SSH, faça o bootstrap do OpenCode ou use um servidor direto';

  @override
  String get noMachinesConfigured => 'Nenhuma máquina configurada';

  @override
  String get addMachine => 'Adicionar máquina';

  @override
  String get editMachine => 'Editar máquina';

  @override
  String get saveAndStart => 'Salvar e iniciar';

  @override
  String get starting => 'Iniciando...';

  @override
  String get deleteMachineTitle => 'Excluir máquina?';

  @override
  String deleteMachineBody(String name) {
    return '\"$name\" e suas configurações serão removidas.';
  }

  @override
  String get validationRequired => 'Obrigatório';

  @override
  String get defaultDirectory => 'Diretório padrão';

  @override
  String get homeDirectoryOnServer => 'Diretório inicial no servidor';

  @override
  String get classifierSetup => 'Classificador de prompts';

  @override
  String get classifierSetupSubtitle =>
      'Escolha o modelo que classifica seus prompts neste servidor';

  @override
  String get classifierModelLabel => 'Modelo do classificador';

  @override
  String get classifierModelHelper =>
      'Formato provider/model. Vazio = padrão do servidor.';

  @override
  String get classifierUseLlmLabel => 'Usar classificador LLM';

  @override
  String get classifierUseLlmSubtitle =>
      'Desligado: heurística local, sem custo nem latência';

  @override
  String get classifierConfigUpdated => 'Classificador atualizado no servidor';

  @override
  String get classifierConfigPushFailed =>
      'Falha ao atualizar o classificador via SSH';

  @override
  String get classifierNeedsSsh => 'Configure SSH para alterar o classificador';

  @override
  String get chooseModel => 'Escolher modelo';

  @override
  String get couldNotLoadModels =>
      'Não foi possível carregar os modelos do servidor';

  @override
  String get noModelsFound => 'Nenhum modelo disponível no servidor';

  @override
  String get loadFromServer => 'Carregar do servidor';

  @override
  String get classifierFromServer => 'Carregado do servidor';

  @override
  String get classifierNotOnServer => 'Sem classificador definido no servidor';

  @override
  String get classifierServerReadFailed => 'Não foi possível ler do servidor';

  @override
  String get sshSetup => 'Configuração SSH';

  @override
  String get sshSetupSubtitle =>
      'Caminho principal: conectar, iniciar o OpenCode e conversar';

  @override
  String get sshHost => 'Host SSH';

  @override
  String get sshPort => 'Porta SSH';

  @override
  String get sshUsername => 'Usuário SSH';

  @override
  String get privateKeyPem => 'Chave privada (PEM)';

  @override
  String get privateKeyPemHelper =>
      'Cole o conteúdo PEM completo ou use a senha abaixo';

  @override
  String get sshPassword => 'Senha SSH';

  @override
  String get sshPasswordHelper =>
      'Fallback opcional para autenticação SSH por senha';

  @override
  String get testSsh => 'Testar SSH';

  @override
  String get setupOpenCodeViaSsh => 'Configurar PAI/OpenCode via SSH';

  @override
  String get updatePaiSetup => 'Atualizar PAI nesta máquina';

  @override
  String get updatingPai => 'Atualizando PAI (install.sh --update)...';

  @override
  String get paiUpdated =>
      'PAI atualizado. Reconecte/reinicie o OpenCode para aplicar mudanças de código.';

  @override
  String get paiUpdateFailed => 'Falha ao atualizar o PAI';

  @override
  String get directOpenCodeServer => 'Servidor OpenCode direto (opcional)';

  @override
  String get directOpenCodeServerSubtitle =>
      'Use apenas se o OpenCode já estiver rodando';

  @override
  String get openCodeServerUrl => 'URL do servidor OpenCode';

  @override
  String get openCodeServerUrlHint =>
      'Derivada automaticamente do host SSH se ficar vazia';

  @override
  String get openCodeUsername => 'Usuário OpenCode';

  @override
  String get openCodeUsernameHelper => 'Padrão: opencode';

  @override
  String get openCodeServerPassword => 'Senha do servidor OpenCode';

  @override
  String get openCodeServerPasswordHelper =>
      'Deixe vazia para gerar uma senha aleatória na configuração';

  @override
  String get timeoutSeconds => 'Timeout (segundos)';

  @override
  String get testDirectServer => 'Testar servidor direto';

  @override
  String get connected => 'Conectado!';

  @override
  String get fillSshCredentials =>
      'Preencha host SSH, usuário e senha ou chave privada';

  @override
  String sshConnectedAs(String user) {
    return 'SSH conectado como $user';
  }

  @override
  String get sshConnectionFailed => 'Conexão SSH falhou';

  @override
  String get settingUpOpenCode => 'Configurando ecossistema PAI';

  @override
  String get connectingOverSsh => 'Conectando via SSH...';

  @override
  String get provisioningDedicatedSshKey =>
      'Gerando e instalando uma chave SSH dedicada...';

  @override
  String get installingPaiEcosystem =>
      'Instalando ou atualizando o ecossistema PAI...';

  @override
  String get startingPulseBroker => 'Iniciando o Pulse Broker...';

  @override
  String get locatingOpenCode => 'Localizando opencode na máquina remota...';

  @override
  String get installingPaiController =>
      'Instalando o controlador pai-opencode...';

  @override
  String get startingOpenCodeService => 'Iniciando o serviço OpenCode...';

  @override
  String waitingForHttpAttempt(int attempt, int maxAttempts) {
    return 'Aguardando HTTP, tentativa $attempt/$maxAttempts...';
  }

  @override
  String get openCodeRunningReachable => 'OpenCode está rodando e acessível';

  @override
  String openCodeStartedHttpFailed(String message) {
    return 'OpenCode iniciou, mas a checagem HTTP falhou: $message';
  }

  @override
  String get openCodeMissingRemote =>
      'opencode não está instalado na máquina remota';

  @override
  String remoteSetupFailedExit(int exitCode) {
    return 'Configuração remota falhou (saída $exitCode)';
  }

  @override
  String get remoteSetupFailed => 'Configuração remota falhou';

  @override
  String get sshBootstrapFailed => 'Bootstrap SSH falhou';

  @override
  String get serverUrlRequiredUnlessSsh =>
      'Obrigatório, exceto se o host SSH estiver definido';

  @override
  String get serverUrlMustStartHttp => 'Deve começar com http:// ou https://';

  @override
  String get timeoutRange => '5-300';

  @override
  String get discardMachineChangesTitle => 'Descartar alterações?';

  @override
  String get discardMachineChangesBody =>
      'Esta máquina tem alterações não salvas.';

  @override
  String get discardProviderChangesBody =>
      'Este provedor tem alterações não salvas.';

  @override
  String get continueEditing => 'Continuar editando';

  @override
  String get discard => 'Descartar';

  @override
  String get aiProvidersSubtitle => 'Gerencie os provedores da máquina ativa';

  @override
  String get appearance => 'Aparência';

  @override
  String get systemTheme => 'Sistema';

  @override
  String get lightTheme => 'Claro';

  @override
  String get darkTheme => 'Escuro';

  @override
  String get dynamicColor => 'Cores dinâmicas';

  @override
  String get dynamicColorSubtitle =>
      'Seguir as cores do papel de parede (Material You)';

  @override
  String get accentColor => 'Cor de destaque';

  @override
  String get pureBlack => 'Preto puro (OLED)';

  @override
  String get pureBlackSubtitle => 'Superfícies pretas no tema escuro';

  @override
  String get showThinking => 'Mostrar raciocínio';

  @override
  String get showThinkingSubtitle => 'Exibe as etapas de raciocínio do agente';

  @override
  String get voiceSectionTitle => 'Entrada por voz';

  @override
  String get voiceConfirmBeforeSendTitle => 'Confirmar antes de enviar';

  @override
  String get voiceConfirmBeforeSendSubtitle =>
      'Coloca transcrições de fala no campo de texto para você editar antes';

  @override
  String get security => 'Segurança';

  @override
  String get appLock => 'Bloqueio do app';

  @override
  String get appLockSubtitleAvailable =>
      'Usa biometria, PIN, senha ou padrão do Android';

  @override
  String get appLockSubtitleUnavailable =>
      'Configure um bloqueio de tela no Android primeiro';

  @override
  String get lockTimeout => 'Tempo de bloqueio';

  @override
  String get permissionRequired => 'Permissão necessária';

  @override
  String get paiWantsToExecute => 'O PAI quer executar:';

  @override
  String get patternsAffected => 'Padrões afetados:';

  @override
  String get question => 'Pergunta';

  @override
  String get answered => 'Respondida';

  @override
  String get customAnswerHint => 'Resposta personalizada...';

  @override
  String get micPermissionNeeded => 'Permissão de microfone necessária';

  @override
  String get welcomeSubtitle => 'Seu assistente pessoal de IA';

  @override
  String get setUpMachine => 'Configurar máquina';

  @override
  String get browseFolders => 'Procurar pastas';

  @override
  String get useThisFolder => 'Usar esta pasta';

  @override
  String get couldNotListFolder => 'Não foi possível listar a pasta';

  @override
  String get noSubfolders => 'Sem subpastas';

  @override
  String get colorStyle => 'Estilo de cor';

  @override
  String get colorStyleSoft => 'Suave';

  @override
  String get colorStyleVibrant => 'Vibrante';

  @override
  String get colorStyleFaithful => 'Fiel';

  @override
  String get colorStyleExpressive => 'Expressivo';

  @override
  String get pulseSectionTitle => 'PAI Pulse (voz)';

  @override
  String get pulseEnableTitle => 'Notificações em segundo plano';

  @override
  String get pulseEnableSubtitle =>
      'Ouça o progresso dos agentes mesmo com o app em segundo plano';

  @override
  String get pulseMilestones => 'Falar marcos (milestones)';

  @override
  String get pulseAttention => 'Falar alertas (attention)';

  @override
  String get pulseDigests => 'Falar resumos de sessão';
}
