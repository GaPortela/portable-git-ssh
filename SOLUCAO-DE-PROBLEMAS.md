# Solução de problemas

Este guia reúne erros conhecidos e verificações úteis para os módulos Windows, Linux e WSL do Git SSH Portátil.

[Voltar ao README principal](README.md)

## Sumário

- [Problemas gerais](#problemas-gerais)
  - [O clone rejeitou a URL](#o-clone-rejeitou-a-url)
  - [A chave possui passphrase](#a-chave-possui-passphrase)
  - [O repositório parou de autenticar após reconectar o pendrive](#o-repositório-parou-de-autenticar-após-reconectar-o-pendrive)
- [Windows](#windows)
  - [Git ou OpenSSH não está disponível no Windows](#git-ou-openssh-não-está-disponível-no-windows)
- [Linux](#linux)
  - [A chave privada está com permissões muito abertas no Linux](#a-chave-privada-está-com-permissões-muito-abertas-no-linux)
  - [O dispositivo está ocupado no Linux](#o-dispositivo-está-ocupado-no-linux)
  - [Git ou OpenSSH não está disponível no Linux](#git-ou-openssh-não-está-disponível-no-linux)
- [WSL](#wsl)
  - [A chave privada está com permissões muito abertas no WSL](#a-chave-privada-está-com-permissões-muito-abertas-no-wsl)
  - [O mountpoint está ocupado no WSL](#o-mountpoint-está-ocupado-no-wsl)
  - [Ubuntu não está instalado no WSL](#ubuntu-não-está-instalado-no-wsl)
  - [Git ou OpenSSH não está disponível no WSL](#git-ou-openssh-não-está-disponível-no-wsl)

## Problemas gerais

### O clone rejeitou a URL

Confirme que você copiou a URL da opção **SSH** no botão **Code** do GitHub:

```text
git@github.com:usuario/repositorio.git
```

URLs iniciadas por `http://` ou `https://` são rejeitadas intencionalmente, pois não utilizariam a chave SSH armazenada no pendrive.

### A chave possui passphrase

O fluxo foi construído sobre o OpenSSH e deve aceitar uma chave protegida por passphrase durante uso interativo. Quando necessário, o próprio OpenSSH deverá solicitar a senha no terminal.

Esse cenário ainda não foi validado nos três módulos. Os scripts não carregam a chave automaticamente em um agente SSH e o WSL desabilita explicitamente outro agente no comando configurado. Por isso, a passphrase pode ser solicitada novamente em cada clone, `fetch`, `pull` ou `push`.

Para testar diretamente:

```bash
ssh -i /caminho/do/pendrive/id_ed25519 \
  -o IdentitiesOnly=yes \
  -T git@github.com
```

No Windows PowerShell:

```powershell
ssh -i X:\id_ed25519 -o IdentitiesOnly=yes -T git@github.com
```

Se o teste pedir a passphrase e depois identificar corretamente sua conta, a chave está funcional naquele ambiente.

### O repositório parou de autenticar após reconectar o pendrive

O repositório armazena um caminho absoluto em `core.sshCommand`. A letra da unidade no Windows ou o mountpoint no Linux e WSL pode mudar depois de uma reconexão.

Execute novamente a opção de configurar um repositório existente. O script atualizará o caminho local da chave sem alterar o histórico ou os arquivos do projeto.

## Windows

### Git ou OpenSSH não está disponível no Windows

O módulo verifica Git e OpenSSH. Quando necessário, tenta instalar o Git for Windows somente se o Winget estiver disponível.

## Linux

### A chave privada está com permissões muito abertas no Linux

O OpenSSH rejeita uma chave privada quando grupo ou outros usuários possuem acesso ao arquivo.

Abra um terminal fora do pendrive e execute:

```bash
bash "/caminho/do/pendrive/linux/git_portatil_Linux.sh"
```

O script se relança a partir de `/tmp`, ajusta a montagem VFAT ou exFAT e valida novamente a chave sem copiar a credencial.

Se `git_portatil_Linux.desktop` apresentar uma mensagem de arquivo não autorizado, a montagem pode estar usando `showexec`. Essa opção impede que arquivos `.desktop` e `.sh` apareçam como executáveis em VFAT. Utilize o comando com `bash`; o `.desktop` é apenas um atalho opcional.

### O dispositivo está ocupado no Linux

Uma desmontagem pode falhar quando algum processo mantém aberto um arquivo, diretório ou o próprio diretório de trabalho dentro do pendrive.

#### 1. Descubra o mountpoint

Use o caminho real da chave:

```bash
findmnt -no TARGET -T /caminho/do/pendrive/id_ed25519
```

Exemplo de resultado:

```text
/run/media/usuario/PENDRIVE
```

#### 2. Liste os processos que estão usando o filesystem

Substitua o caminho pelo mountpoint encontrado:

```bash
sudo fuser -vm /run/media/usuario/PENDRIVE
```

As opções utilizadas são apenas de diagnóstico:

- `-v`: mostra uma tabela detalhada;
- `-m`: procura processos que estejam usando qualquer arquivo daquele filesystem.

A coluna `ACCESS` ajuda a entender o motivo do bloqueio:

- `c`: o diretório de trabalho atual do processo está no pendrive;
- `e`: um executável desse filesystem está em execução;
- `f`: existe um arquivo aberto;
- `F`: existe um arquivo aberto para escrita;
- `r`: o processo utiliza o filesystem como diretório raiz;
- `m`: existe um arquivo mapeado em memória.

#### 3. Identifique o processo antes de agir

Para consultar um PID exibido pelo `fuser`:

```bash
ps -fp PID
```

Para verificar o diretório de trabalho dele:

```bash
readlink -f /proc/PID/cwd
```

As providências mais comuns são:

1. fechar o gerenciador de arquivos que está aberto no pendrive;
2. encerrar editores ou terminais que estejam usando arquivos do dispositivo;
3. executar `cd ~` nos terminais cujo diretório atual esteja dentro do pendrive;
4. fechar normalmente o aplicativo identificado;
5. somente se necessário e depois de confirmar o PID, solicitar seu encerramento com `kill PID`.

> [!WARNING]
> Não use `fuser -km` no mountpoint. A opção `-k` encerra processos e pode atingir mais programas do que o esperado. Os scripts deste projeto utilizam `fuser` somente para diagnóstico e nunca encerram processos automaticamente.

Depois de liberar o dispositivo, abra um terminal fora do pendrive e execute novamente:

```bash
bash "/caminho/do/pendrive/linux/git_portatil_Linux.sh"
```

### Git ou OpenSSH não está disponível no Linux

O caminho validado atualmente é Kubuntu com `apt`. Existem ramificações no código para `dnf` e `zypper`, mas elas ainda não foram testadas em Fedora ou openSUSE.

Distribuições Arch e derivadas que usam `pacman` ainda não são consideradas compatíveis ou suportadas, mesmo que exista uma tentativa de instalação no código.

## WSL

### A chave privada está com permissões muito abertas no WSL

No Windows, execute primeiro:

```text
wsl\montar_wsl.bat
```

Depois, rode `git_portatil_WSL.sh` dentro da distribuição registrada como `Ubuntu`. O módulo aplica `chmod 600` e confirma o modo e o proprietário da chave.

### O mountpoint está ocupado no WSL

Dentro do Ubuntu, identifique a letra utilizada pelo pendrive e execute, por exemplo:

```bash
sudo fuser -vm /mnt/d
```

Feche os processos indicados ou saia do diretório com `cd ~`. Depois, execute novamente no Windows:

```text
wsl\desmontar_wsl.bat
```

### Ubuntu não está instalado no WSL

Os auxiliares procuram uma distribuição registrada exatamente como:

```text
Ubuntu
```

Confira as distribuições instaladas no PowerShell ou Prompt de Comando:

```powershell
wsl.exe --list --quiet
```

Nomes como `Ubuntu-24.04` são diferentes de `Ubuntu` para o fluxo atual. Outra distribuição não será utilizada automaticamente.

### Git ou OpenSSH não está disponível no WSL

O módulo utiliza `apt` para instalar `git` e `openssh-client`.
