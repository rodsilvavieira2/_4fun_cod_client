import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Wrapper centralizado da identidade de ícones do app (Hugeicons stroke-rounded).
///
/// Único arquivo que importa `package:hugeicons` diretamente. Todo o resto do
/// app usa [AppIcon]/[AppIcons] para não acoplar 40+ arquivos à lib.
///
/// Convenções:
/// - `size` padrão 16 (bate com o antigo `Icons.*` a 14–18px).
/// - `strokeWidth` padrão 1.8 (1.5 em 12–14px, 2.0 em 18px+).
/// - `color` nulo herda do `IconTheme`/`DefaultTextStyle` via HugeIcon.color=null.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 16,
    this.color,
    this.strokeWidth = 1.8,
  });

  final List<List<dynamic>> icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return HugeIcon(
      icon: icon,
      size: size,
      color: color,
      strokeWidth: strokeWidth,
    );
  }
}

/// Catálogo semântico: cada entrada mapeia um conceito do app para um
/// `HugeIcons.strokeRounded*` verificado no hugeicons 1.2.0.
///
/// Substitui os antigos `Icons.*` do Material. Ex.:
/// `Icons.tag` (canal texto) -> [AppIcons.channelText]
class AppIcons {
  AppIcons._();

  // Navegação / estrutura
  static const channelText = HugeIcons.strokeRoundedHashtag;
  static const channelVoice = HugeIcons.strokeRoundedVolumeHigh;
  static const server = HugeIcons.strokeRoundedServer;
  static const computer = HugeIcons.strokeRoundedComputer;
  static const monitor = HugeIcons.strokeRoundedMonitor;
  static const browser = HugeIcons.strokeRoundedBrowser;
  static const grid = HugeIcons.strokeRoundedGridView;
  static const forum = HugeIcons.strokeRoundedMessage01;
  static const theater = HugeIcons.strokeRoundedTheater;

  // Ações genéricas
  static const add = HugeIcons.strokeRoundedAdd01;
  static const addCircle = HugeIcons.strokeRoundedAddCircle;
  static const remove = HugeIcons.strokeRoundedRemove01;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const check = HugeIcons.strokeRoundedTick01;
  static const checkCircle = HugeIcons.strokeRoundedCheckmarkCircle01;
  static const info = HugeIcons.strokeRoundedInformationCircle;
  static const warning = HugeIcons.strokeRoundedAlertCircle;
  static const error = HugeIcons.strokeRoundedCancelCircle;
  static const search = HugeIcons.strokeRoundedSearch01;
  static const refresh = HugeIcons.strokeRoundedRefresh;
  static const reload = HugeIcons.strokeRoundedReload;
  static const rotate = HugeIcons.strokeRoundedRotateCcw;
  static const sync = HugeIcons.strokeRoundedRefresh;
  static const edit = HugeIcons.strokeRoundedEdit01;
  static const delete = HugeIcons.strokeRoundedDelete02;
  static const trash = HugeIcons.strokeRoundedTrash;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const download = HugeIcons.strokeRoundedDownload01;
  static const cloudDownload = HugeIcons.strokeRoundedCloudDownload;
  static const fileDownload = HugeIcons.strokeRoundedFileDownload;
  static const link = HugeIcons.strokeRoundedLink01;
  static const unlink = HugeIcons.strokeRoundedUnlink01;
  static const external = HugeIcons.strokeRoundedExternalLink;
  static const share = HugeIcons.strokeRoundedShare01;
  static const send = HugeIcons.strokeRoundedArrowUp01;
  static const reply = HugeIcons.strokeRoundedReply;
  static const more = HugeIcons.strokeRoundedMoreHorizontal;
  static const back = HugeIcons.strokeRoundedArrowLeft01;
  static const chevronUp = HugeIcons.strokeRoundedChevronUp;
  static const chevronDown = HugeIcons.strokeRoundedChevronDown;
  static const chevronLeft = HugeIcons.strokeRoundedChevronLeft;
  static const chevronRight = HugeIcons.strokeRoundedChevronRight;
  static const expand = HugeIcons.strokeRoundedMaximize01;
  static const expandDiagonal = HugeIcons.strokeRoundedArrowExpandDiagonal01;
  static const shrink = HugeIcons.strokeRoundedShrink;
  static const fullscreen = HugeIcons.strokeRoundedFullscreen;
  static const fullscreenExit = HugeIcons.strokeRoundedMinimize;
  static const zoomIn = HugeIcons.strokeRoundedZoomIn;
  static const zoomOut = HugeIcons.strokeRoundedZoomOut;
  static const attachment = HugeIcons.strokeRoundedAttachment01;
  static const image = HugeIcons.strokeRoundedImage01;
  static const imageMissing = HugeIcons.strokeRoundedImageNotFound01;
  static const play = HugeIcons.strokeRoundedPlay;
  static const pause = HugeIcons.strokeRoundedPause;
  static const pin = HugeIcons.strokeRoundedPin02;
  static const pinOff = HugeIcons.strokeRoundedPinOff;

  // Voz / vídeo / mídia
  static const mic = HugeIcons.strokeRoundedMic01;
  static const micOff = HugeIcons.strokeRoundedMicOff01;
  static const video = HugeIcons.strokeRoundedVideo01;
  static const videoOff = HugeIcons.strokeRoundedVideoOff;
  static const camera = HugeIcons.strokeRoundedCamera01;
  static const cameraOff = HugeIcons.strokeRoundedCameraOff01;
  static const headset = HugeIcons.strokeRoundedHeadset;
  static const headsetOff = HugeIcons.strokeRoundedHeadsetOff;
  static const volumeHigh = HugeIcons.strokeRoundedVolumeHigh;
  static const volumeLow = HugeIcons.strokeRoundedVolumeLow;
  static const volumeMute = HugeIcons.strokeRoundedVolumeMute01;
  static const volumeOff = HugeIcons.strokeRoundedVolumeOff;
  static const speaker = HugeIcons.strokeRoundedSpeaker;
  static const wave = HugeIcons.strokeRoundedAudioWave01;
  static const activity = HugeIcons.strokeRoundedActivity01;
  static const voice = HugeIcons.strokeRoundedVoice;
  static const sparkles = HugeIcons.strokeRoundedSparkles;
  static const record = HugeIcons.strokeRoundedRecord;
  static const recordDot = HugeIcons.strokeRoundedCircle;
  static const keyboard = HugeIcons.strokeRoundedKeyboard;
  static const timer = HugeIcons.strokeRoundedTimer01;
  static const clock = HugeIcons.strokeRoundedClock01;
  static const call = HugeIcons.strokeRoundedCall02;
  static const callEnd = HugeIcons.strokeRoundedCallEnd01;
  static const screenShare = HugeIcons.strokeRoundedScreenShare;
  static const view = HugeIcons.strokeRoundedView;
  static const viewOff = HugeIcons.strokeRoundedViewOff;
  static const spoiler = HugeIcons.strokeRoundedView;
  static const spoilerOff = HugeIcons.strokeRoundedViewOff;
  static const wifi = HugeIcons.strokeRoundedWifi01;

  // Chat / social
  static const chat = HugeIcons.strokeRoundedBubbleChat;
  static const messageAdd = HugeIcons.strokeRoundedMessageAdd01;
  static const mention = HugeIcons.strokeRoundedAtSign;
  static const emoji = HugeIcons.strokeRoundedSmile;
  static const gif = HugeIcons.strokeRoundedGif01;
  static const mail = HugeIcons.strokeRoundedMail01;
  static const music = HugeIcons.strokeRoundedMusicNote01;
  static const dot = HugeIcons.strokeRoundedDot;

  // Conta / servidor / settings
  static const user = HugeIcons.strokeRoundedUser;
  static const userCircle = HugeIcons.strokeRoundedUserCircle;
  static const userAdd = HugeIcons.strokeRoundedUserAdd01;
  static const userRemove = HugeIcons.strokeRoundedUserRemove01;
  static const userGroup = HugeIcons.strokeRoundedUserGroup;
  static const users = HugeIcons.strokeRoundedUsers;
  static const userSettings = HugeIcons.strokeRoundedUserSettings01;
  static const addTeam = HugeIcons.strokeRoundedAddTeam;
  static const crown = HugeIcons.strokeRoundedCrown;
  static const shield = HugeIcons.strokeRoundedShield01;
  static const lock = HugeIcons.strokeRoundedLock;
  static const lockKey = HugeIcons.strokeRoundedLockKey;
  static const settings = HugeIcons.strokeRoundedSettings01;
  static const logout = HugeIcons.strokeRoundedLogout01;
  static const notifications = HugeIcons.strokeRoundedNotification01;
  static const palette = HugeIcons.strokeRoundedPalette;
  static const moon = HugeIcons.strokeRoundedMoon01;
  static const systemUpdate = HugeIcons.strokeRoundedSystemUpdate01;
  static const package = HugeIcons.strokeRoundedPackage;
}
