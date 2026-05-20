#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PUSH MANUAL PARA GITHUB — PAI OpenCode Port
#  Execute após configurar autenticação
# ═══════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════"
echo "  Push Manual para GitHub"
echo "═══════════════════════════════════════════════════"
echo ""
echo "O código está salvo em: ~/PAI-PORT-BACKUP/"
echo ""
echo "Para subir para o GitHub, você precisa:"
echo ""
echo "1. Criar um token de acesso pessoal:"
echo "   https://github.com/settings/tokens/new"
echo "   - Scopes necessários: repo"
echo ""
echo "2. Configurar git para usar o token:"
echo "   cd ~/PAI-PORT-BACKUP"
echo "   git remote set-url origin https://TOKEN@github.com/konanzin/Personal_AI_Infrastructure.git"
echo ""
echo "3. Fazer push:"
echo "   git push -u origin opencode --force"
echo ""
echo "═══════════════════════════════════════════════════"
echo ""
echo "Ou via SSH (se recriar as chaves):"
echo "   ssh-keygen -t ed25519 -C 'seu-email'"
echo "   cat ~/.ssh/id_ed25519.pub"
echo "   # Adicionar em https://github.com/settings/keys"
echo "   git remote set-url origin git@github.com:konanzin/Personal_AI_Infrastructure.git"
echo "   git push -u origin opencode --force"
