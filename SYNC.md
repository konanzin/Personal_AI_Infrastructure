# Sincronização com Upstream PAI

Este documento explica como manter seu port OpenCode sincronizado com o PAI original (danielmiessler/PAI).

## Estratégia de Branches

```
seu-fork/PAI
├── main          ← PAI original (sync com upstream)
├── opencode      ← Port OpenCode (baseado na main)
└── feature/*     ← Branches de desenvolvimento
```

## Workflow de Sincronização

### 1. Atualizar a `main` com upstream

```bash
# Adicionar remote upstream (uma vez)
git remote add upstream https://github.com/danielmiessler/PAI.git

# Fetch upstream
git fetch upstream

# Atualizar main
git checkout main
git merge upstream/main
```

### 2. Rebase a branch `opencode`

```bash
# Ir para branch opencode
git checkout opencode

# Rebase com as mudanças da main
git rebase main

# Resolver conflitos se houver
# ...
```

### 3. Testar o port

```bash
# Rodar validação
./opencode/install.sh --update
~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

### 4. Push

```bash
git push origin opencode --force-with-lease
```

## Conflitos Comuns

### Skills novas no upstream

Se o Daniel adicionar novas skills:

```bash
# As skills estarão na main
git checkout main
ls skills/

# Copiar para o port
git checkout opencode
cp -r skills/NOVA_SKILL ~/.config/opencode/skills/

# Verificar se a skill tem refs ~/.claude/
grep -r "\.claude/" skills/NOVA_SKILL/ -l

# Se tiver, aplicar patch
find skills/NOVA_SKILL -type f -exec sed -i 's|~/.claude/|~/.config/opencode/|g' {} +
```

### Mudanças no ALGORITHM

Se o Algorithm for atualizado:

```bash
# O ALGORITHM/ é compartilhado entre main e opencode
# Após rebase, verificar se os plugins ainda compatíveis
node -c opencode/plugins/pai-hooks.js
```

### Hooks novos no upstream

Se novos hooks forem adicionados ao PAI original:

```bash
# Decidir se vale a pena portar para OpenCode
# Se sim, adicionar ao pai-hooks.js com evento equivalente
```

## Automatização (Opcional)

Crie um script `sync-upstream.sh`:

```bash
#!/bin/bash
# sync-upstream.sh — Atualiza opencode com upstream

set -e

echo "🔄 Sincronizando com upstream..."

# Fetch
git fetch upstream

# Atualizar main
git checkout main
git merge upstream/main

# Rebase opencode
git checkout opencode
git rebase main || {
    echo "⚠️ Conflitos detectados. Resolva manualmente:"
    echo "   git status"
    echo "   # Resolver conflitos"
    echo "   git rebase --continue"
    exit 1
}

# Testar
./opencode/install.sh --update
if ~/.config/opencode/PAI/bin/validate-pai-installation.sh; then
    echo "✅ Validação passou"
else
    echo "❌ Validação falhou"
    exit 1
fi

# Push
git push origin opencode --force-with-lease

echo "✅ Sincronização completa!"
```

## Release Checklist

Antes de fazer release do port:

- [ ] `main` sincronizada com upstream
- [ ] `opencode` rebased na `main` atual
- [ ] Validação passando (64/64)
- [ ] README atualizado
- [ ] CHANGELOG-OPENCODE.md atualizado
- [ ] Testado em ambiente limpo

## Contribuições Upstream

Se você criar uma feature no port que poderia ser útil no PAI original:

```bash
# Criar branch baseada na main
git checkout main
git checkout -b feature/alguma-coisa

# Fazer as mudanças
# ...

# Abrir PR para o repo do Daniel
git push origin feature/alguma-coisa
# Abrir PR em https://github.com/danielmiessler/PAI
```
