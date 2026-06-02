# Guia de Testes - PAI Mobile Client

## Pré-requisitos

- Servidor opencode rodando: `opencode serve` (porta 4096)
- Tunnel ADB ativo: `adb reverse tcp:4096 tcp:4096`
- App instalado no device

---

## 1. Envio de mensagem básica

- Abra qualquer sessão ou crie uma nova
- Digite algo simples como "oi" e envie
- **Verificar**: mensagem aparece, resposta chega, sem crash

## 2. Stop button

- Envie um prompt que gere resposta longa, ex: "explique detalhadamente como funciona o protocolo TCP/IP"
- **Verificar**: botão "Stop" aparece abaixo da mensagem durante streaming
- Toque em Stop
- **Verificar**: streaming para imediatamente

## 3. Menu "..." (canto superior direito)

Abra o menu e teste cada opção:

### a) Session Info

- **Verificar**: bottom sheet com Model, Agent, Cost, Tokens, ID formatados

### b) Change Model

- **Verificar**: lista de modelos aparece, "Default (server)" com check
- Selecione outro modelo e envie uma mensagem
- **Verificar**: subtítulo na AppBar muda para o modelo selecionado

### c) View Todos

- Funciona melhor em sessão que tenha gerado TODOs
- **Verificar**: bottom sheet abre (mesmo que vazio)

### d) Share Session

- **Verificar**: snackbar de confirmação aparece

## 4. Long press em mensagem

- Segure pressionado em qualquer bolha de resposta do agente
- **Verificar**: menu com "Copy", "Revert changes", "Fork from here"
- Teste "Copy" e cole em algum app
- Teste "Fork from here" — deve criar nova sessão

## 5. Tool calls inline

- Envie: "liste os arquivos do diretório atual"
- **Verificar**: tool call aparece inline no balão, ex: `$ ls -la ✓`
- **Verificar**: ordem cronológica (primeira tool no topo)

## 6. Code blocks grandes (fix da tela vermelha)

- Abra a sessão "Diretório atual e saudação"
- **Verificar**: sem tela vermelha, code blocks grandes renderizam como texto plain

## 7. Pergunta interativa (question)

- Envie algo que gere pergunta, ex: "faça um grep recursivo por TODO"
- O agente deve perguntar qual diretório/padrão
- **Verificar**: card de pergunta aparece com opções
- Responda
- **Verificar**: resposta fica grifada inline no balão, agente continua respondendo

## 8. Permissão (permission)

- Envie: "delete o arquivo /tmp/test_delete_me.txt" (crie antes com `touch /tmp/test_delete_me.txt`)
- **Verificar**: card de permissão aparece com botões em uma linha só
- Toque "Allow" ou "Deny"

## 9. Slash commands

- No campo de texto, digite `/compact` e envie
- **Verificar**: comando é executado (sem crash), pode aparecer snackbar

## 10. Rehydration

- Abra uma sessão que tenha tool calls e perguntas respondidas
- Saia (back) e volte a entrar
- **Verificar**: tool calls, shell commands e respostas continuam visíveis

## 11. Show reasoning

- Em qualquer mensagem com "Show reasoning", toque
- **Verificar**: texto de reasoning expande/colapsa

## 12. Conexão offline/online

- Mate o servidor opencode (Ctrl+C)
- **Verificar**: ícone no AppBar muda para offline (nuvem vermelha)
- Reinicie o servidor
- **Verificar**: reconecta automaticamente, ícone volta a verde
