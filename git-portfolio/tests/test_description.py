import contextlib
import csv
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from core.description import describe, extract_readme, UNAVAILABLE
from models.repository import Repository
from reports.generator import generate
from services.health import prepare


class DescriptionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def test_manual_priority(self):
        (self.root/'README.md').write_text('Ajuda equipes a organizar tarefas locais.', encoding='utf-8')
        (self.root/'portfolio.json').write_text(json.dumps({'problema': 'Resolve a perda de dados em arquivos locais.'}), encoding='utf-8')
        self.assertEqual(describe(self.root), 'Resolve a perda de dados em arquivos locais.')

    def test_readme_priority_and_plain_text(self):
        (self.root/'rEaDmE.MD').write_text('''# Projeto

Uma ferramenta para organizar arquivos pessoais.

## Problema

Evita **duplicação** de [arquivos](https://example.invalid) em pastas locais.

## Instalação

pip install projeto
''', encoding='utf-8')
        self.assertEqual(describe(self.root), 'Evita duplicação de arquivos em pastas locais.')

    def test_fallback_and_limits(self):
        self.assertEqual(extract_readme('# Título\n\n![badge](x)\n\n```sh\npip install teste\n```\n\nOrganiza documentos para facilitar consultas futuras.'),
                         'Organiza documentos para facilitar consultas futuras.')
        text = 'Resolve problemas com arquivos locais. ' + 'Mais informações sobre os arquivos ' * 20
        self.assertEqual(extract_readme(text), 'Resolve problemas com arquivos locais.')
        self.assertLessEqual(len(extract_readme('Palavra descritiva ' * 100)), 300)

    def test_missing_and_insufficient(self):
        self.assertEqual(describe(self.root), UNAVAILABLE)
        self.assertEqual(extract_readme('# Instalação\n\nPrimeiro baixe todos os arquivos para a pasta local.'), UNAVAILABLE)
        (self.root/'README.md').write_text('# Apenas título\n\n![badge](x)\n\n## Instalação\n\npip install exemplo', encoding='utf-8')
        self.assertEqual(describe(self.root), UNAVAILABLE)

    def test_invalid_manual_and_unreadable(self):
        readme = self.root/'README.md'
        readme.write_text('Organiza documentos para facilitar consultas futuras.', encoding='utf-8')
        for invalid in ('{', '[]', '{"problema": 123}', '{"problema": " "}'):
            (self.root/'portfolio.json').write_text(invalid, encoding='utf-8')
            self.assertEqual(describe(self.root), 'Organiza documentos para facilitar consultas futuras.')
        readme.write_bytes(b'\xff\xfe\x80')
        self.assertEqual(describe(self.root), UNAVAILABLE)
        with patch.object(Path, 'read_text', side_effect=PermissionError):
            self.assertEqual(describe(self.root), UNAVAILABLE)

    def test_safe_html_and_exports(self):
        problem = 'Evita <img src=x onerror=alert(1)> e mantém "dados" & arquivos.'
        rows = prepare([Repository('Projeto <script>', '/repo', Problema=problem)], 180)
        with contextlib.redirect_stdout(io.StringIO()):
            generate(self.root, rows, False, 180)
        page = (self.root/'relatorio-git.html').read_text(encoding='utf-8')
        self.assertIn('&lt;img src=x onerror=alert(1)&gt;', page)
        self.assertNotIn('<img src=x', page)
        self.assertIn('Projeto &lt;script&gt;', page)
        self.assertIn('role="tooltip"', page)
        self.assertIn("event.key === 'Escape'", page)
        self.assertEqual(json.loads((self.root/'relatorio-git.json').read_text(encoding='utf-8'))['Projetos'][0]['Problema'], problem)
        with (self.root/'relatorio-git.csv').open(encoding='utf-8-sig', newline='') as stream:
            self.assertEqual(next(csv.DictReader(stream))['Problema'], problem)
