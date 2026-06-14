# Pulse Voice A51 Test Guide

Guia para validar o Pulse/TTS no Samsung A51 (`RQ8N607VHEK`) com o pacote
atual do app (`dev.pai.mobile`).

## Regra Atual

- App em primeiro plano: eventos live podem falar.
- App em background: eventos live atualizam a notificacao, mas nao falam.
- Catch-up (`/recent` apos reconexao): nunca fala.
- Eventos sem `language` valido nao falam.

## Setup

No host:

```bash
cd /home/konanzin/Work/Personal_AI_Infrastructure
```

Confirme o broker:

```bash
curl -sS http://127.0.0.1:31337/health
```

Instale o app no A51:

```bash
cd mobile-app/apps/flutter
flutter build apk --debug
adb -s RQ8N607VHEK install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RQ8N607VHEK shell pm grant dev.pai.mobile android.permission.POST_NOTIFICATIONS || true
adb -s RQ8N607VHEK shell pm grant dev.pai.mobile android.permission.RECORD_AUDIO || true
```

Configure os reverses usados pelo app:

```bash
adb -s RQ8N607VHEK reverse tcp:31337 tcp:31337
adb -s RQ8N607VHEK reverse tcp:4096 tcp:4096
adb -s RQ8N607VHEK reverse --list
```

Abra o app:

```bash
adb -s RQ8N607VHEK shell monkey -p dev.pai.mobile -c android.intent.category.LAUNCHER 1
```

Confirme inscricao no broker:

```bash
curl -sS http://127.0.0.1:31337/health
```

Esperado:

```json
"subscribers":1
```

## Teste 1: Ingles Fala Em Foreground

Deixe o app aberto na tela.

```bash
adb -s RQ8N607VHEK logcat -c

curl -sS -X POST http://127.0.0.1:31337/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title":"PAI foreground voice",
    "message":"Foreground English voice should speak using English text to speech.",
    "language":"en-US",
    "level":"attention"
  }'

sleep 6

adb -s RQ8N607VHEK logcat -d \
  | rg -i 'Synthesis request|TTS dispatch|Utterance|\[pulse-tts\]'
```

Esperado:

```text
[pulse-tts] selected en-us-...
Synthesis request for locale eng-USA
TTS dispatch: en-us-...
Utterance ID has started
```

Tambem deve ser audivel no telefone.

## Teste 2: Portugues Fala Em Foreground

```bash
adb -s RQ8N607VHEK logcat -c

curl -sS -X POST http://127.0.0.1:31337/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title":"PAI voz portugues",
    "message":"Teste de voz em portugues com o aplicativo em primeiro plano.",
    "language":"pt-BR",
    "level":"attention"
  }'

sleep 6

adb -s RQ8N607VHEK logcat -d \
  | rg -i 'Synthesis request|TTS dispatch|Utterance|\[pulse-tts\]'
```

Esperado:

```text
[pulse-tts] selected pt-br-...
Synthesis request for locale por-BRA
TTS dispatch: pt-br-...
```

## Teste 3: Background Nao Fala

Mande o app para background:

```bash
adb -s RQ8N607VHEK shell input keyevent HOME
sleep 1

adb -s RQ8N607VHEK shell run-as dev.pai.mobile \
  sh -c 'grep -R "pulse.app.foregrounded" shared_prefs 2>/dev/null | head -10'
```

Esperado:

```text
value="false"
```

Dispare um evento:

```bash
adb -s RQ8N607VHEK logcat -c

curl -sS -X POST http://127.0.0.1:31337/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title":"PAI background voice",
    "message":"Background should update notification but should not speak.",
    "language":"en-US",
    "level":"attention"
  }'

sleep 6

adb -s RQ8N607VHEK logcat -d \
  | rg -i 'Synthesis request|TTS dispatch|Utterance|\[pulse-tts\]' || true
```

Esperado: nenhuma saida de TTS. A entrega ainda deve aparecer no broker:

```bash
journalctl --user -u pulse-broker -n 5 --no-pager
```

## Teste 4: Catch-up Nao Fala

Com eventos recentes no broker:

```bash
adb -s RQ8N607VHEK logcat -c
adb -s RQ8N607VHEK shell am force-stop dev.pai.mobile
adb -s RQ8N607VHEK shell monkey -p dev.pai.mobile -c android.intent.category.LAUNCHER 1
sleep 20

adb -s RQ8N607VHEK logcat -d \
  | rg -i 'While you were away|Enquanto|Synthesis request|Utterance' || true
```

Esperado: nenhuma fala e nenhum prefixo de catch-up.

## Diagnostico Rapido

Ver pacote instalado:

```bash
adb -s RQ8N607VHEK shell pm list packages | rg 'dev\.pai|pai_mobile'
```

Esperado: somente `package:dev.pai.mobile`.

Ver foreground service:

```bash
adb -s RQ8N607VHEK shell dumpsys activity services dev.pai.mobile \
  | rg -i 'ServiceRecord|ForegroundService|isForeground|foregroundId'
```

Ver estado de foreground salvo:

```bash
adb -s RQ8N607VHEK shell run-as dev.pai.mobile \
  sh -c 'grep -R "pulse.app.foregrounded" shared_prefs 2>/dev/null | head -10'
```

Ver broker:

```bash
curl -sS http://127.0.0.1:31337/health
journalctl --user -u pulse-broker -n 20 --no-pager
```

Se o broker esta saudavel mas `subscribers` fica `0`, refaca:

```bash
adb -s RQ8N607VHEK reverse tcp:31337 tcp:31337
adb -s RQ8N607VHEK shell am force-stop dev.pai.mobile
adb -s RQ8N607VHEK shell monkey -p dev.pai.mobile -c android.intent.category.LAUNCHER 1
```
