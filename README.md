# PAI for OpenCode

> **PAI (Personal AI Infrastructure) v5.0.0** — Portado nativamente para [OpenCode](https://opencode.ai)

[![Validation](https://img.shields.io/badge/validation-64%2F64%20passing-brightgreen)]()
[![OpenCode](https://img.shields.io/badge/opencode-v1.15.5-blue)]()
[![Model](https://img.shields.io/badge/model-kimi--k2.6-purple)]()

## 🚀 Instalação em 1 Comando

```bash
curl -fsSL https://raw.githubusercontent.com/SEU-USUARIO/PAI/opencode/opencode/install.sh | bash
```

Ou manualmente:

```bash
# 1. Clone o repo
git clone -b opencode https://github.com/SEU-USUARIO/PAI.git ~/PAI-opencode
cd ~/PAI-opencode

# 2. Execute o installer
./opencode/install.sh
```

## 📋 O que está incluído

- **48 Skills** — Todas as skills do PAI (ISA, Telos, Fabric, Research, RedTeam, etc.)
- **18 Agentes** — Com prompts completos e personalidades
- **8 Plugins nativos** — SecurityPipeline, LoadContext, PromptGuard, etc.
- **238 Patterns Fabric** — Para extração e análise de conteúdo
- **Sistema TELOS** — Para metas e identidade
- **PULSE** — Dashboard e monitoramento
- **Memory System** — WORK, KNOWLEDGE, LEARNING, RESEARCH

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────┐
│           OpenCode (CLI)                │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │ opencode.   │  │ 8 Plugins       │  │
│  │ jsonc       │  │ (eventos        │  │
│  │             │  │  nativos)       │  │
│  └─────────────┘  └─────────────────┘  │
│         │                    │          │
│         ▼                    ▼          │
│  ┌─────────────────────────────────┐   │
│  │     ~/.config/opencode/         │   │
│  │  ├── PAI/                       │   │
│  │  ├── agents/ (18)               │   │
│  │  ├── plugins/ (8 hooks)         │   │
│  │  └── skills/ (48)               │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## 🎯 Comandos Disponíveis

Após instalação, no OpenCode:

```bash
/status       # Mostra status do PAI
/pai          # Executa o Algoritmo PAI
/interview    # Inicia entrevista TELOS
/pulse        # Verifica status do Pulse
/e1           # Effort: Standard
/e2           # Effort: Extended
/e3           # Effort: Advanced
/e4           # Effort: Deep
/e5           # Effort: Comprehensive
```

## 🔄 Manter Atualizado

```bash
# Atualizar para última versão
cd ~/PAI-opencode
git pull origin opencode
./opencode/install.sh --update
```

## 📖 Documentação

- [INSTALL.md](INSTALL.md) — Guia detalhado de instalação
- [SYNC.md](SYNC.md) — Como sincronizar com o PAI upstream
- [TROUBLESHOOTING.md](opencode/docs/TROUBLESHOOTING.md) — Problemas comuns

## 🤝 Contribuindo

Este é um port da comunidade. Para contribuir:

1. Fork o repo
2. Crie uma branch: `git checkout -b feature/nome`
3. Commit: `git commit -am 'Adiciona feature'`
4. Push: `git push origin feature/nome`
5. Abra um Pull Request para a branch `opencode`

## 📜 Licença

Mesma licença do PAI original — consulte o repositório upstream.

---

**Nota:** Este port é independente do Claude Code. Não requer `~/.claude/` ou symlink.
