# Entrada Linux

Esta pasta possui dois arquivos principais:

- `git_portatil_Linux.sh`: script principal utilizado internamente pelo launcher.
- `git_portatil_Linux.desktop`: ponto de entrada recomendado para o usuário.

## Como executar

Use somente:

```text
git_portatil_Linux.desktop
```

Abra o arquivo pelo gerenciador de arquivos e escolha a opção para executá-lo.

O launcher foi preparado para iniciar o terminal com o diretório de trabalho fora do pendrive, evitando que o próprio terminal mantenha o dispositivo ocupado durante a remontagem necessária para VFAT/exFAT.

O fluxo faz automaticamente:

```text
.desktop
→ inicia o terminal fora do pendrive
→ chama o script principal
→ detecta o filesystem
→ ajusta a montagem quando necessário
→ valida as permissões da chave SSH
→ abre o menu do Git Portátil
```

## Primeira execução

Dependendo da distribuição Linux e do gerenciador de arquivos, pode ser necessário marcar `git_portatil_Linux.desktop` como confiável ou permitir sua execução antes do primeiro uso.

Depois disso, utilize sempre o `.desktop` como ponto de entrada.
