import { formProvider, formBindingData } from '@kit.FormKit';
import { dataPreferences } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'LiveRoomCardSync';
const PREF_NAME: string = 'liveroom_card';
const KEY_FORM_IDS: string = 'form_ids';
const KEY_SNAPSHOT: string = 'card_snapshot';

export interface CardPayload {
  roomId: string;
  roomType: string;
  roomName: string;
  line1: string;
  line2: string;
  ts: number;
}

function fmtTime(ts: number): string {
  const d: Date = new Date(ts);
  const h: number = d.getHours();
  const m: number = d.getMinutes();
  return (h < 10 ? '0' + h : '' + h) + ':' + (m < 10 ? '0' + m : '' + m);
}

/**
 * 桌面卡片同步器：
 * - App 收到新消息 / 新笔迹时调用 push()，实时刷新所有已添加到桌面的卡片。
 * - 同时把最新快照写进 preferences，供卡片定时刷新兜底（App 被杀后仍能显示最后状态）。
 */
export class CardSync {

  /** 推送一次卡片更新（pixelMap 可选：白板快照图） */
  public static async push(payload: CardPayload, pixelMap?: image.PixelMap): Promise<void> {
    try {
      const ctx: Context = getContext().getApplicationContext();
      const prefs = await dataPreferences.getPreferences(ctx, { name: PREF_NAME });
      await prefs.put(KEY_SNAPSHOT, JSON.stringify(payload));
      await prefs.flush();

      const ids: string[] = await CardSync.loadFormIds(ctx);
      if (ids.length === 0) {
        return;
      }
      const data: formBindingData.FormBindingData = CardSync.buildData(payload, pixelMap);
      for (const id of ids) {
        try {
          await formProvider.updateForm(id, data);
        } catch (err) {
          const e: BusinessError = err as BusinessError;
          hilog.warn(TAG, 'updateForm %{public}s failed: %{public}d', id, e.code);
        }
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(TAG, 'push failed: %{public}d %{public}s', e.code, e.message ?? '');
    }
  }

  /** 供 EntryFormAbility 使用：读取快照构造卡片数据（定时刷新兜底）。ctx 可传入扩展上下文 */
  public static async loadSnapshot(ctxIn?: Context): Promise<Record<string, Object>> {
    const def: Record<string, Object> = {
      'roomId': 'chat-lobby',
      'roomType': 'chat',
      'roomName': '大厅闲聊',
      'line1': '暂无新消息',
      'line2': '点击进入 LiveRoom',
      'time': '',
      'imgKey': ''
    };
    try {
      const ctx: Context = ctxIn !== undefined ? ctxIn : getContext().getApplicationContext();
      const prefs = await dataPreferences.getPreferences(ctx, { name: PREF_NAME });
      const raw: string = (await prefs.get(KEY_SNAPSHOT, '')) as string;
      if (raw.length === 0) {
        return def;
      }
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      def['roomId'] = parsed['roomId'] ?? 'chat-lobby';
      def['roomType'] = parsed['roomType'] ?? 'chat';
      def['roomName'] = parsed['roomName'] ?? '大厅闲聊';
      def['line1'] = parsed['line1'] ?? '';
      def['line2'] = parsed['line2'] ?? '';
      def['time'] = parsed['ts'] !== undefined ? fmtTime(parsed['ts'] as number) : '';
    } catch (err) {
      // 保持默认值
    }
    return def;
  }

  public static async addFormId(ctx: Context, formId: string): Promise<void> {
    const ids: string[] = await CardSync.loadFormIds(ctx);
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      await CardSync.saveFormIds(ctx, ids);
    }
  }

  public static async removeFormId(ctx: Context, formId: string): Promise<void> {
    const ids: string[] = await CardSync.loadFormIds(ctx);
    const idx: number = ids.indexOf(formId);
    if (idx >= 0) {
      ids.splice(idx, 1);
      await CardSync.saveFormIds(ctx, ids);
    }
  }

  private static async loadFormIds(ctx: Context): Promise<string[]> {
    try {
      const prefs = await dataPreferences.getPreferences(ctx, { name: PREF_NAME });
      const raw: string = (await prefs.get(KEY_FORM_IDS, '')) as string;
      return raw.split(',').filter((s: string): boolean => s.length > 0);
    } catch (err) {
      return [];
    }
  }

  private static async saveFormIds(ctx: Context, ids: string[]): Promise<void> {
    try {
      const prefs = await dataPreferences.getPreferences(ctx, { name: PREF_NAME });
      await prefs.put(KEY_FORM_IDS, ids.join(','));
      await prefs.flush();
    } catch (err) {
      // 忽略
    }
  }

  private static buildData(payload: CardPayload, pixelMap?: image.PixelMap): formBindingData.FormBindingData {
    const obj: Record<string, Object> = {
      'roomId': payload.roomId,
      'roomType': payload.roomType,
      'roomName': payload.roomName,
      'line1': payload.line1,
      'line2': payload.line2,
      'time': fmtTime(payload.ts),
      'imgKey': ''
    };
    if (pixelMap !== undefined) {
      // 每次用新的 imageKey，确保卡片上的 Image 刷新
      const imgKey: string = 'board' + Date.now().toString();
      obj['imgKey'] = imgKey;
      const images: Record<string, image.PixelMap> = {};
      images[imgKey] = pixelMap;
      obj['formImages'] = images;
    }
    return formBindingData.createFormBindingData(obj);
  }
}
