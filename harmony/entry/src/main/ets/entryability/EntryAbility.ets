import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, window } from '@kit.ArkUI';
import { AppConfig } from '../common/Constants';

const DOMAIN = 0x0000;

interface CardRoomParams {
  roomId: string;
  roomType: string;
  roomName: string;
}

/** 传给房间页的完整参数（ArkTS 不支持交叉类型，单独定义） */
interface RoomLaunchParams {
  roomId: string;
  roomType: string;
  roomName: string;
  name: string;
  host: string;
}

export default class EntryAbility extends UIAbility {
  /** 来自桌面卡片的跳转参数（roomId 存在即有效） */
  private cardJump: CardRoomParams | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'LiveRoom', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    this.readCardJump(want);
    hilog.info(DOMAIN, 'LiveRoom', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用已在前台/后台存活时，点卡片会走这里
    this.readCardJump(want);
    this.openCardRoom();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'LiveRoom', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'LiveRoom', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'LiveRoom', '%{public}s', 'Succeeded in loading the content.');
      // 冷启动时若带卡片参数，直接进对应房间
      this.openCardRoom();
    });
  }

  private readCardJump(want: Want): void {
    try {
      const p: Record<string, Object> | undefined = want.parameters as Record<string, Object>;
      const roomId: Object | undefined = p?.['roomId'];
      if (roomId !== undefined && roomId !== null) {
        this.cardJump = {
          roomId: roomId as string,
          roomType: (p?.['roomType'] as string) ?? 'chat',
          roomName: (p?.['roomName'] as string) ?? '聊天室'
        };
      }
    } catch (err) {
      hilog.warn(DOMAIN, 'LiveRoom', 'readCardJump failed');
    }
  }

  private openCardRoom(): void {
    const jump: CardRoomParams | null = this.cardJump;
    if (jump === null) {
      return;
    }
    this.cardJump = null;
    const params: RoomLaunchParams = {
      roomId: jump.roomId,
      roomType: jump.roomType,
      roomName: jump.roomName,
      name: '访客',
      host: AppConfig.DEFAULT_HOST
    };
    const url: string = jump.roomType === 'board' ? 'pages/BoardRoomPage' : 'pages/ChatRoomPage';
    setTimeout((): void => {
      router.pushUrl({ url: url, params: params as Object }, (err): void => {
        if (err) {
          hilog.warn(DOMAIN, 'LiveRoom', 'card jump failed: %{public}d', err.code);
        }
      });
    }, 120);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'LiveRoom', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'LiveRoom', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'LiveRoom', '%{public}s', 'Ability onBackground');
  }
}
