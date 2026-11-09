param(
    [string]$Pasta = "C:\Users\sebastiao.moura\Documents\1Portifolio"
)

$resultados = @()

$repos = Get-ChildItem -Path $Pasta -Directory -Recurse |
    Where-Object { Test-Path (Join-Path $_.FullName ".git") }

foreach ($repo in $repos) {

    $gitignore = Test-Path (Join-Path $repo.FullName ".gitignore")

    $nodeModulesRastreado = $false

    Push-Location $repo.FullName

    try {
        $qtd = @(git ls-files node_modules 2>$null).Count

        if ($qtd -gt 0) {
            $nodeModulesRastreado = $true
        }
    }
    finally {
        Pop-Location
    }

    $resultados += [PSCustomObject]@{
        Projeto          = $repo.Name
        GitIgnore        = $gitignore
        NodeModulesNoGit = -not $nodeModulesRastreado
    }
}

$resultados |
    Sort-Object Projeto |
    Format-Table -AutoSize