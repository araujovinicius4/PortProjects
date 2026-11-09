param(
    [string]$Pasta = 'C:\Users\sebastiao.moura\Documents\1Portifolio',
    [switch]$SemFetch
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'Git nao encontrado no PATH.'; exit 1 }
if (-not (Test-Path -LiteralPath $Pasta -PathType Container)) { Write-Error "Pasta nao encontrada: $Pasta"; exit 1 }

# Evita que erros esperados do Git (ex.: branch inexistente) parem o PowerShell 5.1.
function Invoke-Git {
    param([string]$Repo, [string[]]$GitArgs)
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $Repo @GitArgs 2>&1)
        $code = $LASTEXITCODE
        $lines = @($output | Where-Object { $_ -is [string] } | ForEach-Object { [string]$_ })
        return [pscustomobject]@{ Code = $code; Text = ($lines -join "`n").Trim() }
    } finally { $ErrorActionPreference = $oldEap }
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
        if ($child.Name -in @('node_modules','.venv','venv','dist','build','.git')) { continue }
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $dirs.Push($child.FullName)
    }
}

$resultados = @(
foreach ($repo in ($repos | Sort-Object)) {
    $nome = $repo.Substring($Pasta.TrimEnd('\').Length).TrimStart('\')
    if (-not $nome) { $nome = Split-Path $repo -Leaf }
    $branchResult = Invoke-Git $repo @('symbolic-ref','--quiet','--short','HEAD')
    $branch = if ($branchResult.Code -eq 0) { $branchResult.Text } else { '(detached HEAD)' }
    $statusResult = Invoke-Git $repo @('status','--porcelain','--untracked-files=normal')
    $temMudancas = ($statusResult.Code -eq 0 -and -not [string]::IsNullOrWhiteSpace($statusResult.Text))
    $headResult = Invoke-Git $repo @('rev-parse','--verify','HEAD')
    $situacao = ''
    $detalhes = ''

    if ($headResult.Code -ne 0) {
        $situacao = 'SEM COMMITS'
        $detalhes = 'Repositorio ainda sem commit inicial'
    } elseif ($statusResult.Code -ne 0) {
        $situacao = 'ERRO STATUS'
        $detalhes = $statusResult.Text
    } else {
        $upResult = Invoke-Git $repo @('rev-parse','--abbrev-ref','--symbolic-full-name','@{upstream}')
        if ($upResult.Code -ne 0 -or -not $upResult.Text) {
            $situacao = 'SEM UPSTREAM'
            $detalhes = 'Branch sem remoto de acompanhamento'
        } else {
            $upstream = $upResult.Text
            $remoteResult = Invoke-Git $repo @('config',"branch.$branch.remote")
            $remoto = if ($remoteResult.Code -eq 0) { $remoteResult.Text } else { '' }
            if (-not $SemFetch -and $remoto -and $remoto -ne '.') {
                $fetchResult = Invoke-Git $repo @('fetch','--quiet',$remoto)
                if ($fetchResult.Code -ne 0) {
                    $situacao = 'ERRO FETCH'
                    $detalhes = 'Falha ao consultar remoto: ' + $fetchResult.Text
                }
            }
            if (-not $situacao) {
                $countsResult = Invoke-Git $repo @('rev-list','--left-right','--count',"HEAD...$upstream")
                $counts = @($countsResult.Text -split '\s+' | Where-Object { $_ })
                if ($countsResult.Code -ne 0 -or $counts.Count -lt 2) {
                    $situacao = 'ERRO COMPARACAO'
                    $detalhes = $countsResult.Text
                } else {
                    $ahead = [int]$counts[0]
                    $behind = [int]$counts[1]
                    if ($ahead -eq 0 -and $behind -eq 0) { $situacao = 'SINCRONIZADO' }
                    elseif ($ahead -gt 0 -and $behind -gt 0) { $situacao = 'DIVERGENTE' }
                    elseif ($ahead -gt 0) { $situacao = 'ENVIAR' }
                    else { $situacao = 'RECEBER' }
                    $detalhes = "Enviar: $ahead | Receber: $behind"
                }
            }
        }
    }
    if ($temMudancas) {
        if ($situacao -eq 'SINCRONIZADO') { $situacao = 'ALTERACOES LOCAIS' }
        $detalhes += ' | Arquivos modificados/novos'
    }
    [pscustomobject]@{
        Projeto = $nome; Branch = $branch; Situacao = $situacao
        Detalhes = $detalhes.Trim(' ','|'); Caminho = $repo
    }
}
)

if ($resultados.Count -eq 0) { Write-Host 'Nenhum repositorio Git encontrado.'; exit 0 }
$resultados | Format-Table Projeto, Branch, Situacao, Detalhes -AutoSize -Wrap
$saida = Join-Path $Pasta 'relatorio-git.csv'
$resultados | Export-Csv -LiteralPath $saida -NoTypeInformation -Encoding UTF8
Write-Host "`nRelatorio CSV salvo em: $saida" -ForegroundColor Cyan
