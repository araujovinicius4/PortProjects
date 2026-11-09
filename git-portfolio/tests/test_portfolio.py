import contextlib
import csv
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import shlex
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from core.scanner import discover
from core.git_status import inspect, count_changes
from models.repository import Repository
from services.health import prepare, health
from services.github import github_slug, commit_url, visibility
from reports.generator import generate
from utils.commands import run, redact
from utils.browser import open_report
from main import main, parser


class GitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / 'remote.git'
        self.git(self.root, 'init', '--bare', str(self.remote))
        self.local = self.root / 'projeto espaço & ç'
        self.git(self.root,'init','-b','main',str(self.local))
        self.configure(self.local)
        self.commit(self.local, 'inicial')
        self.git(self.local,'remote','add','origin',str(self.remote))
        self.git(self.local,'push','-u','origin','main')
        self.other = self.root / 'outro'
        self.git(self.root,'clone','-b','main',str(self.remote),str(self.other))
        self.configure(self.other)

    def git(self, repo, *args):
        result = subprocess.run(['git','-C',str(repo),*args],capture_output=True,encoding='utf-8',errors='replace',timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        return result.stdout

    def configure(self, repo):
        self.git(repo,'config','user.name','Autor Teste')
        self.git(repo,'config','user.email','teste@example.invalid')
        self.git(repo,'config','commit.gpgsign','false')

    def commit(self, repo, message):
        with (repo/'arquivo especial & ç.txt').open('a',encoding='utf-8') as stream:
            stream.write(message+'\n')
        self.git(repo,'add','--all')
        self.git(repo,'commit','-m',message)

    def audit(self, skip=True):
        return inspect(self.local,self.root,skip)

    def test_synchronized_and_local_changes(self):
        self.assertEqual(self.audit().Situacao,'SINCRONIZADO')
        (self.local/'não rastreado & espaço.txt').write_text('x')
        r=self.audit()
        self.assertEqual((r.Situacao,r.ArquivosAlterados),('ALTERACOES LOCAIS',1))
        self.git(self.local,'mv','arquivo especial & ç.txt','renomeado.txt')
        self.assertEqual(self.audit().ArquivosAlterados,2)

    def test_ahead(self):
        self.commit(self.local,'enviar')
        self.assertEqual(self.audit().Situacao,'ENVIAR')

    def test_behind_and_pending(self):
        self.commit(self.other,'receber <script>')
        self.git(self.other,'push')
        self.assertEqual(self.audit().Situacao,'SINCRONIZADO')
        r=self.audit(False)
        self.assertEqual(r.Situacao,'RECEBER')
        self.assertEqual(r.CommitsPendentes[0].mensagem,'receber <script>')
        self.assertEqual(len(r.CommitsPendentes[0].hash),40)
        self.assertEqual(self.git(self.local,'log','-1','--format=%s').strip(),'inicial')
        with contextlib.redirect_stdout(io.StringIO()):
            generate(self.root,prepare([r],180),False,180)
        page=(self.root/'relatorio-git.html').read_text(encoding='utf-8')
        self.assertIn('<details',page)
        self.assertIn('receber &lt;script&gt;',page)
        self.assertIn('conic-gradient(',page)

    def test_divergent(self):
        self.commit(self.other,'remoto')
        self.git(self.other,'push')
        self.commit(self.local,'local')
        r=self.audit(False)
        self.assertEqual(r.Situacao,'DIVERGENTE')
        self.assertEqual(len(r.CommitsPendentes),1)

    def test_no_commits_and_upstream(self):
        repo=self.root/'vazio'
        self.git(self.root,'init','-b','main',str(repo))
        self.assertEqual(inspect(repo,self.root,True).Situacao,'SEM COMMITS')
        self.git(self.local,'branch','--unset-upstream')
        self.assertEqual(self.audit().Situacao,'SEM UPSTREAM')

    def test_fetch_failure(self):
        self.git(self.local,'remote','set-url','origin',str(self.root/'inexistente'))
        self.assertEqual(self.audit(False).Situacao,'ERRO FETCH')
        self.assertEqual(self.audit(True).Situacao,'SINCRONIZADO')

    def test_worktree_and_exclusions(self):
        tree=self.root/'worktree'
        self.git(self.local,'worktree','add','-b','worktree',str(tree))
        for name in ('node_modules','.venv','venv','dist','build'):
            ignored=self.root/name/'repo'
            ignored.mkdir(parents=True)
            self.git(ignored,'init')
        repos=list(discover(self.root))
        self.assertEqual(set(repos),{self.local,self.other,tree})
        self.assertEqual(inspect(tree,self.root,True).Branch,'worktree')

    def test_cli_reports(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(['--pasta',str(self.root),'--sem-fetch','--sem-abrir']),0)
        report=json.loads((self.root/'relatorio-git.json').read_text(encoding='utf-8'))
        self.assertEqual(report['TotalProjetos'],2)
        self.assertEqual(report['IndiceSaude'],100)

    def test_bash_v51_compatibility(self):
        bash = os.environ.get('GIT_PORTFOLIO_BASH') or shutil.which('bash')
        if not bash:
            self.skipTest('Bash indisponível; defina GIT_PORTFOLIO_BASH')
        original = Path(__file__).resolve().parents[2] / 'verificar-projetos-git-v5-1.sh'
        if not original.exists():
            self.skipTest('Script Bash de referência não encontrado')
        # The Windows Store python3 alias is not a Python interpreter. Supply a shim
        # only inside this temporary test environment, without modifying user PATH.
        bin_dir = self.root/'bin'
        bin_dir.mkdir()
        shim = bin_dir/'python3'
        shim.write_text('#!/usr/bin/env bash\nexec '+shlex.quote(Path(sys.executable).as_posix())+' "$@"\n',encoding='utf-8')
        shim.chmod(0o755)
        fixture = self.root/'cenários'
        fixture.mkdir()
        for name in ('sincronizado','enviar','receber','divergente','alterações','sem upstream'):
            repo = fixture/name
            self.git(fixture,'clone','-b','main',str(self.remote),str(repo))
            self.configure(repo)
            if name in ('enviar','divergente'):
                self.commit(repo,'commit local')
            if name == 'alterações':
                (repo/'espaço & ç.txt').write_text('local',encoding='utf-8')
            if name == 'sem upstream':
                self.git(repo,'branch','--unset-upstream')
        self.commit(self.other,'commit remoto')
        self.git(self.other,'push')
        for name in ('receber','divergente'):
            self.git(fixture/name,'fetch')
        self.git(fixture,'init','-b','main',str(fixture/'sem commits'))
        env=dict(os.environ,PATH=str(bin_dir)+os.pathsep+os.environ['PATH'])
        for only in (False,True):
            flags=['--pasta',str(fixture),'--sem-fetch','--sem-abrir','--dias-inatividade','0']
            if only:
                flags.append('--somente-problemas')
            result=subprocess.run([bash,str(original),*flags],env=env,capture_output=True,encoding='utf-8',errors='replace',timeout=120)
            self.assertEqual(result.returncode,0,result.stderr)
            reference=json.loads((fixture/'relatorio-git.json').read_text(encoding='utf-8'))
            reference_csv=(fixture/'relatorio-git.csv').read_bytes()
            with contextlib.redirect_stdout(io.StringIO()):
                generate(fixture,prepare([inspect(repo,fixture,True) for repo in discover(fixture)],0),only,0)
            actual=json.loads((fixture/'relatorio-git.json').read_text(encoding='utf-8'))
            for data in (reference,actual):
                data.pop('DataExecucao')
                for row in data['Projetos']:
                    # Git Bash emits /c/... and Python emits C:\... on Windows.
                    row.pop('Caminho')
            self.assertEqual(actual,reference)
            # All CSV fields except platform-dependent absolute paths are identical.
            before=list(csv.DictReader(io.StringIO(reference_csv.decode('utf-8-sig'))))
            with (fixture/'relatorio-git.csv').open(encoding='utf-8-sig',newline='') as stream:
                after=list(csv.DictReader(stream))
            for data in (before,after):
                for row in data:
                    row.pop('Caminho')
            self.assertEqual(after,before)


class LogicTests(unittest.TestCase):
    def test_sort_inactivity_health_and_filter(self):
        repos=[Repository('sem','/sem'),Repository('antigo','/a',Situacao='ENVIAR',_timestamp=0),
               Repository('novo','/n',Situacao='SINCRONIZADO',_timestamp=86400)]
        rows=prepare(repos,2,datetime.fromtimestamp(3*86400,timezone.utc))
        self.assertEqual([r['Projeto'] for r in rows],['novo','antigo','sem'])
        self.assertEqual([r['Inativo'] for r in rows],['SIM','SIM','NAO'])
        self.assertEqual(health(rows),33)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            path=root/'historico-git.json'
            path.write_text('{"antigo":true}')
            with contextlib.redirect_stdout(io.StringIO()):
                generate(root,rows,True,2)
            report=json.loads((root/'relatorio-git.json').read_text(encoding='utf-8'))
            self.assertEqual(report['ProjetosExibidos'],2)
            self.assertEqual(report['IndiceSaude'],33)
            self.assertNotIn('_timestamp',report['Projetos'][0])
            self.assertEqual(json.loads(path.read_text())[0],{'antigo':True})
            with (root/'relatorio-git.csv').open(encoding='utf-8-sig',newline='') as stream:
                data=list(csv.DictReader(stream))
            self.assertEqual(len(data),2)
            self.assertIsInstance(json.loads(data[0]['CommitsPendentes']),list)
            path.write_text('inválido',encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
                generate(root,rows,False,2)
            self.assertEqual(path.read_text(encoding='utf-8'),'inválido')

    def test_github_and_safe_urls(self):
        for url in ('https://github.com/a/b.git','git@github.com:a/b.git','ssh://git@github.com:22/a/b.git'):
            self.assertEqual(github_slug(url),'a/b')
            self.assertEqual(commit_url(url,'a'*40),'https://github.com/a/b/commit/'+'a'*40)
        for url in ('https://github.com.evil/a/b','https://github.com/a/b?q=1','file:///tmp/repo','https://github.com/a/b/c'):
            self.assertEqual(github_slug(url),'')
        self.assertIsNone(commit_url('https://github.com/a/b','<script>'))
        self.assertEqual(visibility('local'),'DESCONHECIDO')
        from utils.commands import Result
        with patch('services.github.run',return_value=Result(0,'private\n')):
            self.assertEqual(visibility('https://github.com/a/b'),'PRIVADO')
        with patch('services.github.run',return_value=Result(1)),patch('services.github.urlopen',side_effect=OSError):
            self.assertEqual(visibility('https://github.com/a/b'),'DESCONHECIDO')

    def test_timeouts_redaction_and_browser(self):
        self.assertEqual(run(['missing-git-portfolio-executable']).code,127)
        with patch('utils.commands.subprocess.run',side_effect=subprocess.TimeoutExpired('git',1)):
            self.assertEqual(run(['git']).code,124)
        self.assertNotIn('segredo',redact('https://segredo@github.com/a/b'))
        with patch.dict(os.environ,{'GH_TOKEN':'segredo'}):
            self.assertEqual(redact('segredo'),'[credencial]')
        with patch('utils.browser.webbrowser.open',return_value=True) as browser:
            open_report(Path('arquivo espaço.html'))
            self.assertTrue(browser.call_args[0][0].startswith('file:'))

    def test_argument_validation(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                parser().parse_args(['--dias-inatividade','-1'])
        self.assertEqual(error.exception.code,2)
        self.assertEqual(count_changes('R  new\0old\0?? space\0'),2)

    def test_empty_reports(self):
        with tempfile.TemporaryDirectory() as directory,contextlib.redirect_stdout(io.StringIO()):
            generate(Path(directory),[],False,180)
            self.assertEqual(json.loads((Path(directory)/'relatorio-git.json').read_text())['IndiceSaude'],0)

if __name__ == '__main__':
    unittest.main()
