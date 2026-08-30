# Push to Talk por mouse no Linux

O atalho global por teclado usa o portal do desktop. Para ler botões de mouse
em segundo plano no Wayland, o cliente abre somente dispositivos classificados
como `ID_INPUT_MOUSE=1`. Isso requer uma regra `udev` e associação explícita
ao grupo dedicado `fourfun-ptt`.

Instale manualmente, após revisar os arquivos:

```sh
sudo ./install-input-access.sh "$USER"
```

Em seguida, encerre a sessão gráfica e entre novamente. A regra não concede
acesso a dispositivos de teclado, mas membros do grupo podem observar todos os
eventos dos mouses conectados.
