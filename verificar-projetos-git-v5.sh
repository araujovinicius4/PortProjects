#!/usr/bin/env bash
# Portfolio Git V5: auditoria de repositorios e relatorios cronologicos.
set -u
export LC_ALL=C

usage() {
  cat <<'HELP'
Uso: ./verificar-projetos-git-v5.sh [opcoes]
  --pasta CAMINHO        Diretorio raiz (padrao: $HOME/Documents/1Portifolio)
  --sem-fetch            Nao atualiza referencias remotas
  --somente-problemas    Mostra/exporta apenas projetos nao sincronizados
  --dias-inatividade N   Limite de inatividade em dias (padrao: 180)
  --sem-abrir           Nao abre o relatorio HTML no navegador
  --ajuda                Exibe esta ajuda

Relatorios: relatorio-git.csv, relatorio-git.json, relatorio-git.html,
            historico-git.json (acumulativo).
HELP
}

pasta="$HOME/Documents/1Portifolio"
sem_fetch=0
somente_problemas=0
dias_inatividade=180
sem_abrir=0
while (($#)); do
  case "$1" in
    --pasta) if (($# < 2)); then echo 'Falta caminho apos --pasta' >&2; exit 2; fi; pasta="$2"; shift 2 ;;
    --sem-fetch) sem_fetch=1; shift ;;
    --somente-problemas) somente_problemas=1; shift ;;
    --sem-abrir) sem_abrir=1; shift ;;
    --dias-inatividade)
      if (($# < 2)) || ! [[ "$2" =~ ^[0-9]+$ ]]; then echo 'Informe um numero inteiro nao negativo para --dias-inatividade' >&2; exit 2; fi
      dias_inatividade="$2"; shift 2 ;;
    -h|--ajuda) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done
for cmd in git python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Dependencia ausente: $cmd" >&2; exit 1; }
done
[[ -d "$pasta" ]] || { echo "Pasta nao encontrada: $pasta" >&2; exit 1; }
pasta="$(cd -- "$pasta" && pwd -P)"
tmp="$(mktemp)" || exit 1
trap 'rm -f -- "$tmp"' EXIT

# Normaliza a URL de origin para owner/repo do GitHub.
github_slug() {
  local url="$1" slug=''
  if [[ "$url" =~ ^https?://([^/@]+@)?github\.com/([^?#]+)$ ]]; then
    slug="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@github\.com:(.+)$ ]]; then
    slug="${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^ssh://git@github\.com(:[0-9]+)?/(.+)$ ]]; then
    slug="${BASH_REMATCH[2]}"
  fi
  slug="${slug%/}"; slug="${slug%.git}"
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && printf '%s' "$slug"
  return 0
}

visibilidade_git() {
  local slug="$1" resposta='' token=''
  [[ -n "$slug" ]] || { printf 'DESCONHECIDO'; return; }
  if command -v gh >/dev/null 2>&1; then
    resposta="$(gh api "repos/$slug" --jq '.visibility' 2>/dev/null)" || resposta=''
    case "$resposta" in public) printf 'PUBLICO'; return;; private) printf 'PRIVADO'; return;; internal) printf 'INTERNO'; return;; esac
  fi
  if command -v curl >/dev/null 2>&1; then
    token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then token="$(gh auth token 2>/dev/null)" || token=''; fi
    if [[ -n "$token" ]]; then
      resposta="$(curl -fsSL --connect-timeout 3 --max-time 8 -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $token" "https://api.github.com/repos/$slug" 2>/dev/null)" || resposta=''
    else
      resposta="$(curl -fsSL --connect-timeout 3 --max-time 8 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$slug" 2>/dev/null)" || resposta=''
    fi
    VISIBILIDADE_JSON="$resposta" python3 -c 'import json,os
try:
 d=json.loads(os.environ["VISIBILIDADE_JSON"])
 print({"public":"PUBLICO","private":"PRIVADO","internal":"INTERNO"}.get(d.get("visibility"),"DESCONHECIDO"),end="")
except (ValueError,TypeError,AttributeError):
 print("DESCONHECIDO",end="")' 2>/dev/null && return
  fi
  printf 'DESCONHECIDO'
}

# Cada linha logica tem 13 campos separados por NUL; suporta espacos e quebras de linha.
while IFS= read -r -d '' gitmarker; do
  repo="$(dirname -- "$gitmarker")"
  nome="${repo#"$pasta"/}"
  [[ "$repo" == "$pasta" ]] && nome="$(basename -- "$repo")"
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" || branch='(detached HEAD)'
  status="$(git -C "$repo" status --porcelain --untracked-files=normal 2>&1)"
  status_code=$?
  qtd_alterados=0
  if ((status_code == 0)) && [[ -n "$status" ]]; then
    # --porcelain -z: contagem robusta inclusive para nomes com quebras de linha.
    qtd_alterados="$(git -C "$repo" status --porcelain -z --untracked-files=normal | python3 -c 'import sys
b=sys.stdin.buffer.read().split(b"\0"); b=b[:-1] if b and b[-1]==b"" else b
n=0;i=0
while i<len(b):
 x=b[i]; n+=1; i+=2 if x[:2] in (b"R ",b" R",b"RM",b"MR",b"RR",b"C ",b" C",b"CM",b"MC") else 1
print(n)' 2>/dev/null)" || qtd_alterados=0
  fi
  situacao=''; detalhes=''; autor=''; data_commit=''; mensagem=''; timestamp=''; upstream=''
  if ! git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1; then
    situacao='SEM COMMITS'; detalhes='Repositorio sem commit inicial'
  elif ((status_code != 0)); then
    situacao='ERRO STATUS'; detalhes="$status"
  else
    upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || upstream=''
    if [[ -z "$upstream" ]]; then
      situacao='SEM UPSTREAM'; detalhes='Branch sem remoto de acompanhamento'
    else
      remoto="$(git -C "$repo" config "branch.$branch.remote" 2>/dev/null)" || remoto=''
      if ((sem_fetch == 0)) && [[ -n "$remoto" && "$remoto" != '.' ]]; then
        if ! fetch_msg="$(git -C "$repo" -c credential.interactive=never fetch --quiet "$remoto" 2>&1)"; then
          situacao='ERRO FETCH'; detalhes="Falha ao consultar remoto: $fetch_msg"
        fi
      fi
      if [[ -z "$situacao" ]]; then
        counts="$(git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>&1)"
        code=$?
        if ((code != 0)) || ! [[ "$counts" =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
          situacao='ERRO COMPARACAO'; detalhes="$counts"
        else
          ahead=$((10#${BASH_REMATCH[1]})); behind=$((10#${BASH_REMATCH[2]}))
          if ((ahead == 0 && behind == 0)); then situacao='SINCRONIZADO'
          elif ((ahead > 0 && behind > 0)); then situacao='DIVERGENTE'
          elif ((ahead > 0)); then situacao='ENVIAR'
          else situacao='RECEBER'; fi
          detalhes="Enviar: $ahead | Receber: $behind"
        fi
      fi
    fi
  fi
  if ((status_code == 0 && qtd_alterados > 0)); then
    [[ "$situacao" == 'SINCRONIZADO' ]] && situacao='ALTERACOES LOCAIS'
    [[ -n "$detalhes" ]] && detalhes+=' | '
    detalhes+="Arquivos alterados: $qtd_alterados"
  fi
  if git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1; then
    # Uma unica consulta para metadados do commit, data exibida na hora local.
    IFS=$'\x1f' read -r autor data_commit timestamp mensagem < <(git -C "$repo" log -1 --date=format-local:'%Y-%m-%d %H:%M:%S' --format='%an%x1f%cd%x1f%ct%x1f%s' 2>/dev/null)
  fi
  remote_url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || remote_url=''
  slug="$(github_slug "$remote_url")"
  visibilidade="$(visibilidade_git "$slug")"
  principal='NAO'; [[ "$branch" == 'main' || "$branch" == 'master' ]] && principal='SIM'
  printf '%s\0' "$nome" "$visibilidade" "$branch" "$principal" "$situacao" "$detalhes" "$qtd_alterados" "$autor" "$data_commit" "$timestamp" "$mensagem" "$remote_url" "$repo" >> "$tmp"
done < <(find "$pasta" \( -name .git \( -type d -o -type f \) -print0 -prune \) -o \( -type d \( -name node_modules -o -name .venv -o -name venv -o -name dist -o -name build \) -prune \) 2>/dev/null)

python3 - "$tmp" "$pasta" "$somente_problemas" "$dias_inatividade" <<'PY'
import csv, datetime as dt, html, json, os, sys
from collections import Counter
from pathlib import Path

source, root, only_problems, inactive_days = sys.argv[1:]
only_problems = only_problems == '1'
inactive_days = int(inactive_days)
root = Path(root)
fields = ['Projeto','Visibilidade','Branch','BranchPrincipal','Situacao','Detalhes',
          'ArquivosAlterados','Autor','DataUltimoCommit','Timestamp','UltimoCommit','Remoto','Caminho']
with open(source, 'rb') as f:
    parts = f.read().split(b'\0')
if parts and parts[-1] == b'': parts.pop()
if len(parts) % len(fields):
    raise SystemExit('Erro: registro de repositorio incompleto; relatorios nao foram modificados.')
rows = []
now = dt.datetime.now(dt.timezone.utc)
for i in range(0,len(parts),len(fields)):
    row = dict(zip(fields,(os.fsdecode(p) for p in parts[i:i+len(fields)])))
    row['ArquivosAlterados'] = int(row['ArquivosAlterados'] or 0)
    ts = int(row['Timestamp']) if row['Timestamp'].isdigit() else None
    days = max(0,(now - dt.datetime.fromtimestamp(ts,dt.timezone.utc)).days) if ts is not None else None
    row['DiasSemAtividade'] = days
    row['Inativo'] = 'SIM' if days is not None and days >= inactive_days else 'NAO'
    row.pop('Timestamp')
    row['_timestamp'] = ts
    rows.append(row)
# Ordenacao real por instante do commit, nao por string formatada ou dias arredondados.
rows.sort(key=lambda r: (-r['_timestamp'] if r['_timestamp'] is not None else float('inf'),r['Projeto'].casefold()))
all_rows = rows
rows = [r for r in rows if r['Situacao'] != 'SINCRONIZADO'] if only_problems else rows
# Saude estrita: somente sincronizados E sem alteracoes locais.
healthy = sum(r['Situacao'] == 'SINCRONIZADO' and r['ArquivosAlterados'] == 0 for r in all_rows)
health = round(100 * healthy / len(all_rows)) if all_rows else 0
run_at = dt.datetime.now().astimezone().isoformat(timespec='seconds')
columns = ['Projeto','Visibilidade','Branch','BranchPrincipal','Situacao','Detalhes',
           'ArquivosAlterados','Autor','DataUltimoCommit','DiasSemAtividade','Inativo',
           'UltimoCommit','Remoto','Caminho']
export_rows = [{k:r[k] for k in columns} for r in rows]

# CSV com BOM UTF-8 para abrir acentuacao corretamente em planilhas.
with open(root/'relatorio-git.csv','w',encoding='utf-8-sig',newline='') as f:
    writer = csv.DictWriter(f,fieldnames=columns)
    writer.writeheader(); writer.writerows(export_rows)
with open(root/'relatorio-git.json','w',encoding='utf-8') as f:
    json.dump({'DataExecucao':run_at,'TotalProjetos':len(all_rows),'ProjetosExibidos':len(rows),
               'IndiceSaude':health,'FiltroSomenteProblemas':only_problems,
               'LimiteInatividadeDias':inactive_days,'Projetos':export_rows},f,ensure_ascii=False,indent=2)

hist_path = root/'historico-git.json'
history = []
if hist_path.exists():
    try:
        data = json.loads(hist_path.read_text(encoding='utf-8-sig'))
        if isinstance(data,list): history = data
        elif isinstance(data,dict): history = [data]
    except (OSError,ValueError):
        print('Aviso: historico anterior invalido; sera preservado em vez de sobrescrito.',file=sys.stderr)
        history = None
if history is not None:
    history.append({'DataExecucao':run_at,'TotalProjetos':len(all_rows),'IndiceSaude':health})
    hist_path.write_text(json.dumps(history,ensure_ascii=False,indent=2),encoding='utf-8')

html_cols = ['Projeto','Visibilidade','Branch','Situacao','ArquivosAlterados','Autor',
             'DataUltimoCommit','DiasSemAtividade','Inativo','UltimoCommit','Remoto']
trs = '\n'.join('<tr>'+''.join('<td>'+html.escape(str(r[c] if r[c] is not None else '—'))+'</td>' for c in html_cols)+'</tr>' for r in export_rows)
heads = ''.join('<th>'+html.escape(c)+'</th>' for c in html_cols)
page = f'''<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Relatório Git V5</title><style>
body{{font:14px system-ui, sans-serif;margin:24px;background:#f8fafc;color:#172033}}
h1{{margin-bottom:8px}}.meta{{margin-bottom:22px}}.table{{overflow-x:auto;background:white;border:1px solid #dce3ec;border-radius:8px}}
table{{border-collapse:collapse;width:100%}}th{{background:#1e293b;color:white;text-align:left;white-space:nowrap}}
th,td{{padding:10px;border-bottom:1px solid #e5e7eb;vertical-align:top}}tr:nth-child(even){{background:#f3f6fa}}
tr:hover{{background:#e7eef8}}td{{max-width:360px;overflow-wrap:anywhere}}
</style></head><body><h1>Relatório Git V5</h1><p class="meta">Execução: {html.escape(run_at)}<br>
Total de projetos: {len(all_rows)} | Exibidos: {len(rows)} | Índice de saúde (sincronização estrita): {health}%<br>
Ordenação: último commit, mais recente primeiro. Inatividade: {inactive_days} dias.</p>
<div class="table"><table><thead><tr>{heads}</tr></thead><tbody>{trs}</tbody></table></div></body></html>'''
(root/'relatorio-git.html').write_text(page,encoding='utf-8')

print('\n=== RESUMO GERAL ===')
print(f'Total de projetos: {len(all_rows)} | Exibidos: {len(rows)} | Indice de saude: {health}%')
for name,count in sorted(Counter(r['Situacao'] for r in all_rows).items()):
    print(f'  {name:<23} {count:>4}')
print('\nPROJETOS POR ULTIMO COMMIT (MAIS RECENTES PRIMEIRO)')
show_cols = ['Projeto','Branch','Situacao','DataUltimoCommit','ArquivosAlterados','DiasSemAtividade','Inativo']
if not rows:
    print('Nenhum projeto corresponde ao filtro.' if only_problems else 'Nenhum repositorio Git encontrado.')
else:
    widths = [min(40,max(len(c),*(len(str(r[c] if r[c] is not None else '—')) for r in rows))) for c in show_cols]
    print('  '.join(c.ljust(w) for c,w in zip(show_cols,widths)))
    print('  '.join('-'*w for w in widths))
    for r in rows:
        print('  '.join(str(r[c] if r[c] is not None else '—')[:w].ljust(w) for c,w in zip(show_cols,widths)))
committed = [r for r in rows if r['_timestamp'] is not None]
for label,subset in [('TOP 5 MAIS RECENTES',committed[:5]),('TOP 5 MAIS ANTIGOS',list(reversed(committed[-5:])) )]:
    print('\n'+label)
    for r in subset:
        print(f"  {r['Projeto']:<35.35} {r['DataUltimoCommit']}  ({r['DiasSemAtividade']} dias)")
for name in ['relatorio-git.csv','relatorio-git.json','relatorio-git.html','historico-git.json']:
    if (root/name).exists(): print(f'{name}: {root/name}')
PY

# Abre o relatorio no navegador padrao quando ha sessao grafica.
relatorio_html="$pasta/relatorio-git.html"
if ((sem_abrir == 0)) && [[ -f "$relatorio_html" ]]; then
  if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    if command -v xdg-open >/dev/null 2>&1; then
      if ! xdg-open "$relatorio_html" >/dev/null 2>&1; then
        echo "Aviso: nao foi possivel abrir o navegador. Abra manualmente: $relatorio_html" >&2
      fi
    else
      echo "Aviso: xdg-open indisponivel. Abra manualmente: $relatorio_html" >&2
    fi
  else
    echo "Sem sessao grafica; abra o relatorio manualmente: $relatorio_html"
  fi
fi
