# PAI Mobile M5 — Guia de Testes

## Instalação

✅ **APK instalado com sucesso** no device `RQCX101VW0M`
- Pacote: `com.example.pai_mobile_flutter`
- Versão: 1.0.0+1 (debug)
- Local do APK: `mobile-app/apps/flutter/build/app/outputs/apk/debug/app-debug.apk`

---

## Pré-requisitos para Teste

1. **Configurar servidor OpenCode**
   - Abrir app → "Configure Server"
   - URL do servidor (ex: `http://SEU_IP:4096`)
   - Usuário e senha do OpenCode Server

2. **Tailscale ativo** (se usando em rede privada)

---

## Checklist de Testes por Feature

### ✅ ISC-1/ISC-2 — Modelos Tipados (Foundation)

**Teste:** Abrir o app e navegar pelas telas
- [ ] App abre sem crash
- [ ] Tela de sessões carrega
- [ ] Chat abre corretamente

---

### ✅ ISC-3 — Code Blocks (Syntax Highlighting)

**Teste:** Enviar mensagem que retorne código

```
Prompt sugerido: "Escreve um exemplo de função em Dart que calcula fibonacci"
```

**Verificar:**
- [ ] O código aparece em container com fundo escuro
- [ ] A linguagem aparece no canto superior direito (ex: "dart")
- [ ] O código tem syntax highlighting (palavras-chave coloridas)
- [ ] Botão "Copy" funciona (tocar e colar em outro lugar)

---

### ✅ ISC-4 — Reasoning Inline

**Teste:** Enviar mensagem que faça o agente reasoning

```
Prompt sugerido: "Pensa passo a passo: quanto é 15 x 23?"
```

**Verificar:**
- [ ] Mensagem do agente aparece normalmente
- [ ] Abaixo da mensagem, há um botão "Show reasoning" com ícone 🧠
- [ ] Tocar no botão expande o reasoning inline (não abre modal)
- [ ] Tocar novamente colapsa o reasoning
- [ ] O reasoning tem fundo sutil diferente da mensagem principal

---

### ✅ ISC-5 — Date Headers

**Teste:** Ter mensagens de dias diferentes

```
Sugestão: Se já tiver histórico de dias anteriores, apenas scrollar
```

**Verificar:**
- [ ] Entre mensagens de dias diferentes, há um header centralizado
- [ ] Mensagens de hoje: header diz "Hoje"
- [ ] Mensagens de ontem: header diz "Ontem"
- [ ] Mensagens mais antigas: header mostra "15 de Março" (formato)

---

### ✅ ISC-6 — Tool Calls

**Teste:** Enviar mensagem que use tools

```
Prompt sugerido: "Lista os arquivos do diretório atual usando ls"
```

**Verificar:**
- [ ] Aparece um card com borda colorida indicando tool call
- [ ] Estado **pending**: ícone pulsando laranja, texto "Preparing..."
- [ ] Estado **running**: spinner azul, texto "Running...", nome da tool visível
- [ ] Estado **completed**: check verde ✅, nome da tool, arguments collapsible, resultado visível
- [ ] O resultado pode ser texto markdown ou arquivo
- [ ] Estado **error** (se ocorrer): ícone vermelho ❌ com mensagem de erro

---

### ✅ ISC-7 — Permission Cards

**Teste:** Enviar mensagem que requeira permissão do agente

```
Prompt sugerido: "Edita o arquivo README.md para adicionar 'Hello World' no final"
```

**Verificar:**
- [ ] Aparece um card com borda laranja/âmbar
- [ ] Header com ícone de escudo 🛡️ e texto "Permission Required"
- [ ] Mostra a permissão solicitada (ex: "edit") em monospace
- [ ] Mostra patterns afetados como chips (ex: `README.md`)
- [ ] Três botões de ação:
  - [ ] **"Allow Once"** — autoriza uma vez
  - [ ] **"Always"** — autoriza sempre
  - [ ] **"Deny"** — nega (texto vermelho)
- [ ] Após responder, o card desaparece e a sessão continua

---

### ✅ ISC-8 — Question Cards

**Teste:** Enviar mensagem que faça o agente perguntar algo

```
Prompt sugerido: "Me recomenda uma linguagem de programação"
```

**Verificar:**
- [ ] Aparece um card com borda azul
- [ ] Header com ícone ❓ e texto "Question"
- [ ] Mostra a pergunta completa
- [ ] Opções aparecem como:
  - [ ] Radio buttons (se single choice)
  - [ ] Checkboxes (se multiple choice)
- [ ] Se tiver campo custom, aparece TextField abaixo das opções
- [ ] Botões:
  - [ ] **"Cancel"** — rejeita a pergunta
  - [ ] **"Answer"** — envia a resposta
- [ ] Após responder, o card desaparece

---

### ✅ ISC-9 — Shell Commands

**Teste:** Enviar mensagem que execute shell

```
Prompt sugerido: "Executa 'ls -la' no terminal"
```

**Verificar:**
- [ ] Aparece container escuro estilo terminal
- [ ] Comando em verde com `$` no início
- [ ] Botão de copy ao lado do comando
- [ ] Output scrollable abaixo do comando
- [ ] Botão "Copy output" no final

---

### ✅ ISC-10 — APIs de Reply

**Teste:** Responder permissão ou question

**Verificar:**
- [ ] Ao tocar "Allow Once" em permission, a sessão continua sem erro
- [ ] Ao tocar "Answer" em question, a sessão continua sem erro
- [ ] Não há crash ou freeze

---

### ✅ ISC-11 — Permissões de Device

**Teste:** Verificar permissões no Android

```
Caminho: Android Settings → Apps → PAI → Permissions
```

**Verificar:**
- [ ] Microfone — solicitado e pode ser concedido
- [ ] Câmera — solicitado e pode ser concedido
- [ ] Fotos/Mídia — solicitado e pode ser concedido
- [ ] Notificações — solicitado e pode ser concedido

---

### ✅ ISC-12 — Regressão

**Teste:** Chat de texto simples

```
Prompt sugerido: "Oi, tudo bem?"
```

**Verificar:**
- [ ] Mensagem do usuário aparece normalmente (direita, azul)
- [ ] Resposta do agente aparece normalmente (esquerda, cinza)
- [ ] Markdown funciona (negrito, itálico, listas)
- [ ] Timestamps aparecem
- [ ] Scroll funciona suavemente
- [ ] Input de texto funciona

---

## Fluxos de Teste End-to-End

### Fluxo 1: Chat Completo
1. Abrir app
2. Configurar servidor
3. Criar nova sessão
4. Enviar: "Oi"
5. Verificar resposta normal
6. Enviar: "Escreve um código em Python de hello world"
7. Verificar code block com syntax highlight
8. Enviar: "Pensa passo a passo como fazer isso"
9. Verificar reasoning inline

### Fluxo 2: Tool + Permission
1. Enviar: "Lista os arquivos"
2. Verificar tool call card (running → completed)
3. Enviar: "Edita o README.md"
4. Verificar permission card
5. Tocar "Allow Once"
6. Verificar que a sessão continua

### Fluxo 3: Question
1. Enviar: "Qual sua opinião sobre Dart vs Python?"
2. Se o agente fizer uma question, verificar question card
3. Selecionar opção
4. Tocar "Answer"
5. Verificar que a sessão continua

---

## Comandos Úteis

```bash
# Reinstalar APK após mudanças
cd /home/konanzin/Work/tries/2026-05-28-pai-flutter/Personal_AI_Infrastructure/mobile-app/apps/flutter
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH=$JAVA_HOME/bin:$PATH
flutter build apk --debug --android-skip-build-dependency-validation
adb install -r build/app/outputs/apk/debug/app-debug.apk

# Ver logs do app
adb logcat -s "PAI" "flutter" | grep -i "error\|crash\|exception"

# Limpar dados do app
adb shell pm clear com.example.pai_mobile_flutter
```

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| App crasha ao abrir | Verificar `adb logcat` por erros de inicialização |
| Code block sem cores | Verificar se `flutter_highlight` está no pubspec |
| Tool call não aparece | Verificar se o servidor emitiu eventos SSE |
| Permission card não aparece | Verificar se o servidor enviou `permission.asked` |
| Question card não aparece | Verificar se o servidor enviou `question.asked` |
| Date header errado | Verificar timezone do device |

---

**Status do Build:** ✅ APK Debug instalado e pronto para testes
**Última atualização:** 2026-06-01
