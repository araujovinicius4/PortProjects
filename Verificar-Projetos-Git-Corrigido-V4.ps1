param(
  [string]$Pasta = 'C:\Users\sebastiao.moura\Documents\1Portifolio',
  [switch]$SemFetch,
  [switch]$SomenteProblemas
)

$ErrorActionPreference = 'Stop'

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 > $null

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

  foreach ($child in (
      Get-ChildItem `
        -LiteralPath $dir `
        -Directory `
        -Force `
        -ErrorAction SilentlyContinue
    )) {

    if ($child.Name -in @(
        'node_modules',
        '.venv',
        'venv',
        'dist',
        'build',
        '.git'
      )) {
      continue
    }

    if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      continue
    }

    $dirs.Push($child.FullName)
  }
}

$resultados = @()

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
  (
    $statusResult.Code -eq 0 -and
    -not [string]::IsNullOrWhiteSpace($statusResult.Text)
  )

  $qtdArquivosAlterados = 0

  if ($statusResult.Code -eq 0 -and $statusResult.Text) {

    $qtdArquivosAlterados =
    ($statusResult.Text -split "`n" |
      Where-Object { $_.Trim() }).Count
  }

  $headResult = Invoke-Git $repo @(
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

      $remoteResult = Invoke-Git $repo @(
        'config',
        "branch.$branch.remote"
      )

      $remoto = if ($remoteResult.Code -eq 0) {
        $remoteResult.Text
      }
      else {
        ''
      }

      if (-not $SemFetch -and
        $remoto -and
        $remoto -ne '.') {

        $fetchResult = Invoke-Git $repo @(
          'fetch',
          '--quiet',
          $remoto
        )

        if ($fetchResult.Code -ne 0) {

          $situacao = 'ERRO FETCH'
          $detalhes = 'Falha ao consultar remoto'
        }
      }

      if (-not $situacao) {

        $countsResult = Invoke-Git $repo @(
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

    $detalhes +=
    " | Arquivos alterados: $qtdArquivosAlterados"
  }

  $autor = ''
  $dataCommit = ''
  $mensagemCommit = ''

  if ($headResult.Code -eq 0) {

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
        '--date=format:%Y-%m-%d %H:%M:%S',
        '--pretty=%cd'
      )).Text
    $mensagemCommit =
    (Invoke-Git $repo @(
        'log',
        '-1',
        '--pretty=%s'
      )).Text
  }

  $remoteUrl = ''

  $remoteResult =
  Invoke-Git $repo @(
    'remote',
    'get-url',
    'origin'
  )

  if ($remoteResult.Code -eq 0) {
    $remoteUrl = $remoteResult.Text
  }

  $diasSemAtividade = $null

  if (-not [string]::IsNullOrWhiteSpace($dataCommit)) {

    try {

      $diasSemAtividade =
      [math]::Floor(
        ((Get-Date) -
          ([datetime]$dataCommit)).TotalDays
      )
    }
    catch {

      $diasSemAtividade = $null
    }
  }

  $abandonado =
  if (
    $diasSemAtividade -ne $null -and
    $diasSemAtividade -ge 180
  ) {
    'SIM'
  }
  else {
    'NAO'
  }

  $branchPrincipal =
  if ($branch -in @('main','master')) {
    'SIM'
  }
  else {
    'NAO'
  }

  $resultados += [pscustomobject]@{

    Projeto = $nome
    Branch = $branch
    BranchPrincipal = $branchPrincipal

    Situacao = $situacao
    Detalhes = $detalhes.Trim(' ','|')

    ArquivosAlterados = $qtdArquivosAlterados

    Autor = $autor
    DataUltimoCommit = $dataCommit

    DiasSemAtividade = $diasSemAtividade
    Abandonado = $abandonado

    UltimoCommit = $mensagemCommit

    Remoto = $remoteUrl

    Caminho = $repo
  }
}

if ($SomenteProblemas) {

  $resultados = $resultados |
    Where-Object {

    $_.Situacao -ne 'SINCRONIZADO'

  }
}

if ($resultados.Count -eq 0) {

  if ($SomenteProblemas) {

    Write-Host ''
    Write-Host 'Nenhum projeto com problemas encontrado.' -ForegroundColor Green
  }
  else {

    Write-Host 'Nenhum repositório Git encontrado.'
  }

  exit
}
$total = $resultados.Count

$saudaveis = (
  $resultados |
    Where-Object {

    $_.Situacao -in @(
      'SINCRONIZADO',
      'ALTERACOES LOCAIS'
    )

  }
).Count

if ($total -gt 0) {

  $indiceSaude =
  [math]::Round(
    (($saudaveis / $total) * 100),
    0
  )
}
else {

  $indiceSaude = 0
}
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " RESUMO GERAL" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total de Projetos : $total"

$resultados |
  Group-Object Situacao |
  Sort-Object Name |
  ForEach-Object {

  Write-Host (
    "{0,-25} {1,5}" -f
    $_.Name,
    $_.Count
  )
}

Write-Host ""
Write-Host (
  [char]0x00CD +
  "ndice de Sa" +
  [char]0x00FA +
  "de: $indiceSaude %"
)
Write-Host ""

$resultados |
  Sort-Object Situacao, Projeto |
  Format-Table `
  Projeto,
Branch,
Situacao,
DataUltimoCommit,
ArquivosAlterados,
DiasSemAtividade,
Abandonado `
  -AutoSize

$csv = Join-Path $Pasta 'relatorio-git.csv'

$resultados |
  Export-Csv `
  -NoTypeInformation `
  -Encoding UTF8 `
  -LiteralPath $csv

$json = Join-Path $Pasta 'relatorio-git.json'

$jsonData = [pscustomobject]@{

  DataExecucao = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

  TotalProjetos = $total

  IndiceSaude = $indiceSaude

  Projetos = $resultados
}

$jsonData |
  ConvertTo-Json -Depth 10 |
  Set-Content `
  -Encoding UTF8 `
  -Path $json

$historicoPath = Join-Path $Pasta 'historico-git.json'

$novaEntrada = [pscustomobject]@{

  DataExecucao = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

  TotalProjetos = $total

  IndiceSaude = $indiceSaude
}

$historico = @()

if (Test-Path $historicoPath) {

  try {

    $historico = Get-Content `
      $historicoPath `
      -Raw |
      ConvertFrom-Json

    if ($historico -isnot [System.Array]) {
      $historico = @($historico)
    }
  }
  catch {

    $historico = @()
  }
}

$historico += $novaEntrada

$historico |
  ConvertTo-Json -Depth 5 |
  Set-Content `
  -Encoding UTF8 `
  -Path $historicoPath

$css = @"
<meta charset="utf-8">
<style>
body{
font-family:Segoe UI;
margin:20px;
background:#f8fafc;
}

h1{
color:#1e293b;
}

table{
border-collapse:collapse;
width:100%;
}

th{
background:#1e293b;
color:white;
padding:10px;
text-align:left;
}

td{
padding:8px;
border-bottom:1px solid #dddddd;
}

tr:nth-child(even){
background:#f7f7f7;
}

tr:hover{
background:#e5e7eb;
}
</style>
"@

$html = Join-Path $Pasta 'relatorio-git.html'

$cabecalhoHtml = @"
<h1>Relat&oacute;rio Git V3</h1>

<p>
<b>Data de Execu&ccedil;&atilde;o:</b> $(Get-Date)
<br>
<b>Total de Projetos:</b> $total
<br>
<b>&Iacute;ndice de Sa&uacute;de:</b> $indiceSaude %
</p>
"@

$tabelaHtml =
$resultados |
  Select-Object `
  Projeto,
Branch,
Situacao,
ArquivosAlterados,
Autor,
DataUltimoCommit,
DiasSemAtividade,
Abandonado,
UltimoCommit,
Remoto |
  ConvertTo-Html -Fragment

$htmlContent =
ConvertTo-Html `
  -Title 'Relatório Git V3' `
  -Head $css `
  -Body ($cabecalhoHtml + $tabelaHtml)

[System.IO.File]::WriteAllText(
  $html,
  $htmlContent,
  [System.Text.UTF8Encoding]::new($true)
)

Write-Host ""
Write-Host "CSV  : $csv" -ForegroundColor Green
Write-Host "JSON : $json" -ForegroundColor Green
Write-Host "HTML : $html" -ForegroundColor Green

Write-Host ""
Write-Host "TOP 5 MAIS RECENTES"
Write-Host "-------------------"

$resultados |
  Sort-Object DiasSemAtividade |
  Select-Object -First 5 |
  ForEach-Object {

  Write-Host (
    "{0,-35} {1,5} dias" -f
    $_.Projeto,
    $_.DiasSemAtividade
  )
}

Write-Host ""
Write-Host "TOP 5 MAIS ANTIGOS"
Write-Host "------------------"

$resultados |
  Sort-Object DiasSemAtividade -Descending |
  Select-Object -First 5 |
  ForEach-Object {

  Write-Host (
    "{0,-35} {1,5} dias" -f
    $_.Projeto,
    $_.DiasSemAtividade
  )
}

if (Test-Path $html) {

  try {
    Start-Process $html
  }
  catch {
    Write-Warning "Não foi possível abrir o HTML automaticamente."
  }
}
