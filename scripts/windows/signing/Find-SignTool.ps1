# 4FunCode — shared SignTool discovery (dot-source from other signing scripts).
# Prefers newest x64 signtool.exe, never hardcodes an SDK version.
function Find-SignTool {
    $signTool = Get-ChildItem `
        "C:\Program Files (x86)\Windows Kits\10\bin" `
        -Filter signtool.exe `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if (-not $signTool) {
        throw "signtool.exe (x64) not found. Install Windows SDK."
    }

    return $signTool.FullName
}
