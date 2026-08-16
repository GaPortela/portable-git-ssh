# Git SSH Portátil

Use uma chave SSH armazenada em um pendrive para trabalhar com Git e GitHub em **Windows, Linux e WSL**, sem copiar permanentemente a credencial para a máquina utilizada.

```text
Pendrive conectado
        ↓
chave SSH disponível
        ↓
Git autentica usando a chave externa

Pendrive removido
        ↓
o repositório continua apontando para a chave externa
        ↓
a chave deixa de estar disponível
        ↓
a autenticação com essa identidade deixa de funcionar
```

> [!IMPORTANT]
> Este projeto automatiza um fluxo de conveniência com Git e OpenSSH. Ele reduz a permanência da chave na máquina utilizada, mas não transforma um computador comprometido em um ambiente seguro.

<!-- TODO: adicionar aqui uma imagem de apresentação do projeto e do pendrive. -->

## Sumário

- [Por que criei este projeto](#por-que-criei-este-projeto)
- [Como funciona](#como-funciona)
- [Requisitos e compatibilidade](#requisitos-e-compatibilidade)
- [Recursos](#recursos)
- [Estrutura esperada](#estrutura-esperada)
- [Preparação inicial](#preparação-inicial)
- [Uso no Windows](#uso-no-windows)
- [Uso no Linux](#uso-no-linux)
- [Uso no WSL](#uso-no-wsl)
- [Configuração aplicada aos repositórios](#configuração-aplicada-aos-repositórios)
- [Segurança e limitações](#segurança-e-limitações)
- [Solução de problemas](#solução-de-problemas)

## Por que criei este projeto

Este projeto surgiu de um problema pessoal.

Durante muito tempo eu não tive um notebook. Na faculdade, isso significava depender frequentemente de computadores públicos ou compartilhados dos laboratórios para desenvolver projetos e realizar atividades.

Eu queria usar o GitHub normalmente nessas máquinas, mas sem copiar permanentemente minha chave SSH privada para cada computador e sem precisar configurar manualmente minha identidade Git toda vez.

A solução que encontrei foi carregar a chave SSH em um pendrive.

Os scripts deste projeto automatizam o fluxo ao redor dessa ideia: localizam a chave externa, leem minha identidade a partir de um arquivo `.env`, clonam ou configuram o repositório e fazem o Git apontar diretamente para a chave armazenada no dispositivo removível.

Assim, o código e o repositório podem permanecer no computador, mas minha credencial vai embora comigo no bolso.

## Como funciona

O projeto mantém no pendrive:

- a chave privada `id_ed25519`;
- a chave pública `id_ed25519.pub`;
- a identidade Git pessoal em `.env`;
- os scripts para Windows, Linux e WSL.

Ao clonar ou configurar um repositório, o módulo da plataforma grava configurações locais no `.git/config`:

```ini
[user]
    name = Seu Nome
    email = voce@exemplo.com

[core]
    sshCommand = ssh -i '/caminho-do-pendrive/id_ed25519' -o IdentitiesOnly=yes
```

Esses valores são gravados no arquivo `.git/config` do repositório escolhido. Na prática:

- somente aquele repositório passa a usar o nome, o e-mail e a chave configurados pelo script;
- outros repositórios da máquina permanecem com suas próprias configurações;
- o arquivo global do usuário, normalmente `~/.gitconfig`, não é alterado.

Se você executar o script em outro projeto, ele receberá sua própria configuração local, independente da anterior.

> [!NOTE]
> O caminho da chave é absoluto. Se a letra da unidade ou o ponto de montagem mudar, execute novamente o script para atualizar o repositório.

## Requisitos e compatibilidade

| Plataforma | Requisitos principais | Destino padrão do clone | Situação atual |
|---|---|---|---|
| Windows | Git for Windows e OpenSSH; Winget é opcional para instalação | Área de Trabalho | Implementado; validação prática completa ainda pendente |
| Linux | Bash, Git, OpenSSH, `findmnt`, utilitários de montagem e `sudo` quando necessário | `$HOME` | Fluxo validado em Kubuntu com pendrive VFAT |
| WSL | WSL, distribuição registrada exatamente como `Ubuntu`, Bash, PowerShell e DrvFS | `$HOME` do Ubuntu | Implementado; validação prática completa ainda pendente |

O Windows Terminal é opcional e utilizado apenas como conveniência quando disponível.

No Linux, o código possui tentativas de instalação para diferentes gerenciadores, mas isso não significa que todos os ambientes estejam homologados:

- `apt`: caminho utilizado no ambiente Kubuntu em que o módulo Linux foi desenvolvido e testado;
- `dnf`: implementação presente, mas ainda não testada em Fedora ou derivados;
- `zypper`: implementação presente, mas ainda não testada em openSUSE ou derivados;
- `pacman`: implementação presente no código, porém distribuições Arch e derivadas ainda não são consideradas compatíveis ou suportadas.

## Recursos

### Comuns aos módulos

- leitura dos campos esperados do `.env`, sem executá-lo como código;
- clone exclusivamente por URL SSH, com bloqueio de HTTP e HTTPS;
- configuração de repositórios já existentes;
- aplicação local de `user.name`, `user.email` e `core.sshCommand`;
- escolha do diretório de destino e uso de um local padrão quando ele não é informado;
- verificação da disponibilidade de Git e OpenSSH.

### Windows

- execução por um único arquivo `.bat`;
- Área de Trabalho como destino padrão dos clones;
- validação do Winget antes de qualquer tentativa de instalação;
- instalação do Git for Windows quando necessária e possível;
- abertura de um PowerShell no projeto após um clone bem-sucedido.

### Linux

- launcher gráfico independente de um emulador de terminal específico;
- tratamento de permissões da chave em VFAT e exFAT;
- montagem segura com UID, GID, `fmask` e `dmask` do usuário atual;
- validação da origem, do proprietário e das permissões após a montagem;
- rollback automático quando a remontagem não é concluída corretamente;
- uso controlado de `sudo` para montagem ou preparação de diretórios protegidos.

### WSL

- execução restrita à distribuição registrada como `Ubuntu`;
- montagem DrvFS com metadados, UID e GID detectados dinamicamente;
- validação das permissões da chave antes do uso;
- `$HOME` do Ubuntu como destino padrão dos clones;
- auxiliares próprios para montar e desmontar o pendrive.

## Estrutura esperada

O `.env` e as chaves SSH devem ficar no diretório pai das pastas `win`, `linux` e `wsl`:

```text
portable-git-ssh/
├── .env
├── .env.example
├── id_ed25519
├── id_ed25519.pub
├── SOLUCAO-DE-PROBLEMAS.md
├── win/
│   └── git_portatil_Win.bat
├── linux/
│   ├── git_portatil_Linux.desktop
│   ├── git_portatil_Linux.sh
│   └── README-Linux.md
└── wsl/
    ├── git_portatil_WSL.sh
    ├── montar_wsl.bat
    ├── montar_wsl.ps1
    ├── desmontar_wsl.bat
    └── desmontar_wsl.ps1
```

O projeto pode estar em qualquer profundidade e dentro de pastas com qualquer nome. Os caminhos abaixo são apenas exemplos; não é obrigatório usar os nomes `projetos` ou `portable-git-ssh`:

```text
/PENDRIVE/.env
/PENDRIVE/id_ed25519
/PENDRIVE/linux/
```

```text
/PENDRIVE/pasta-aleatoria/portable-git-ssh/id_ed25519
/PENDRIVE/pasta-aleatoria/portable-git-ssh/linux/
/PENDRIVE/pasta-aleatoria/portable-git-ssh/.env
```

Também seria válido, por exemplo:

```text
/PENDRIVE/qualquer-pasta/outra-pasta/.env
/PENDRIVE/qualquer-pasta/outra-pasta/id_ed25519
/PENDRIVE/qualquer-pasta/outra-pasta/linux/
```

A única regra de localização é: `.env` e `id_ed25519` devem estar ao lado das pastas dos módulos, no diretório imediatamente acima de `win`, `linux` e `wsl`.

## Preparação inicial

### 1. Configure sua identidade Git

Copie `.env.example` para `.env`.

No Linux ou WSL:

```bash
cp .env.example .env
```

No PowerShell:

```powershell
Copy-Item .env.example .env
```

Depois, preencha seus dados:

```dotenv
GIT_USER_NAME=Seu Nome
GIT_USER_EMAIL=voce@exemplo.com
```

O `.env` real é ignorado pelo Git. Os scripts leem somente `GIT_USER_NAME` e `GIT_USER_EMAIL`; o arquivo não é carregado como um script de shell.

### 2. Crie uma chave SSH

Se você ainda não possui uma chave dedicada para este fluxo, crie um par Ed25519:

```bash
ssh-keygen -t ed25519 -C "voce@exemplo.com"
```

No campo de destino, escolha o diretório do projeto no pendrive e use o nome:

```text
id_ed25519
```

O comando produzirá:

```text
id_ed25519      # chave privada: nunca compartilhe
id_ed25519.pub  # chave pública: pode ser cadastrada no GitHub
```

É recomendável proteger a chave privada com uma passphrase, principalmente por ela estar em um dispositivo que pode ser perdido.

> [!NOTE]
> O uso interativo com passphrase deve ser atendido pelo próprio OpenSSH, que solicitará a senha no terminal. Como esse cenário ainda não foi testado nos três módulos, consulte as observações no [Guia de solução de problemas](SOLUCAO-DE-PROBLEMAS.md#a-chave-possui-passphrase).

### 3. Cadastre a chave pública no GitHub

Exiba o conteúdo de `id_ed25519.pub`.

No Linux ou WSL:

```bash
cat /caminho-do-pendrive/id_ed25519.pub
```

No PowerShell:

```powershell
Get-Content X:\id_ed25519.pub
```

Substitua `X:` pela letra atual do pendrive. No GitHub, abra:

1. **Settings**;
2. **SSH and GPG keys**;
3. **New SSH key**;
4. escolha um nome para identificar o dispositivo;
5. cole o conteúdo completo de `id_ed25519.pub`;
6. salve a chave.

> [!WARNING]
> Nunca envie o conteúdo de `id_ed25519` ao GitHub, a um commit, issue, chat ou qualquer outro local público. Somente o arquivo terminado em `.pub` deve ser compartilhado.

<!-- TODO: adicionar print da tela SSH and GPG keys do GitHub. -->

### 4. Use sempre uma URL SSH

Formato esperado:

```text
git@github.com:usuario/repositorio.git
```

Você pode copiar essa URL pelo botão **Code**, selecionando a opção **SSH** no GitHub.

```text
Aceito:    git@github.com:usuario/repositorio.git
Rejeitado: https://github.com/usuario/repositorio.git
Rejeitado: http://github.com/usuario/repositorio.git
```

<!-- TODO: adicionar print do botão Code com a aba SSH selecionada. -->

## Uso no Windows

Execute:

```text
win\git_portatil_Win.bat
```

O módulo Windows:

- valida `.env` e `id_ed25519`;
- verifica Git e OpenSSH;
- usa o Winget para instalar o Git for Windows quando necessário e disponível;
- permite clonar um repositório ou configurar um projeto existente;
- usa a Área de Trabalho como destino padrão quando nenhum diretório é informado;
- rejeita URLs que não sejam SSH;
- abre um PowerShell no projeto após um clone bem-sucedido.

O menu apresenta:

```text
1. Clonar um novo repositorio
2. Configurar um projeto ja clonado
3. Sair
```

<!-- TODO: adicionar print do menu do módulo Windows. -->

## Uso no Linux

> [!WARNING]
> Distribuições Arch Linux e derivadas que utilizam `pacman` ainda não são consideradas compatíveis com este projeto. Existe uma tentativa de instalação no código, mas esse fluxo não foi testado nem homologado e será tratado como suporte futuro.

Abra um terminal cujo diretório atual esteja fora do pendrive e execute:

```bash
bash "/caminho/do/pendrive/linux/git_portatil_Linux.sh"
```

Como alternativa prática, digite `bash `, arraste `git_portatil_Linux.sh` para o terminal e pressione Enter. Na maioria dos ambientes gráficos, isso preenche automaticamente o caminho completo do arquivo.

> [!IMPORTANT]
> Abra o terminal fora do pendrive. O script se relança por uma cópia temporária em `/tmp` antes da desmontagem necessária em VFAT ou exFAT; a chave privada não é copiada.

O arquivo `linux/git_portatil_Linux.desktop` permanece disponível como atalho opcional. Algumas montagens VFAT utilizam `showexec`, que impede o ambiente gráfico de autorizar arquivos `.desktop`. Se isso acontecer, utilize o comando com `bash`, que não depende do bit de execução nem das políticas do KDE, GNOME ou XFCE.

### Permissões em VFAT e exFAT

VFAT e exFAT não armazenam permissões Unix individuais como ext4. Quando a chave aparece com acesso para grupo ou outros usuários, o módulo Linux:

1. detecta dinamicamente dispositivo, filesystem e mountpoint;
2. executa uma cópia temporária do script fora do pendrive;
3. desmonta o dispositivo;
4. monta novamente com o usuário atual e máscaras restritivas, sem preservar `showexec`;
5. valida origem, proprietário e permissões da chave;
6. restaura a montagem original automaticamente se a operação falhar.

As opções de segurança utilizadas são equivalentes a:

```text
uid=<usuario-atual>,gid=<grupo-atual>,fmask=0077,dmask=0077
```

A chave permanece no pendrive durante todo o processo. Somente o script, que não contém a credencial, é copiado temporariamente para `/tmp`.

### Destino dos clones

Se nenhum destino for informado, o Linux utiliza:

```text
$HOME
```

Também é possível escolher um diretório protegido. Nesse caso, `sudo` é usado apenas para criar o diretório final e transferir sua propriedade ao usuário atual; o `git clone` não é executado como root.

<!-- TODO: adicionar prints do launcher, da validação da chave e do menu Linux. -->

Mais detalhes estão em [`linux/README-Linux.md`](linux/README-Linux.md).

## Uso no WSL

O módulo WSL foi projetado para uma distribuição instalada com o nome exato:

```text
Ubuntu
```

Se apenas outra distribuição estiver instalada, os scripts não continuarão.

### 1. Monte o pendrive no Ubuntu

No Windows, execute:

```text
wsl\montar_wsl.bat
```

O auxiliar:

- detecta automaticamente a letra atual do pendrive;
- confirma que a distribuição `Ubuntu` está instalada;
- descobre UID e GID do usuário padrão;
- monta a unidade em `/mnt/<letra>` usando DrvFS;
- habilita metadados e aplica `umask=0077`.

Conceitualmente, a montagem corresponde a:

```bash
sudo mount -t drvfs D: /mnt/d \
  -o metadata,uid=<uid>,gid=<gid>,umask=0077
```

### 2. Execute o módulo dentro do Ubuntu

Use o caminho informado pelo auxiliar. Por exemplo:

```bash
cd /mnt/d/wsl
chmod +x git_portatil_WSL.sh
./git_portatil_WSL.sh
```

O módulo confirma a montagem com metadados, executa `chmod 600` e valida o modo, o proprietário e a leitura da chave antes de disponibilizar o menu.

O destino padrão dos clones é o `$HOME` da distribuição Ubuntu, não a Área de Trabalho do Windows.

### 3. Desmonte ao terminar

Depois de encerrar o módulo, execute no Windows:

```text
wsl\desmontar_wsl.bat
```

O auxiliar desmonta `/mnt/<letra>` dentro da distribuição `Ubuntu`.

<!-- TODO: adicionar prints da montagem, do menu WSL e da desmontagem concluída. -->

## Configuração aplicada aos repositórios

Depois de um clone ou da configuração de um projeto existente, o repositório recebe:

- `user.name` com o valor de `GIT_USER_NAME`;
- `user.email` com o valor de `GIT_USER_EMAIL`;
- `core.sshCommand` apontando para `id_ed25519` no pendrive.

Com o dispositivo conectado:

```text
repositório
    ↓
core.sshCommand
    ↓
id_ed25519 disponível no pendrive
    ↓
autenticação SSH funciona
```

Depois da remoção:

```text
repositório
    ↓
core.sshCommand
    ↓
caminho da chave indisponível
    ↓
autenticação com essa identidade não funciona
```

Esse comportamento é intencional e representa a ideia central do projeto.

## Segurança e limitações

- Nunca faça commit de `id_ed25519`.
- `.env`, `id_ed25519`, `id_ed25519.pub`, `*.pem` e `*.key` são ignorados pelo Git.
- Use uma chave dedicada a este fluxo quando possível.
- Uma chave com passphrase deve funcionar em uso interativo: o OpenSSH solicitará a senha no terminal quando precisar acessar a chave. Esse cenário ainda não foi testado neste projeto. Como os scripts não carregam a chave automaticamente em um agente SSH, a passphrase pode ser solicitada novamente em cada operação Git.
- Remova ou desmonte o pendrive quando terminar.
- Revogue a chave no GitHub se o dispositivo for perdido ou roubado.
- Não execute o clone como root somente porque o destino exige permissão elevada.
- O projeto não copia deliberadamente a chave privada para o disco local.
- Nome e e-mail Git não são credenciais de autenticação.

Um computador comprometido ainda pode observar dados enquanto a chave estiver conectada e em uso, assim como poderia capturar senhas, tokens ou outras credenciais utilizadas naquela máquina. O projeto reduz a permanência da chave após a remoção do pendrive; ele não protege contra malware com acesso ao ambiente de execução.

## Solução de problemas

Erros conhecidos, diagnóstico de unidade ocupada com `fuser` e orientações por plataforma foram reunidos em um documento próprio:

**[Consulte o Guia de solução de problemas](SOLUCAO-DE-PROBLEMAS.md).**

## Arquivos ignorados

O `.gitignore` protege dados pessoais e metadados comuns do dispositivo removível:

```gitignore
# Chaves SSH
id_ed25519
id_ed25519.pub
*.pem
*.key

# Configuração pessoal
.env

# Metadados de unidade removível do Windows
System Volume Information/
```

## Aviso

Este projeto foi criado principalmente para um fluxo pessoal em computadores compartilhados de faculdade e laboratório. Revise os scripts antes de utilizá-los em outro contexto e adapte caminhos, permissões e requisitos de segurança conforme sua necessidade.

## Autor

Criado por **Guilherme A. Portela (GaPortela)** como uma solução prática para um problema real de desenvolvimento.
