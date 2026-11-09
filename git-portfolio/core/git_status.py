from pathlib import Path
from models.repository import Repository
from core.git_sync import compare
from core.git_commits import latest, pending
from services.github import visibility
from utils.commands import git, redact

def count_changes(output: str) -> int:
    entries = output.split('\0')
    count = i = 0
    while i < len(entries) and entries[i]:
        entry = entries[i]
        count += 1
        i += 2 if 'R' in entry[:2] or 'C' in entry[:2] else 1
    return count

def inspect(repo: Path, root: Path, skip_fetch: bool = False) -> Repository:
    name = str(repo.relative_to(root)) if repo != root else repo.name
    r = Repository(Projeto=name, Caminho=str(repo))
    branch = git(repo,'symbolic-ref','--quiet','--short','HEAD')
    r.Branch = branch.out.strip() if branch.code == 0 else '(detached HEAD)'
    r.BranchPrincipal = 'SIM' if r.Branch in ('main','master') else 'NAO'
    status = git(repo,'status','--porcelain','-z','--untracked-files=normal')
    r.ArquivosAlterados = count_changes(status.out) if status.code == 0 else 0
    upstream = ''
    if git(repo,'rev-parse','--verify','HEAD').code:
        r.Situacao, r.Detalhes = 'SEM COMMITS', 'Repositorio sem commit inicial'
    elif status.code:
        r.Situacao, r.Detalhes = 'ERRO STATUS', (status.error or status.out).strip()
    else:
        r.Situacao, r.Detalhes, upstream = compare(repo, r.Branch, skip_fetch)
    if r.ArquivosAlterados:
        if r.Situacao == 'SINCRONIZADO':
            r.Situacao = 'ALTERACOES LOCAIS'
        r.Detalhes += (' | ' if r.Detalhes else '') + f'Arquivos alterados: {r.ArquivosAlterados}'
    metadata = latest(repo)
    if metadata:
        r.Autor, r.DataUltimoCommit, r._timestamp, r.UltimoCommit = metadata
    if r.Situacao in ('RECEBER','DIVERGENTE'):
        r.CommitsPendentes = pending(repo, upstream)
    remote = git(repo,'remote','get-url','origin')
    url = remote.out.strip() if remote.code == 0 else ''
    r.Visibilidade = visibility(url)
    r.Remoto = redact(url)
    return r
