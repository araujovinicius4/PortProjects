from pathlib import Path
DEFAULT_ROOT = Path.home() / 'Documents' / '1Portifolio'
EXCLUDED = {'.git', 'node_modules', '.venv', 'venv', 'dist', 'build'}
COLUMNS = ['Projeto','Visibilidade','Branch','BranchPrincipal','Situacao','Detalhes',
           'ArquivosAlterados','Autor','DataUltimoCommit','DiasSemAtividade','Inativo',
           'UltimoCommit','Remoto','Caminho','CommitsPendentes','Problema']
