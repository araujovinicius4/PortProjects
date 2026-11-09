import argparse
import shutil
import sys
from pathlib import Path
# Also support portable Python distributions with an isolated module search path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from config.settings import DEFAULT_ROOT
from core.scanner import discover
from core.git_status import inspect
from services.health import prepare
from reports.generator import generate
from utils.browser import open_report

class Parser(argparse.ArgumentParser):
    def error(self, message):
        message = message.replace('unrecognized arguments:', 'argumentos desconhecidos:').replace('expected one argument', 'informe um valor').replace('argument ', 'argumento ')
        self.print_usage(sys.stderr)
        self.exit(2, f'Erro nos argumentos: {message}\n')

def nonnegative(value: str) -> int:
    if not value.isascii() or not value.isdigit():
        raise argparse.ArgumentTypeError('Informe um número inteiro não negativo')
    return int(value)

def parser() -> argparse.ArgumentParser:
    p = Parser(description='Git Portfolio: auditoria de repositórios Git', add_help=False, usage='%(prog)s [opções]')
    p._optionals.title = 'opções'
    p.add_argument('-h','--ajuda',action='help',help='Exibe esta ajuda')
    p.add_argument('--pasta',type=Path,default=DEFAULT_ROOT,help=f'Diretório raiz (padrão: {DEFAULT_ROOT})')
    p.add_argument('--sem-fetch',action='store_true',help='Não atualiza referências remotas')
    p.add_argument('--somente-problemas',action='store_true',help='Mostra/exporta apenas projetos não sincronizados')
    p.add_argument('--dias-inatividade',type=nonnegative,default=180,help='Limite de inatividade em dias (padrão: 180)')
    p.add_argument('--sem-abrir',action='store_true',help='Não abre o relatório HTML no navegador')
    return p

def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    root = args.pasta.expanduser().resolve()
    if not root.is_dir():
        print(f'Pasta não encontrada: {root}',file=sys.stderr)
        return 1
    if not shutil.which('git'):
        print('Dependência ausente: git',file=sys.stderr)
        return 1
    try:
        repositories = [inspect(repo,root,args.sem_fetch) for repo in discover(root)]
        generate(root,prepare(repositories,args.dias_inatividade),args.somente_problemas,args.dias_inatividade)
        if not args.sem_abrir:
            open_report(root/'relatorio-git.html')
    except (OSError, ValueError) as exc:
        print(f'Erro ao gerar auditoria: {exc}',file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
