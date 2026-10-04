# Smoke Windows: janela minimizada e retomada

Execute no desktop Windows interativo, com Flutter e dependências do build
nativo já configurados. O diretório de evidências deve ser novo em cada
execução. Este target é de diagnóstico: não publique seu bundle como o app.

Na raiz do cliente, em PowerShell:

```powershell
flutter build windows --release --no-pub -t tooling-woodpecker/smoke_windows_window_share.dart --dart-define=SMOKE_DIR=C:\Temp\4fun-window-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File tooling-woodpecker\smoke-windows-window-share.ps1 -SmokeDirectory C:\Temp\4fun-window-smoke -Binary "$PWD\build\windows\x64\runner\Release\_4fun_cod_client.exe"
Get-Content C:\Temp\4fun-window-smoke\status.json
```

A opção de política acima afeta apenas o processo do helper, não a
configuração permanente do Windows. O helper abre uma janela com contador,
minimiza antes da enumeração, restaura/foca ao detectar espera e repete
minimização/restauração depois que a captura inicia. Fecha a janela ao final.

O harness verifica inclusão na lista, identidade por PID, início após foco,
snapshots não vazios/diferentes e frames decodificados por um segundo peer
WebRTC local, usando a mesma track. Cria `status.json`, `before.png`,
`after.png` e marcadores locais. `stage=passed` confirma o cenário completo;
o código de saída do helper sozinho não prova aprovação do harness.

`captureFrame` pode encontrar a track local quando IDs local/remoto são
iguais; por isso os snapshots validam a fonte, e stats do receptor validam
independentemente a recepção/decodificação. O teste não requer login, não
envia telemetria e não comprova áudio, sala LiveKit ou fullscreen exclusivo.

Depois do diagnóstico, reconstrua o target normal antes de distribuir:

```powershell
flutter build windows --release --no-pub
```
