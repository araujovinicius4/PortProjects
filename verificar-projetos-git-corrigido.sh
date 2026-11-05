#!/usr/bin/env bash
# Verifica repositorios Git recursivamente e gera relatorio CSV.
set -u
export LC_ALL=C

usage() {
  cat <<'HELP'
Uso: ./verificar-projetos-git.sh [--pasta CAMINHO] [--sem-fetch] [--ajuda]
  --pasta CAMINHO   Pasta a pesquisar (padrao: $HOME/Documents/1Portifolio)
  --sem-fetch       Nao consulta os remotos; usa referencias locais
  --ajuda           Exibe esta ajuda
HELP
}

pasta="$HOME/Documents/1Portifolio"
sem_fetch=0
while (($#)); do
  case "$1" in
    --pasta) if (($# < 2)); then echo 'Falta caminho apos --pasta' >&2; exit 2; fi; pasta="$2"; shift 2 ;;
    --sem-fetch) sem_fetch=1; shift ;;
    -h|--ajuda) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done
command -v git >/dev/null 2>&1 || { echo 'Git nao encontrado. Instale com: sudo apt install git' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 nao encontrado. Instale com: sudo apt install python3' >&2; exit 1; }
[[ -d "$pasta" ]] || { echo "Pasta nao encontrada: $pasta" >&2; exit 1; }
pasta="$(cd -- "$pasta" && pwd -P)"
saida="$pasta/relatorio-git.csv"
tmp="$(mktemp)" || exit 1
trap 'rm -f -- "$tmp"' EXIT

# Consulta a API do GitHub; repositorios privados exigem autenticacao.
# Configure GH_TOKEN ou GITHUB_TOKEN, ou autentique com gh auth login.
visibilidade_git() {
  local repo="$1" url slug resposta token=''
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || { printf 'DESCONHECIDO'; return; }
  # Aceita URLs HTTPS e SSH, inclusive git@github.com:owner/repo.git.
  if [[ "$url" =~ ^https?://([^/@]+@)?github\.com/([^/?#]+/[^/?#]+)(\.git)?/?$ ]]; then
    slug="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@github\.com:([^[:space:]]+)$ ]]; then
    slug="${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^ssh://git@github\.com(:[0-9]+)?/([^[:space:]]+)$ ]]; then
    slug="${BASH_REMATCH[2]}"
  else
    printf 'DESCONHECIDO'; return
  fi
  slug="${slug%.git}"
  slug="${slug%/}"
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { printf 'DESCONHECIDO'; return; }
  # gh usa as credenciais da conta autenticada e identifica repositorios privados.
  if command -v gh >/dev/null 2>&1; then
    resposta="$(gh api "repos/$slug" --jq '.visibility' 2>/dev/null)" || resposta=''
    case "$resposta" in
      public) printf 'PUBLICO'; return ;;
      private) printf 'PRIVADO'; return ;;
      internal) printf 'INTERNO'; return ;;
    esac
  fi
  token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then
    token="$(gh auth token 2>/dev/null)" || token=''
  fi
  command -v curl >/dev/null 2>&1 || { printf 'DESCONHECIDO'; return; }
  if [[ -n "$token" ]]; then
    resposta="$(curl -fsSL --connect-timeout 3 --max-time 8 -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $token" "https://api.github.com/repos/$slug" 2>/dev/null)" || resposta=''
  else
    resposta="$(curl -fsSL --connect-timeout 3 --max-time 8 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$slug" 2>/dev/null)" || resposta=''
  fi
  VISIBILIDADE_JSON="$resposta" python3 -c 'import json,os
try:
 d=json.loads(os.environ["VISIBILIDADE_JSON"])
 print({"public":"PUBLICO","private":"PRIVADO","internal":"INTERNO"}.get(d.get("visibility"),"DESCONHECIDO"))
except (ValueError,TypeError,AttributeError):
 print("DESCONHECIDO")' 2>/dev/null || printf 'DESCONHECIDO'
}

# Localiza .git (diretorio ou arquivo de worktree/submodulo), sem entrar em repositorios encontrados.
# Nomes sao transmitidos com separador NUL para suportar espacos e caracteres especiais.
while IFS= read -r -d '' gitmarker; do
  repo="$(dirname -- "$gitmarker")"
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" || branch='(detached HEAD)'
  status="$(git -C "$repo" status --porcelain --untracked-files=normal 2>&1)"
  status_code=$?
  mudancas=0
  [[ $status_code -eq 0 && -n "$status" ]] && mudancas=1
  situacao=''
  detalhes=''
  if ! git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1; then
    situacao='SEM COMMITS'
    detalhes='Repositorio ainda sem commit inicial'
  elif ((status_code != 0)); then
    situacao='ERRO STATUS'
    detalhes="$status"
  else
    upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
    if [[ -z "$upstream" ]]; then
      situacao='SEM UPSTREAM'
      detalhes='Branch sem remoto de acompanhamento'
    else
      remoto="$(git -C "$repo" config "branch.$branch.remote" 2>/dev/null)" || remoto=''
      if ((sem_fetch == 0)) && [[ -n "$remoto" && "$remoto" != '.' ]]; then
        if ! fetch_msg="$(git -C "$repo" fetch --quiet "$remoto" 2>&1)"; then
          situacao='ERRO FETCH'
          detalhes="Falha ao consultar remoto: $fetch_msg"
        fi
      fi
      if [[ -z "$situacao" ]]; then
        counts="$(git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>&1)"
        code=$?
        if ((code != 0)) || ! [[ "$counts" =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
          situacao='ERRO COMPARACAO'
          detalhes="$counts"
        else
          ahead=$((10#${BASH_REMATCH[1]}))
          behind=$((10#${BASH_REMATCH[2]}))
          if ((ahead == 0 && behind == 0)); then situacao='SINCRONIZADO'
          elif ((ahead > 0 && behind > 0)); then situacao='DIVERGENTE'
          elif ((ahead > 0)); then situacao='ENVIAR'
          else situacao='RECEBER'; fi
          detalhes="Enviar: $ahead | Receber: $behind"
        fi
      fi
    fi
  fi
  if ((mudancas)); then
    [[ "$situacao" == 'SINCRONIZADO' ]] && situacao='ALTERACOES LOCAIS'
    [[ -n "$detalhes" ]] && detalhes+=' | '
    detalhes+='Arquivos modificados/novos'
  fi
  nome="${repo#"$pasta"/}"
  [[ "$repo" == "$pasta" ]] && nome="$(basename -- "$repo")"
  ultimo_commit="$(git -C "$repo" log -1 --date=format-local:'%d/%m/%Y %H:%M' --format=%cd 2>/dev/null)"
  [[ -n "$ultimo_commit" ]] || ultimo_commit="SEM COMMITS"
  visibilidade="$(visibilidade_git "$repo")"
  printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0' "$nome" "$visibilidade" "$branch" "$ultimo_commit" "$situacao" "$detalhes" "$repo" >> "$tmp"
done < <(find "$pasta" \( -name .git \( -type d -o -type f \) -print0 -prune \) -o \( -type d \( -name node_modules -o -name .venv -o -name venv -o -name dist -o -name build \) -prune \) 2>/dev/null)

python3 - "$tmp" "$saida" <<'PY'
import csv, os, sys
source, destination = sys.argv[1:]
with open(source, 'rb') as f:
    parts = f.read().split(b'\0')
if parts and parts[-1] == b'':
    parts.pop()
rows = [[os.fsdecode(x) for x in parts[i:i+7]] for i in range(0, len(parts), 7)]
rows.sort(key=lambda row: row[0].casefold())
if not rows:
    print('Nenhum repositorio Git encontrado.')
    sys.exit(0)
headers = ['Projeto', 'Visibilidade', 'Branch', 'Ultimo commit', 'Situacao', 'Detalhes', 'Caminho']
with open(destination, 'w', encoding='utf-8-sig', newline='') as f:
    writer = csv.writer(f, delimiter=',')
    writer.writerow(headers)
    writer.writerows(rows)
widths = [min(55, max(len(headers[i]), *(len(row[i]) for row in rows))) for i in range(6)]
print('  '.join(headers[i].ljust(widths[i]) for i in range(6)))
print('  '.join('-' * widths[i] for i in range(6)))
for row in rows:
    print('  '.join(row[i][:widths[i]].ljust(widths[i]) for i in range(6)))
print(f'\nRelatorio CSV salvo em: {destination}')
PY
