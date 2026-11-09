# Inventário e decisões de migração V5.1

## Referência analisada

`../verificar-projetos-git-v5-1.sh` foi lido integralmente. O Bash permanece intacto. O programa Python é independente do Bash em produção; somente o teste diferencial usa a referência.

## Inventário funcional e mapeamento

| Bloco da V5.1 | Responsabilidade Python | Regras preservadas |
| --- | --- | --- |
| usage e parsing | main.py, config/settings.py | Os seis parâmetros, padrão de pasta e 180 dias; inteiro não negativo; saída 2 para argumentos inválidos |
| find | core/scanner.py | .git arquivo/diretório; worktrees; recursão; exclui node_modules, .venv, venv, dist, build; não segue diretórios simbólicos |
| symbolic-ref e status | core/git_status.py | main/master; detached HEAD; status porcelain NUL; renomeações contam uma vez; arquivos não rastreados normais |
| verificação HEAD | core/git_status.py | SEM COMMITS tem prioridade sobre falha de status |
| upstream, remote, fetch, rev-list | core/git_sync.py | Usa upstream da branch, ignora fetch para remoto ponto, prioridades de erro e quatro estados de comparação |
| alterações locais | core/git_status.py | Só substitui SINCRONIZADO; acrescenta contagem aos detalhes |
| log -1 | core/git_commits.py | Autor, assunto, timestamp do committer e data local |
| HEAD..upstream | core/git_commits.py | Pendências só em RECEBER/DIVERGENTE, em ordem reversa do log, com hash completo, autor, data do autor ISO e assunto |
| github_slug, visibilidade_git | services/github.py | origin; formatos HTTP(S), SCP e SSH; gh, API, tokens opcionais; quatro visibilidades |
| Python embutido: classificação | services/health.py | Ordenação, dias completos, limite inclusivo, saúde estrita calculada antes do filtro |
| CSV e JSON | reports/csv_report.py, json_report.py | Mesmos nomes, ordem de colunas, BOM, campos, tipos e indentação JSON |
| histórico | reports/history.py | Acumula lista; aceita objeto legado; preserva JSON inválido |
| HTML | reports/html_report.py e templates | Gráfico CSS offline, legenda completa, tabela filtrada, escape de conteúdo, expansão de pendências |
| console | reports/console.py | Resumo, contagens, tabela com largura limitada, top 5 recentes/antigos, caminhos dos arquivos |
| xdg-open | utils/browser.py | Abertura automática no navegador padrão e aviso quando indisponível, agora também Windows |

## Limitações identificadas e ajustes justificados

- A V5.1 não tem timeout no fetch nem nas demais consultas Git/gh; Python limita Git a 20s, fetch a 60s, gh a 10s e API a 8s. Timeout passa pelo estado de erro correspondente.
- O Bash impede parte dos prompts via credential.interactive, mas ainda permite prompts de terminal/SSH. Python define GIT_TERMINAL_PROMPT=0, GCM_INTERACTIVE=Never e SSH BatchMode/ConnectTimeout.
- A URL remota e erros do Git podem expor credenciais. Python oculta credenciais em URLs e os valores GH_TOKEN/GITHUB_TOKEN nas mensagens. Esta é uma diferença intencional no conteúdo sensível dos relatórios.
- A V5.1 usa parsers diferentes para visibilidade e links. Python compartilha a validação estrita do slug e exige hash hexadecimal para links de commits.
- A V5.1 abre o navegador somente com sessão gráfica Linux. Python usa webbrowser para suporte a Windows/Linux e mantém aviso se a abertura falhar.
- A contagem Bash enumera combinações de rename/copy; Python reconhece R/C em qualquer posição do código porcelain, cobrindo também combinações adicionais.
- Diretórios podem mudar durante a auditoria, APIs podem falhar e referências podem estar antigas em sem-fetch. Estados de erro e DESCONHECIDO são preservados.
- Escrita simultânea dos relatórios e histórico não tem bloqueio, como na referência. Sem upstream, a branch não sofre fetch. Branch principal continua sendo main/master, sem heurística nova.
- Os três relatórios mantêm o formato V5.1. A implementação original de formatação foi extraída em módulos para reduzir diferenças de contrato. HTML/CSS são arquivos separados na fonte e incorporados na saída offline.
- Mensagens nativas de erro do Git variam com plataforma/versão/idioma. Caminhos absolutos usam a forma nativa do sistema; o teste diferencial normaliza essa diferença ao comparar.

## Validação

A suíte cobre sincronização, envio, recebimento, divergência, alterações locais, renomeação, sem commits, sem upstream, fetch falho, worktree, exclusões, ordem, inatividade, saúde, filtro, relatórios, histórico válido/inválido, nomes especiais, timeout, credenciais, URLs, API e integração com navegador simulado. A comparação com Bash usa os mesmos repositórios descartáveis e verifica os campos dos relatórios com filtro habilitado/desabilitado.

A abertura real de uma janela do navegador depende da sessão gráfica do usuário; o teste valida a chamada ao navegador padrão sem abrir uma janela durante os testes. Não foram executados comandos de alteração nos repositórios reais.

Resultado nesta implementação: 14 testes aprovados em 132,346 segundos no Windows com Python 3.15.2 e Git portátil, incluindo a comparação real Bash/Python. A ajuda da CLI e a compilação de todos os módulos também foram verificadas. A abertura do navegador foi validada com simulação; nenhuma janela foi aberta nesta sessão.
