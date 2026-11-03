param(
    [string]$Pasta = 'C:\Users\sebastiao.moura\Documents\1Portifolio',
    [switch]$SemFetch
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error 'Git não encontrado no PATH.'
    exit 1
}

if (-not (Test-Path -LiteralPath $Pasta -PathType Container)) {
    Write-Error "Pasta não encontrada: $Pasta"
    exit 1
}

function Invoke-Git {
    param(
        [string]$Repo,
        [string[]]$GitArgs
    )

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $output = @(& git -C $Repo @GitArgs 2>&1)
        $code = $LASTEXITCODE

        $lines = @(
            $output |
            Where-Object { $_ -is [string] } |
            ForEach-Object { [string]$_ }
        )

        [pscustomobject]@{
            Code = $code
            Text = ($lines -join "`n").Trim()
        }
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

$repos = New-Object System.Collections.Generic.List[string]

$dirs = New-Object System.Collections.Generic.Stack[string]

$dirs.Push((Resolve-Path -LiteralPath $Pasta).Path)

while ($dirs.Count -gt 0) {

    $dir = $dirs.Pop()

    if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
        $repos.Add($dir)
        continue
    }

    foreach ($child in (Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue)) {

        if ($child.Name -in @(
                'node_modules',
                '.venv',
                'venv',
                'dist',
                'build',
                '.git'
            )) { continue }

        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            continue
        }

        $dirs.Push($child.FullName)
    }
}

$resultados = @(
foreach ($repo in ($repos | Sort-Object)) {

    $nome = $repo.Substring($Pasta.TrimEnd('\').Length).TrimStart('\')

    if (-not $nome) {
        $nome = Split-Path $repo -Leaf
    }

    $branchResult = Invoke-Git $repo @(
        'symbolic-ref',
        '--quiet',
        '--short',
        'HEAD'
    )

    $branch = if ($branchResult.Code -eq 0) {
        $branchResult.Text
    }
    else {
        '(detached HEAD)'
    }

    $statusResult = Invoke-Git $repo @(
        'status',
        '--porcelain',
        '--untracked-files=normal'
    )

    $temMudancas =
    ($statusResult.Code -eq 0 -and
     -not [string]::IsNullOrWhiteSpace($statusResult.Text))

    $headResult =
    Invoke-Git $repo @(
        'rev-parse',
        '--verify',
        'HEAD'
    )

    $situacao = ''
    $detalhes = ''

    if ($headResult.Code -ne 0) {

        $situacao = 'SEM COMMITS'
        $detalhes = 'Repositório sem commit inicial'
    }
    else {

        $upResult = Invoke-Git $repo @(
            'rev-parse',
            '--abbrev-ref',
            '--symbolic-full-name',
            '@{upstream}'
        )

        if ($upResult.Code -ne 0 -or -not $upResult.Text) {

            $situacao = 'SEM UPSTREAM'
            $detalhes = 'Branch sem remoto de acompanhamento'
        }
        else {

            $upstream = $upResult.Text

            $remoteResult =
            Invoke-Git $repo @(
                'config',
                "branch.$branch.remote"
            )

            $remoto =
            if ($remoteResult.Code -eq 0) {
                $remoteResult.Text
            }
            else {
                ''
            }

            if (-not $SemFetch -and
                $remoto -and
                $remoto -ne '.') {

                $fetchResult =
                Invoke-Git $repo @(
                    'fetch',
                    '--quiet',
                    $remoto
                )

                if ($fetchResult.Code -ne 0) {

                    $situacao = 'ERRO FETCH'
                    $detalhes =
                    'Falha ao consultar remoto'
                }
            }

            if (-not $situacao) {

                $countsResult =
                Invoke-Git $repo @(
                    'rev-list',
                    '--left-right',
                    '--count',
                    "HEAD...$upstream"
                )

                $counts =
                @(
                    $countsResult.Text -split '\s+' |
                    Where-Object { $_ }
                )

                if ($countsResult.Code -eq 0 -and
                    $counts.Count -ge 2) {

                    $ahead = [int]$counts[0]
                    $behind = [int]$counts[1]

                    if ($ahead -eq 0 -and $behind -eq 0) {
                        $situacao = 'SINCRONIZADO'
                    }
                    elseif ($ahead -gt 0 -and $behind -gt 0) {
                        $situacao = 'DIVERGENTE'
                    }
                    elseif ($ahead -gt 0) {
                        $situacao = 'ENVIAR'
                    }
                    else {
                        $situacao = 'RECEBER'
                    }

                    $detalhes =
                    "Enviar: $ahead | Receber: $behind"
                }
            }
        }
    }

    if ($temMudancas) {

        if ($situacao -eq 'SINCRONIZADO') {
            $situacao = 'ALTERACOES LOCAIS'
        }

        $detalhes += ' | Arquivos modificados/novos'
    }

    # Último commit
    $autor =
    (Invoke-Git $repo @(
        'log',
        '-1',
        '--pretty=%an'
    )).Text

    $dataCommit =
    (Invoke-Git $repo @(
        'log',
        '-1',
        '--date=short',
        '--pretty=%cd'
    )).Text

    $mensagemCommit =
    (Invoke-Git $repo @(
        'log',
        '-1',
        '--pretty=%s'
    )).Text

    $diasSemAtividade = ''

    try {

        if ($dataCommit) {

            $diasSemAtividade =
            [math]::Floor(
                ((Get-Date) - ([datetime]$dataCommit)).TotalDays
            )
        }
    }
    catch { }

    $abandonado =
    if ($diasSemAtividade -ge 180) {
        'SIM'
    }
    else {
        'NAO'
    }

    [pscustomobject]@{

        Projeto = $nome
        Branch = $branch
        Situacao = $situacao
        Detalhes = $detalhes.Trim(' ','|')

        Autor = $autor
        DataUltimoCommit = $dataCommit
        DiasSemAtividade = $diasSemAtividade
        Abandonado = $abandonado
        UltimoCommit = $mensagemCommit

        Caminho = $repo
    }
}
)

if ($resultados.Count -eq 0) {

    Write-Host 'Nenhum repositório Git encontrado.'
    exit 0
}

Write-Host ""
Write-Host "===============================" -ForegroundColor Cyan
Write-Host " RESUMO GERAL"
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""

$total = $resultados.Count

Write-Host ("Total de Projetos : {0}" -f $total)

$resultados |
Group-Object Situacao |
Sort-Object Name |
ForEach-Object {

    Write-Host (
        "{0,-20} {1,5}" -f $_.Name,$_.Count
    )
}

Write-Host ""

$resultados |
Format-Table `
Projeto,
Branch,
Situacao,
DiasSemAtividade,
Abandonado,
DataUltimoCommit `
-AutoSize -Wrap

$csv = Join-Path $Pasta 'relatorio-git.csv'

$resultados |
Export-Csv `
-LiteralPath $csv `
-NoTypeInformation `
-Encoding UTF8

$html = Join-Path $Pasta 'relatorio-git.html'

$css = @"
<style>
body{
font-family:Segoe UI;
margin:20px;
}

table{
border-collapse:collapse;
width:100%;
}

th{
background:#1f2937;
color:white;
padding:8px;
}

td{
padding:8px;
border-bottom:1px solid #ddd;
}

tr:nth-child(even){
background:#f7f7f7;
}
</style>
"@

$resultados |
Select-Object `
Projeto,
Branch,
Situacao,
Autor,
DataUltimoCommit,
DiasSemAtividade,
Abandonado,
UltimoCommit |
ConvertTo-Html `
-Title "Relatório Git" `
-Head $css |
Set-Content `
-Encoding UTF8 `
-Path $html

Write-Host ""
Write-Host "CSV salvo em: $csv" -ForegroundColor Green
Write-Host "HTML salvo em: $html" -ForegroundColor Green

# Estatísticas

Write-Host ""
Write-Host "==============================="
Write-Host " ESTATÍSTICAS"
Write-Host "==============================="
Write-Host ""

$maisAntigo =
$resultados |
Sort-Object DiasSemAtividade -Descending |
Select-Object -First 1

$maisRecente =
$resultados |
Sort-Object DiasSemAtividade |
Select-Object -First 1

Write-Host "Projeto mais recente:"
Write-Host ("  {0} ({1} dias)" -f $maisRecente.Projeto,$maisRecente.DiasSemAtividade)

Write-Host ""
Write-Host "Projeto mais antigo:"
Write-Host ("  {0} ({1} dias)" -f $maisAntigo.Projeto,$maisAntigo.DiasSemAtividade)