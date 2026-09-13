# Push to Talk global no Linux

O atalho global por teclado tenta, nesta ordem:

1. `org.gnome.Shell.GrabAccelerator` em sessoes GNOME.
2. Leitura evdev de dispositivos `ID_INPUT_KEYBOARD=1`.
3. Portal `org.freedesktop.portal.GlobalShortcuts` como fallback.

Atalhos so de modificadores, como `Ctrl` ou `Ctrl + Alt`, dependem do caminho
evdev. Botoes de mouse em segundo plano tambem usam evdev, lendo dispositivos
`ID_INPUT_MOUSE=1`.

O acesso evdev exige uma regra `udev` e associacao explicita ao grupo dedicado
`fourfun-ptt`.

Instale manualmente, após revisar os arquivos:

```sh
sudo ./install-input-access.sh "$USER"
```

Em seguida, encerre a sessao grafica e entre novamente. A regra concede leitura
bruta aos dispositivos de teclado/mouse para membros do grupo, portanto deve ser
instalada apenas na maquina de desenvolvimento/uso confiavel.
