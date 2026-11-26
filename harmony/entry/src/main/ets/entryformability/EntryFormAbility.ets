import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSync } from '../service/CardSync';

const TAG: string = 'LiveRoomForm';

export default class EntryFormAbility extends FormExtensionAbility {

  /** 卡片首次添加到桌面 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    try {
      const raw: Object | undefined = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
      const formId: string = raw !== undefined && raw !== null ? raw as string : '';
      if (formId.length > 0) {
        CardSync.addFormId(this.context.getApplicationContext(), formId);
        hilog.info(0, TAG, 'form added: %{public}s', formId);
        this.refreshLater(formId);
      }
    } catch (err) {
      hilog.warn(0, TAG, 'onAddForm save id failed');
    }
    // 用最后一次快照初始化（异步读 preferences，这里直接给默认值，
    // 紧接着的 onUpdateForm / 定时刷新会把真实快照补上）
    const def: Record<string, Object> = {
      'roomId': 'chat-lobby',
      'roomType': 'chat',
      'roomName': '大厅闲聊',
      'line1': '暂无新消息',
      'line2': '点击进入 LiveRoom',
      'time': '',
      'imgKey': ''
    };
    return formBindingData.createFormBindingData(def);
  }

  /** 异步补一次快照刷新，让新卡片立刻显示最近状态 */
  private refreshLater(formId: string): void {
    CardSync.loadSnapshot(this.context.getApplicationContext())
      .then(async (snap: Record<string, Object>): Promise<void> => {
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(snap));
      })
      .catch((): void => {
        hilog.warn(0, TAG, 'refreshLater failed');
      });
  }

  /** 系统定时刷新 / 手动刷新 */
  async onUpdateForm(formId: string): Promise<void> {
    try {
      const snap: Record<string, Object> = await CardSync.loadSnapshot(this.context.getApplicationContext());
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(snap));
    } catch (err) {
      hilog.warn(0, TAG, 'onUpdateForm failed: %{public}s', formId);
    }
  }

  /** 卡片从桌面移除 */
  async onRemoveForm(formId: string): Promise<void> {
    try {
      await CardSync.removeFormId(this.context.getApplicationContext(), formId);
    } catch (err) {
      hilog.warn(0, TAG, 'onRemoveForm failed');
    }
  }
}
