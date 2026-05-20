# Instalação Detalhada — PAI for OpenCode

## Pré-requisitos

- **Git** — `git --version` (testado com 2.30+)
- **OpenCode** — [opencode.ai](https://opencode.ai) (v1.15.5+)
- **Bun** (opcional, recomendado) — [bun.sh](https://bun.sh)

## Instalação Rápida (1 comando)

```bash
curl -fsSL https://raw.githubusercontent.com/SEU-USUARIO/PAI/opencode/opencode/install.sh | bash
```

## Instalação Manual

### 1. Clone o Repositório

```bash
git clone -b opencode https://github.com/SEU-USUARIO/PAI.git ~/PAI-opencode
cd ~/PAI-opencode
```

### 2. Execute o Installer

```bash
./opencode/install.sh
```

O installer irá:
- ✅ Detectar pré-requisitos
- ✅ Criar estrutura de diretórios em `~/.config/opencode/`
- ✅ Copiar plugins, agentes, skills e configs
- ✅ Gerar `opencode.jsonc`
- ✅ Validar a instalação

### 3. Verifique a Instalação

```bash
~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Deve mostrar: **64/64 checks passing (100%)**

## Atualização

```bash
# Método 1: Via script
curl -fsSL https://raw.githubusercontent.com/SEU-USUARIO/PAI/opencode/opencode/install.sh | bash -s -- --update

# Método 2: Manual
cd ~/PAI-opencode
git pull origin opencode
./opencode/install.sh --update
```

## Desinstalação

```bash
# Remove PAI do OpenCode
rm -rf ~/.config/opencode/PAI
rm -rf ~/.config/opencode/agents
rm -rf ~/.config/opencode/plugins/pai*
rm ~/.config/opencode/opencode.jsonc

# Opcional: remover skills
rm -rf ~/.config/opencode/skills
```

## Estrutura Pós-Instalação

```
~/.config/opencode/
├── opencode.jsonc          # Config principal
├── plugins/
│   ├── pai-hooks.js        # 8 hooks nativos
│   └── pai-hooks.lib.js    # Biblioteca compartilhada
├── agents/                 # 18 agentes .md
├── commands/               # Comandos customizados
└── PAI/                    # Diretório PAI
    ├── ALGORITHM/          # Algoritmo PAI
    ├── MEMORY/             # Sistema de memória
    ├── PULSE/              # Dashboard
    ├── TOOLS/              # Scripts utilitários
    ├── USER/               # Dados do principal
    └── bin/                # Scripts (install, validate)
```

## Troubleshooting

### "opencode.jsonc inválido"

```bash
# Recriar config
rm ~/.config/opencode/opencode.jsonc
./opencode/install.sh
```

### "Plugins não carregam"

```bash
# Verificar sintaxe
node -c ~/.config/opencode/plugins/pai-hooks.js

# Verificar se plugin está registrado
grep -A 2 '"plugin"' ~/.config/opencode/opencode.jsonc
```

### "Agentes não aparecem"

```bash
# Verificar diretório
ls ~/.config/opencode/agents/*.md | wc -l
# Deve mostrar 18
```

## Suporte

- Abra uma [issue](https://github.com/SEU-USUARIO/PAI/issues) no GitHub
- Consulte [TROUBLESHOOTING.md](opencode/docs/TROUBLESHOOTING.md)
