# Entrada Linux

Esta pasta possui dois arquivos principais:

- `git_portatil_Linux.sh`: script principal e ponto de entrada universal.
- `git_portatil_Linux.desktop`: atalho opcional para ambientes que autorizem sua execução.

## Como executar

Abra um terminal cujo diretório atual esteja fora do pendrive e execute:

```bash
bash "/caminho/do/pendrive/linux/git_portatil_Linux.sh"
```

Você também pode digitar `bash `, arrastar `git_portatil_Linux.sh` para o terminal e pressionar Enter. O caminho completo será preenchido automaticamente na maioria dos ambientes gráficos.

O script cria uma cópia temporária de si mesmo em `/tmp` antes de desmontar o dispositivo. A chave privada não é copiada e permanece no pendrive durante todo o processo.

O fluxo faz automaticamente:

```text
bash git_portatil_Linux.sh
→ relança o script temporariamente a partir de /tmp
→ detecta o filesystem
→ ajusta a montagem quando necessário
→ valida as permissões da chave SSH
→ abre o menu do Git Portátil
```

## Atalho `.desktop` opcional

O arquivo `git_portatil_Linux.desktop` pode ser usado quando o ambiente gráfico permitir sua execução. Entretanto, ele não é o método universal: montagens VFAT com a opção `showexec` apresentam arquivos `.desktop` sem o bit executável, e KDE ou outros desktops podem bloqueá-los antes de o script começar.

Se aparecer uma mensagem de arquivo não autorizado, não tente alterar repetidamente a confiança do launcher. Utilize o comando com `bash` descrito acima.
