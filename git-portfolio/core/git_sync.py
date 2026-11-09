from pathlib import Path
from utils.commands import git

def compare(repo: Path, branch: str, skip_fetch: bool) -> tuple[str, str, str]:
    upstream = git(repo,'rev-parse','--abbrev-ref','--symbolic-full-name','@{upstream}')
    name = upstream.out.strip() if upstream.code == 0 else ''
    if not name:
        return 'SEM UPSTREAM', 'Branch sem remoto de acompanhamento', ''
    remote = git(repo,'config',f'branch.{branch}.remote').out.strip()
    if not skip_fetch and remote and remote != '.':
        result = git(repo,'-c','credential.interactive=never','fetch','--quiet',remote,timeout=60)
        if result.code:
            return 'ERRO FETCH', 'Falha ao consultar remoto: ' + (result.error or result.out).strip(), name
    result = git(repo,'rev-list','--left-right','--count',f'HEAD...{name}')
    try:
        if result.code:
            raise ValueError
        ahead, behind = map(int,result.out.split())
        if ahead < 0 or behind < 0:
            raise ValueError
    except ValueError:
        return 'ERRO COMPARACAO', (result.error or result.out).strip(), name
    state = ('DIVERGENTE' if ahead and behind else 'ENVIAR' if ahead else
             'RECEBER' if behind else 'SINCRONIZADO')
    return state, f'Enviar: {ahead} | Receber: {behind}', name
