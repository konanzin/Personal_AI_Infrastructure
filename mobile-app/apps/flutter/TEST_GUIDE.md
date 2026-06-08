# Guia de Testes - PAI Mobile Client

> Atualizado em 2026-06-08. `flutter analyze` e `flutter test` passam localmente. O smoke core no Android `a51` passou via ADB reverse; este guia cobre repetição e os fluxos live restantes.

## Pré-requisitos

- Servidor OpenCode rodando: `opencode serve --hostname 0.0.0.0 --port 4096` para Tailscale, ou `opencode serve` com ADB reverse.
- Se usar ADB local: `adb reverse tcp:4096 tcp:4096`.
- App instalado no device.

Se o build Android falhar usando Java 26, rode o build com Java 17 nesta máquina:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="$JAVA_HOME/bin:$PATH"
flutter build apk --debug
```

## Último Smoke Live Registrado

- Device: `a51` / SM-A515F, Android 13.
- Transporte: `adb reverse tcp:4096 tcp:4096`.
- Servidor: OpenCode `1.16.2`.
- Modelo: `kimi-for-coding/k2p6`.
- Prompt: `Run pwd using shell and reply DONE2`.
- Resultado: resposta `DONE2`, rich block `bash`, reidratação após reabrir sessão e nenhum timeout/erro de envio no logcat.

## 1. Envio de mensagem básica

- Abra qualquer sessão ou crie uma nova.
- Digite algo simples como "oi" e envie.
- Verificar: mensagem aparece, resposta chega, sem crash.

## 2. Stop Button

- Envie um prompt que gere resposta longa, como "explique detalhadamente como funciona o protocolo TCP/IP".
- Verificar: botão "Stop" aparece abaixo da mensagem durante streaming.
- Toque em Stop.
- Verificar: streaming para imediatamente.

## 3. Menu "..."

Teste cada opção:

- Session Info: bottom sheet com Model, Agent, Cost, Tokens, ID.
- Change Model: lista de modelos aparece, "Default (server)" com check.
- View Todos: bottom sheet abre, mesmo vazio.
- Share Session: snackbar de confirmação aparece.

## 4. Long Press Em Mensagem

- Segure pressionado em uma resposta do agente.
- Verificar: menu com "Copy", "Revert changes", "Fork from here".
- Teste Copy e Fork.

## 5. Tool Calls Ricos

- Envie: "liste os arquivos do diretório atual".
- Verificar: tool call aparece como bloco rico na timeline, não como snippet Markdown dentro de uma bolha do agente.
- Verificar: estados pending/running/completed/error aparecem corretamente.

## 6. Shell Commands Ricos

- Envie um prompt que execute shell.
- Verificar: comando e output aparecem no `ShellCommandBubble`.
- Verificar: copy do comando/output funciona.

## 7. Code Blocks Grandes

- Envie um prompt que gere um bloco de código grande.
- Verificar: sem tela vermelha; code blocks renderizam corretamente.

## 8. Pergunta Interativa

- Envie algo que gere pergunta, como "faça um grep recursivo por TODO".
- Verificar: card de pergunta aparece com opções.
- Responda.
- Verificar: resposta fica inline na mensagem do agente e o agente continua respondendo.

## 9. Permissão

- Crie um arquivo temporário e envie um prompt que demande alteração/deleção.
- Verificar: card de permissão aparece com `Deny`, `Once`, `Always`.
- Responda.
- Verificar: stream continua após a resposta.

## 10. Slash Commands

- No campo de texto, digite `/compact` e envie.
- Verificar: comando é executado sem crash.

## 11. Rehydration

- Abra uma sessão que tenha tool calls, shell commands e perguntas respondidas.
- Saia e volte a entrar.
- Verificar: tool calls, shell commands e respostas continuam visíveis e associados à mensagem correta.

## 12. Reasoning

- Em qualquer mensagem com "Show reasoning", toque.
- Verificar: texto de reasoning expande/colapsa.

## 13. Conexão Offline/Online

- Pare o servidor OpenCode.
- Verificar: ícone no AppBar muda para offline.
- Reinicie o servidor.
- Verificar: reconecta automaticamente.

## Comandos Locais

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
```
