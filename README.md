# Git Portfolio

O Git Portfolio reúne a situação dos seus repositórios Git em um único relatório.
- Localiza projetos dentro de uma pasta e suas subpastas.
- Verifica sincronização: sincronizado, enviar, receber, divergente ou com alterações locais.
- Atualiza referências remotas com fetch, sem executar pull ou push.
- Mostra commits pendentes para receber.
- Exibe informações: branch, visibilidade, autor, último commit e arquivos alterados.
- Identifica inatividade e ordena projetos pela atividade mais recente.
- Apresenta o problema que cada projeto resolve, extraído do README ou de portfolio.json.
- Permite copiar e abrir o link remoto.
- Gera HTML, CSV e JSON, com gráfico de situações, índice de saúde e histórico das execuções.
- Filtra somente projetos com pendências.
Funciona em Windows e Linux, usando Python e Git.


Migração modular do `verificar-projetos-git-v5-1.sh`, preservado na raiz do repositório como referência. Audita repositórios locais, consulta seus remotos e produz relatórios cronológicos em português. A aplicação usa apenas a biblioteca padrão.

## Requisitos e instalação

Python 3.10+ e Git no PATH. GitHub CLI (`gh`) é opcional. Não exige privilégios de administrador. A execução direta dispensa instalação e dependências Python externas.

Linux:

```bash
cd git-portfolio
python3 main.py --pasta ~/repos --sem-fetch --sem-abrir
python3 main.py --pasta ~/repos
```

Windows PowerShell:

```powershell
cd git-portfolio
python main.py --pasta "C:\Users\seu-usuario\repos" --sem-fetch --sem-abrir
python main.py --pasta "C:\Users\seu-usuario\repos"
```

Opcionalmente, instale com `python -m pip install .` e execute `git-portfolio`. O empacotamento usa setuptools e inclui os templates. Sem `--pasta`, mantém `$HOME/Documents/1Portifolio` (no Windows, a pasta inicial do usuário).

```bash
python main.py --ajuda
python main.py --pasta ~/repos --sem-fetch
python main.py --pasta ~/repos --somente-problemas
python main.py --pasta ~/repos --dias-inatividade 90
python main.py --pasta ~/repos --sem-abrir
```

O fetch é habilitado por padrão, usa o remoto configurado no upstream e não permite prompts de autenticação. Usa as credenciais já configuradas no Git. O programa não executa pull, push, reset ou checkout. O navegador padrão abre automaticamente ao final; `--sem-abrir` desabilita isso. Em ambientes sem navegador, mostra o caminho para abertura manual.

## Estrutura

```text
main.py                 CLI e coordenação
config/settings.py      diretório padrão, exclusões e colunas
core/scanner.py         descoberta recursiva, incluindo worktrees
core/git_status.py      estado e arquivos modificados
core/git_sync.py        fetch e comparação com upstream
core/git_commits.py     último commit e pendências remotas
models/repository.py    dataclasses Repository e Commit
services/github.py      URLs seguras e visibilidade
services/health.py      cronologia, inatividade e saúde
reports/                CSV, JSON, HTML, histórico e console
reports/templates/      HTML e CSS separados do Python
utils/                  subprocessos e navegador
tests/test_portfolio.py testes de integração, regras e compatibilidade
MIGRACAO.md             inventário, regras e diferenças da V5.1
```

Os testes ficam em um arquivo para compartilhar fixtures Git; os módulos da aplicação permanecem separados por responsabilidade. O CSS é incorporado ao HTML gerado, mantendo o relatório como arquivo único para uso offline.

## Estados

| Estado | Significado |
| --- | --- |
| SINCRONIZADO | Nenhum commit a enviar/receber nem arquivos alterados |
| ENVIAR | Somente commits locais pendentes |
| RECEBER | Somente commits remotos pendentes |
| DIVERGENTE | Commits pendentes nos dois sentidos |
| ALTERACOES LOCAIS | Histórico sincronizado, árvore de trabalho alterada |
| SEM COMMITS | Sem commit inicial |
| SEM UPSTREAM | Branch sem referência remota de acompanhamento |
| ERRO STATUS | Falha ao consultar a árvore de trabalho |
| ERRO FETCH | Falha de rede, autenticação ou timeout no fetch |
| ERRO COMPARACAO | Falha ao comparar HEAD e upstream |

Arquivos alterados são contados em todos os estados em que o status é válido. Alterações locais substituem somente SINCRONIZADO; em outros estados acrescentam informação a Detalhes. BranchPrincipal é SIM somente para main/master, conforme a V5.1. Detached HEAD aparece explicitamente.

A visibilidade é PUBLICO, PRIVADO, INTERNO ou DESCONHECIDO. A consulta usa origin, tenta `gh api`, depois a API HTTPS com GH_TOKEN/GITHUB_TOKEN ou credenciais obtidas por `gh auth token`. Falhas não interrompem a auditoria. Tokens não são impressos; credenciais embutidas na URL são ocultadas nos relatórios.

## Saúde e inatividade

Índice de saúde = `round(100 × saudáveis / total)`, com o arredondamento padrão do Python. Saudável exige SINCRONIZADO e zero arquivos alterados. Total vazio produz 0%. O filtro somente problemas não modifica esse denominador nem o gráfico.

A ordenação usa o timestamp real do último commit em ordem decrescente, com desempate pelo nome sem distinção de maiúsculas. Sem commits ficam no final. Datas do último commit usam hora local; pendências usam a data ISO do autor. Dias sem atividade são dias completos desde o timestamp do commit, com mínimo zero. Inativo é SIM quando dias >= limite; sem commits recebe dias nulos e Inativo NAO.

`--dias-inatividade` classifica os projetos; não exclui projetos da saída. `--somente-problemas` exclui apenas SINCRONIZADO dos projetos exibidos/exportados. O console mostra os cinco mais recentes e os cinco mais antigos entre os exibidos com commits.

## Relatórios

Os quatro arquivos são gravados na pasta auditada:

- `relatorio-git.csv`: UTF-8 com BOM, delimitador vírgula, cabeçalho V5.1; CommitsPendentes contém JSON.
- `relatorio-git.json`: DataExecucao, TotalProjetos, ProjetosExibidos, IndiceSaude, FiltroSomenteProblemas, LimiteInatividadeDias e Projetos.
- `relatorio-git.html`: tabela, gráfico circular, legenda de todos os projetos e expansão de commits em RECEBER/DIVERGENTE. Não carrega recursos externos. Links de commits são criados apenas para URLs GitHub e hashes válidos.
- `historico-git.json`: lista acumulativa de DataExecucao, TotalProjetos e IndiceSaude. Um objeto legado é preservado como primeiro item; JSON inválido permanece intacto e gera aviso.

Campos de cada projeto, na ordem do CSV: Projeto, Visibilidade, Branch, BranchPrincipal, Situacao, Detalhes, ArquivosAlterados, Autor, DataUltimoCommit, DiasSemAtividade, Inativo, UltimoCommit, Remoto, Caminho, CommitsPendentes. Cada commit pendente contém hash, autor, data e mensagem. Campos internos de ordenação não são exportados.

Como na V5.1, os três relatórios são substituídos em cada execução; o histórico é acumulativo. Evite execuções simultâneas na mesma pasta, pois não há bloqueio de escrita. Fetch falho impede classificar a sincronização a partir de referências potencialmente antigas. Com `--sem-fetch`, a comparação usa as referências locais existentes.

## Descrição do problema

Cada projeto exporta o campo `Problema` no JSON e no CSV. No HTML, passe o mouse sobre o nome, clique nele ou use Tab para abrir o painel; Escape fecha. O painel acompanha a área visível da tela. HTML, CSS e JavaScript ficam no mesmo arquivo, funcionando offline.

A extração usa somente arquivos locais, sem IA ou APIs. Na raiz de cada repositório, um `portfolio.json` opcional tem prioridade:

```json
{"problema": "Evita a perda de documentos ao organizar cópias de segurança locais."}
```

O campo deve ser uma string descritiva, com ao menos 20 caracteres e quatro palavras. JSON inválido, campo vazio ou tipo incorreto fazem a extração continuar pelo README. O módulo `core/description.py` procura README na raiz sem distinguir maiúsculas e minúsculas (README, README.md e outras extensões). Prefere seções Problema, Objetivo, Sobre ou Descrição; na ausência de conteúdo útil nelas, usa o primeiro parágrafo descritivo relevante.

Títulos isolados, badges, imagens, blocos de código, comandos e instruções de instalação são ignorados. A extração remove marcação e limita o texto a 300 caracteres, preferindo terminar uma frase. Nenhuma finalidade é deduzida do nome do projeto. Sem conteúdo suficiente, ou com README ausente ou ilegível, usa `Descrição do problema não disponível`, sem interromper a auditoria. O conteúdo é escapado ao gerar HTML.

O campo `Problema` é acrescentado ao final do CSV. O teste de compatibilidade ignora esse campo novo ao comparar com o Bash V5.1.

## Execução dos testes

Na pasta `git-portfolio`:

```bash
python -m unittest discover -s tests -v
```

Com Python portátil que isola sys.path, use:

```bash
python -m unittest discover -s tests -t . -v
```

Os testes criam e removem apenas repositórios temporários, incluindo remoto bare, clones e worktrees. Comandos que escrevem commits ou fazem push são restritos às fixtures. Não acessam o GitHub real; a API é simulada nos testes.

Para a comparação com a V5.1, mantenha o script Bash na raiz e disponibilize Bash no PATH. No Windows com Git portátil:

```powershell
$env:GIT_PORTFOLIO_BASH = "C:\caminho\PortableGit\bin\bash.exe"
python -m unittest discover -s tests -t . -v
```

A comparação executa Bash e Python sobre os mesmos repositórios temporários, com e sem somente-problemas, e compara os campos JSON/CSV. Ignora apenas DataExecucao e a representação de Caminho absoluto, que difere entre Git Bash e Windows. Sem Bash, esse teste é marcado como ignorado. O teste cria um wrapper python3 temporário para usar o mesmo interpretador Python, sem alterar a configuração do usuário.
