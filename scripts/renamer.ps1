$projectDir = "E:\PortableApps\ahk\scripts\v2\ahk_v2_vimd"
$scriptDir = "$projectDir\scripts"
$configFile = "$scriptDir\rename-regexs.txt"

# 读取配置文件
$replacements = Get-Content $configFile | Where-Object { $_ -notmatch "^//" } | ForEach-Object {
    $parts = $_ -split "="
    if ($parts.Length -eq 2) {
        [PSCustomObject]@{
            Original = $parts[0].Trim()
            New = $parts[1].Trim()
        }
    }
}

# 对每个替换项执行替换
foreach ($item in $replacements) {
    Write-Host "替换: $($item.Original) => $($item.New)"


}

Write-Host "替换完成！"