from dataclasses import dataclass, field, asdict

@dataclass
class Commit:
    hash: str
    autor: str
    data: str
    mensagem: str

@dataclass
class Repository:
    Projeto: str
    Caminho: str
    Visibilidade: str = 'DESCONHECIDO'
    Branch: str = ''
    BranchPrincipal: str = 'NAO'
    Situacao: str = ''
    Detalhes: str = ''
    ArquivosAlterados: int = 0
    Autor: str = ''
    DataUltimoCommit: str = ''
    UltimoCommit: str = ''
    Remoto: str = ''
    CommitsPendentes: list[Commit] = field(default_factory=list)
    DiasSemAtividade: int | None = None
    Inativo: str = 'NAO'
    Problema: str = 'Descrição do problema não disponível'
    _timestamp: int | None = None

    def row(self) -> dict:
        return asdict(self)
