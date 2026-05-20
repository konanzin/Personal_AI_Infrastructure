#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Setup GitHub Repo — PAI OpenCode Port
# ═══════════════════════════════════════════════════════════

set -e

REPO_DIR="/tmp/pai-opencode-repo"

echo "═══════════════════════════════════════════════════"
echo "  Setup GitHub Repo — PAI for OpenCode"
echo "═══════════════════════════════════════════════════"
echo ""

# Verificar se já tem remote configurado
cd "$REPO_DIR"

if [ -d .git ]; then
    echo "✅ Repo já inicializado"
else
    echo "Inicializando repo..."
    git init
    git add .
    git commit -m "Initial commit: PAI v5.0.0 OpenCode port

- 48 skills
- 18 agents
- 8 native plugins
- 238 Fabric patterns
- Complete documentation"
    
    echo ""
    echo "📝 Próximos passos:"
    echo ""
    echo "1. Crie uma branch 'opencode' no seu fork:"
    echo "   git checkout -b opencode"
    echo ""
    echo "2. Adicione seu fork como remote:"
    echo "   git remote add origin https://github.com/SEU-USUARIO/PAI.git"
    echo ""
    echo "3. Push:"
    echo "   git push -u origin opencode"
    echo ""
    echo "4. Configure GitHub Actions:"
    echo "   - Vá em Settings → Actions → General"
    echo "   - Permita workflows"
    echo ""
fi

echo ""
echo "📊 Status do repo:"
echo "   Arquivos: $(find . -type f | wc -l)"
echo "   Tamanho: $(du -sh . | cut -f1)"
echo ""
echo "📁 Estrutura:"
find . -maxdepth 3 -type d | grep -v ".git" | sort | sed 's|^\./||;s|^|   |'
