# 4FunCode client

Cliente Flutter desktop para Linux e Windows.

Web não é target suportado. O diretório `web/` pode permanecer no projeto por
histórico e por assets compartilhados (por exemplo, favicon usado no tray), mas
não deve ser usado para build, QA ou release.

## Desktop

No Linux e no Windows, fechar a janela envia o aplicativo para o system tray.
O menu da bandeja permite reabrir a janela ou encerrar o processo de verdade.
Se o Linux não oferecer um host de tray acessível, o fechamento normal é
mantido para evitar deixar o processo invisível sem forma de recuperação.

Para compilar no Debian/Ubuntu, instale uma implementação AppIndicator:

```bash
sudo apt-get install libayatana-appindicator3-dev
```

Também é possível usar `libappindicator3-dev`. No GNOME, a extensão
AppIndicator/KStatusNotifierItem precisa estar habilitada para exibir o ícone.
