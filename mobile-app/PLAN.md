# PAI Mobile — Plano Inicial de Desenvolvimento

## 1. Contexto

O PAI hoje vive no desktop via OpenCode CLI/TUI. O objetivo deste projeto é criar a interface mobile privada do Digital Assistant, preservando a identidade do PAI como Life OS e evitando transformar o app em um chatbot genérico.

Este app **não é um produto público agora**. Ele é a interface móvel do meu agente, operando em ambiente privado, com foco em privacidade e controle.

## 2. Tese do Produto

O PAI Mobile deve ser:

- **voz-first** como interface principal
- **chat-enabled** como modo de inspeção, correção e granularidade
- **remote do PAI**, não um cliente IA independente
- **privado por arquitetura**, usando rede Tailscale
- **fino no mobile e centralizado no backend**, com o OpenCode Server como fonte de verdade

## 3. Decisões já tomadas

| Área | Decisão |
|---|---|
| Mobile stack | React Native + Expo |
| Backend | OpenCode Server (`opencode serve`) |
| Conectividade | Tailscale + VPS / host privado |
| Autenticação inicial | Basic Auth nativa do OpenCode Server |
| Cliente API | SDK HTTP custom (`fetch`) |
| Posicionamento | App privado do meu DA, não produto público |
| Interação | Voz principal + chat complementar |
| Base UI/UX | Material 3 (`https://m3.material.io/get-started`) |

## 4. O que o app é — e o que não é

### É

- A interface mobile do meu Digital Assistant
- Um remote do meu Life OS
- Um ponto de entrada para sessões, continuidade e notificações
- Um app orientado a contexto pessoal, não a prompts isolados

### Não é

- Um ChatGPT mobile genérico
- Um IDE mobile
- Um backend paralelo ao PAI
- Um app público pensado para onboarding de massa

## 5. Princípios de arquitetura

1. **OpenCode Server continua sendo o cérebro**  
   O app não duplica lógica de agentes, memória, skills ou estado central.

2. **Mobile é interface, não centro de processamento**  
   O celular deve orquestrar interação, não reinventar o backend.

3. **Privacidade antes de conveniência pública**  
   Tailscale é uma escolha deliberada, não uma limitação provisória.

4. **Voz é identidade; chat é precisão**  
   O app precisa suportar ambos sem virar apenas “uma tela de chat”.

5. **Confiabilidade é mais importante que amplitude de features**  
   O alpha precisa funcionar de forma previsível antes de expandir escopo.

6. **Base visual consistente desde o início**  
   A fundação de UI/UX parte de Material 3 como sistema base, adaptado à identidade do PAI.

## 6. MVP / Alpha inicial

Como este projeto é privado e pessoal, o primeiro alvo prático é um **alpha funcional**.

### Incluído

1. **Modo Voz**
   - botão principal para falar
   - transcrição de voz para texto
   - envio da mensagem ao OpenCode Server
   - feedback visual de estado: ouvindo / enviando / processando / respondendo

2. **Modo Chat**
   - histórico de mensagens
   - input manual de texto
   - renderização básica de markdown
   - uso como fallback e modo de inspeção

3. **Sessões**
   - listar sessões existentes
   - criar nova sessão
   - abrir sessão existente
   - retomar contexto recente

4. **Configuração**
   - host / porta / URL do OpenCode Server na tailnet
   - usuário / senha
   - armazenamento seguro de credenciais

5. **Tema**
   - claro / escuro

6. **Notificações**
   - agente precisa de input/permissão
   - trabalho concluído
   - notificação agendada

## 7. Fora de escopo neste momento

- edição de arquivos
- shell remoto
- offline real
- fila offline complexa
- múltiplos servidores
- skills UI completa
- dashboard Pulse completo
- automações avançadas em background

## 8. Riscos principais que já identificamos

### 8.1 SSE em mobile

Risco real:
- app indo para background
- queda de conexão
- resume inconsistente
- reconexão sem replay de eventos

Implicação: o app não pode depender de SSE “ingênuo”.

### 8.2 Voz como fluxo principal

Risco real:
- STT ruim em pt-BR
- permissões de microfone
- ruído / latência
- UX quebrando quando a fala falha

Implicação: voz precisa ser principal **sem eliminar o chat**.

### 8.3 Basic Auth

Risco real:
- ergonomia limitada
- revogação ruim
- pouca granularidade por device

Implicação: aceitável no começo, mas provavelmente temporário.

### 8.4 Tailscale

Risco real:
- dependência do app Tailscale ativo
- possíveis problemas de rede no mobile

Implicação: aceitável porque o app é privado, mas deve ser explicitamente tratado como pré-requisito operacional.

### 8.5 Push notifications

Risco real:
- falta de modelagem de evento
- correlação ruim com sessão
- duplicidade
- deep link incompleto

Implicação: push precisa ser modelado como parte da arquitetura, não como detalhe de UI.

## 9. Decisões de engenharia da experiência

### 9.1 Modelo de interação

O desenho base deve ser:

- **Tela principal = voz-first**
- **Tela de conversa = chat-first**
- **Push = mecanismo de reentrada**
- **Sessões = continuidade operacional**

### 9.2 Regra central de UX

Se voz falhar, o usuário não pode ficar preso.  
O sistema deve permitir:

- revisar transcrição
- corrigir texto
- reenviar
- continuar via chat

### 9.3 Meta de experiência

O app deve parecer “estou falando com meu assistant”, não “estou preenchendo um formulário de prompt”.

## 10. Fundações técnicas que precisam existir cedo

Esses itens são mais importantes que várias features visíveis:

1. **Modelo de conexão**
   - connecting
   - connected
   - streaming
   - stale
   - auth_failed
   - offline

2. **Modelo de mensagens/eventos**
   - IDs estáveis
   - ordenação
   - deduplicação
   - correlação com sessão

3. **Reconexão**
   - reconnect automático
   - reidratação de sessão
   - mecanismo de recuperação ao voltar do background

4. **Segurança local**
   - credenciais no SecureStore
   - remoção segura de sessão local

5. **Observabilidade mínima**
   - erros de conexão
   - falhas de auth
   - falhas de transcrição
   - falhas de streaming

## 11. Fases de desenvolvimento

### Fase 0 — Discovery técnico curto

Objetivo: reduzir incerteza das apostas principais.

Entregáveis:
- prova de conexão do app com OpenCode Server via Tailscale
- prova de streaming/resposta em sessão
- prova de captura/transcrição de voz no dispositivo

### Fase 1 — Spine funcional

Objetivo: fechar o ciclo mínimo end-to-end.

Entregáveis:
- bootstrap do app Expo
- tela de configuração
- secure storage
- listagem / abertura de sessões
- chat funcional básico
- envio/recebimento de mensagens

### Fase 2 — Voice-first loop

Objetivo: transformar o app em assistant, não apenas chat.

Entregáveis:
- botão de voz principal
- transcrição
- revisão opcional da transcrição
- envio da fala ao backend
- estados visuais completos

### Fase 3 — Resiliência operacional

Objetivo: o app sobreviver ao uso real.

Entregáveis:
- reconexão
- resume de sessão
- restauração após background
- notificações integradas ao fluxo

### Fase 4 — Alpha utilizável

Objetivo: uso pessoal recorrente no dia a dia.

Entregáveis:
- UX refinada
- bugs principais resolvidos
- fluxo básico confiável em iOS e Android

## 12. Primeiros passos práticos

### Passo 1 — Scaffold do app

Criar o projeto Expo em TypeScript e definir estrutura inicial:

- `app/` ou `src/`
- `features/chat`
- `features/voice`
- `features/sessions`
- `features/settings`
- `shared/api`
- `shared/state`
- `shared/storage`

### Passo 2 — Prova de conectividade

Implementar uma tela mínima que:

- recebe URL do server
- recebe credenciais
- testa conexão
- valida resposta do OpenCode Server

### Passo 3 — Modelar o cliente API

Definir um client único para:

- auth
- listar sessões
- criar sessão
- enviar mensagem
- consumir streaming / eventos

### Passo 4 — Prova de chat funcional

Entregar uma primeira tela de conversa capaz de:

- abrir sessão
- enviar mensagem de texto
- renderizar resposta

### Passo 5 — Spike de voz

Testar a biblioteca/abordagem de voz escolhida e validar:

- qualidade em pt-BR
- latência
- permissões
- compatibilidade iOS/Android

### Passo 6 — Definir estratégia de eventos

Antes de crescer o app, decidir:

- SSE puro?
- SSE + reconnect?
- polling de recuperação ao voltar do background?

Essa decisão é crítica para estabilidade do produto.

## 13. Ordem recomendada de implementação

1. scaffold Expo
2. settings + secure storage
3. teste de conectividade com server
4. client API unificado
5. sessões
6. chat funcional
7. spike de voz
8. estados de UX
9. reconexão / recuperação
10. notificações

## 14. Critérios de sucesso do alpha

O alpha estará pronto quando:

- o app conecta ao OpenCode Server via Tailscale
- autentica com sucesso
- lista e abre sessões
- envia e recebe mensagens com consistência
- permite interação por voz ponta a ponta
- permite fallback para chat sem fricção
- sobrevive a interrupções comuns de uso mobile
- funciona em iOS e Android

## 15. Próximo documento recomendado

Depois deste plano, o próximo artefato deve ser um documento de execução curta contendo:

1. stack exata de bibliotecas
2. contrato inicial do client API
3. arquitetura de estado local
4. decisão formal sobre streaming/reconexão
5. backlog da Fase 0 e Fase 1

> Status: esse próximo documento foi criado em `mobile-app/EXECUTION.md`.

> Spec complementar: `mobile-app/OPENCODE_PLUGIN_SPEC.md` fecha o plugin de notificações e a spec inicial de mensagens/permissões.

> Plano técnico detalhado: `mobile-app/TECHNICAL_PLAN.md` organiza milestones, workstreams, estrutura de monorepo e ordem completa de desenvolvimento.
