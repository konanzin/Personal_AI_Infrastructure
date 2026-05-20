# ⚠️ INCIDENTE REPORT — rm -rf ${HOME}

## Data
2026-05-20

## O Que Aconteceu
O comando `rm -rf "${HOME}"` foi executado acidentalmente, deletando todo o diretório /home/konanzin.

## Por Que O Hook de Segurança Falhou

### Causa Raiz
O hook de segurança (SecurityPipeline) estava **corretamente implementado** com a regex:
```javascript
{ pattern: /rm\s+-rf/, reason: 'Recursive delete requires confirmation' }
```

### Por Que Não Funcionou
1. **O plugin estava instalado em `~/.config/opencode/plugins/`**
2. **O comando `rm -rf` apagou o próprio plugin primeiro**
3. **Sem o plugin, não havia mais proteção**
4. **O comando continuou e apagou o resto**

### Diagrama
```
rm -rf /home/konanzin
    ├── ~/.config/opencode/plugins/pai-hooks.js  [APAGADO - proteção morre]
    ├── ~/.config/opencode/PAI/                  [APAGADO]
    ├── ~/Documents/                              [APAGADO]
    ├── ~/Projects/                               [APAGADO]
    └── ...
```

## Lição Aprendida
**Um plugin de segurança não pode se proteger se ele está dentro do diretório que está sendo protegido.**

## Solução Futura
O plugin de segurança deve ser instalado em um local que NÃO seja dentro do home do usuário, ou o OpenCode deve ter proteção nativa contra rm -rf.

## Backup
O código do port foi salvo em:
- `~/PAI-PORT-BACKUP/` (repo git completo)
- `/tmp/pai-opencode-backup-*.tar.gz`

## Status do Port
✅ Código preservado
❌ Instalação ativa perdida
⚠️ Precisa reinstalar após recuperação
