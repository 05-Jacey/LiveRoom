import { router } from '@kit.ArkUI';
import { AppConfig } from '../common/Constants';
import { RoomClient } from '../service/RoomClient';
import { ChatItem, MemberInfo, ServerEnvelope } from '../model/Protocol';
import { CardSync } from '../service/CardSync';

interface RoomParams {
  roomId: string;
  roomName: string;
  host: string;
  name: string;
}

@Entry
@Component
struct ChatRoomPage {
  @State roomName: string = '聊天室';
  @State status: string = '连接中…';
  @State memberText: string = '';
  @State input: string = '';
  @State messages: ChatItem[] = [];

  private roomId: string = 'chat-lobby';
  private host: string = AppConfig.DEFAULT_HOST;
  private name: string = '访客';
  private selfId: string = '';
  private joinedOnce: boolean = false;
  private client: RoomClient = new RoomClient();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const raw: Object = router.getParams();
    const p: RoomParams = raw ? (raw as RoomParams) : {
      roomId: 'chat-lobby', roomName: '聊天室', host: AppConfig.DEFAULT_HOST, name: '访客'
    };
    this.roomId = p.roomId;
    this.roomName = p.roomName;
    this.host = p.host;
    this.name = p.name || '访客';

    this.client.onMessage = (data: string): void => {
      this.onServerMessage(data);
    };
    this.client.onState = (state: string): void => {
      this.status = state;
      if (state === '已连接' && !this.joinedOnce) {
        this.joinedOnce = true;
        this.client.join(this.roomId, this.name);
      }
    };
    this.client.connect(AppConfig.wsUrl(this.host));
  }

  aboutToDisappear(): void {
    this.client.disconnect();
  }

  private onServerMessage(data: string): void {
    const msg: ServerEnvelope = JSON.parse(data) as ServerEnvelope;
    const type: string = msg.type ?? '';
    switch (type) {
      case 'joined':
        this.selfId = msg.clientId ?? '';
        this.messages = msg.history ?? [];
        this.applyMembers(msg.members ?? []);
        this.scrollBottom();
        break;
      case 'chat': {
        const item: ChatItem = {
          kind: 'chat',
          id: msg.id ?? '',
          fromId: msg.fromId ?? '',
          fromName: msg.fromName ?? '',
          color: msg.color ?? '#8A8F99',
          text: msg.text ?? '',
          ts: msg.ts ?? Date.now()
        };
        this.messages = this.messages.concat([item]);
        this.scrollBottom();
        CardSync.push({
          roomId: this.roomId, roomType: 'chat', roomName: this.roomName,
          line1: (item.fromName.length > 0 ? item.fromName : '系统') + '：' + item.text,
          line2: this.memberText.length > 0 ? this.memberText : '点击进入聊天',
          ts: item.ts
        }, undefined, getContext(this).getApplicationContext());
        break;
      }
      case 'system': {
        const item: ChatItem = {
          kind: 'system', id: '', fromId: '', fromName: '', color: '',
          text: msg.text ?? '', ts: msg.ts ?? Date.now()
        };
        this.messages = this.messages.concat([item]);
        this.scrollBottom();
        break;
      }
      case 'members':
        this.applyMembers(msg.members ?? []);
        break;
      case 'error': {
        const item: ChatItem = {
          kind: 'system', id: '', fromId: '', fromName: '', color: '',
          text: '提示：' + (msg.message ?? ''), ts: Date.now()
        };
        this.messages = this.messages.concat([item]);
        break;
      }
      default:
        break;
    }
  }

  private applyMembers(list: MemberInfo[]): void {
    const names: string[] = [];
    for (const m of list) {
      names.push(m.name);
    }
    this.memberText = '在线 ' + list.length + ' 人：' + names.join('、');
  }

  private scrollBottom(): void {
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 60);
  }

  private formatTime(ts: number): string {
    const d: Date = new Date(ts);
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    return (h < 10 ? '0' + h : '' + h) + ':' + (m < 10 ? '0' + m : '' + m);
  }

  /** ① 接服务器：进入页面时自动连；这里供关闭后手动重连 */
  private connectServer(): void {
    if (this.status === '已连接') {
      return;
    }
    this.joinedOnce = false;
    this.client.connect(AppConfig.wsUrl(this.host));
  }

  /** ③ 关闭服务器：断开 WebSocket 连接，保留页面方便截图 */
  private closeServer(): void {
    this.client.disconnect();
    this.status = '已断开';
  }

  /** ② 发送消息 */
  private send(): void {
    const text: string = this.input.trim();
    if (text.length === 0 || this.status !== '已连接') {
      return;
    }
    this.client.sendChat(text);
    this.input = '';
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹ 返回')
          .fontSize(14)
          .fontColor('#4F7DF3')
          .onClick((): void => {
            router.back();
          });
        Text(this.roomName)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2329');
        Blank();
        Text(this.status)
          .fontSize(12)
          .fontColor(this.status === '已连接' ? '#2E8B57' : '#C0563B');
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })
      .backgroundColor('#FFFFFF');

      Text(this.memberText)
        .fontSize(12)
        .fontColor('#8A8F99')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 10 })
        .backgroundColor('#FFFFFF');

      Row({ space: 8 }) {
        Button('连接服务器')
          .fontSize(12)
          .height(32)
          .backgroundColor('#4F7DF3')
          .fontColor('#FFFFFF')
          .enabled(this.status !== '已连接')
          .onClick((): void => {
            this.connectServer();
          });
        Button('关闭服务器')
          .fontSize(12)
          .height(32)
          .backgroundColor('#C0563B')
          .fontColor('#FFFFFF')
          .enabled(this.status === '已连接')
          .onClick((): void => {
            this.closeServer();
          });
        Blank();
        Text('关闭＝断开连接')
          .fontSize(11)
          .fontColor('#9A9FA8');
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })
      .backgroundColor('#FFFFFF');

      Scroll(this.scroller) {
        Column({ space: 10 }) {
          ForEach(this.messages, (item: ChatItem) => {
            if (item.kind === 'system') {
              Text(item.text)
                .fontSize(12)
                .fontColor('#A0A5AE')
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 4, bottom: 4 });
            } else {
              Column({ space: 4 }) {
                Text(item.fromName + '  ' + this.formatTime(item.ts))
                  .fontSize(11)
                  .fontColor('#9A9FA8');
                Text(item.text)
                  .fontSize(14)
                  .fontColor(item.fromId === this.selfId ? '#FFFFFF' : '#1F2329')
                  .backgroundColor(item.fromId === this.selfId ? '#4F7DF3' : '#FFFFFF')
                  .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                  .borderRadius(12)
                  .constraintSize({ maxWidth: 280 });
              }
              .width('100%')
              .alignItems(item.fromId === this.selfId ? HorizontalAlign.End : HorizontalAlign.Start);
            }
          }, (item: ChatItem, index: number) => item.id + '_' + index);
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 });
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F5F6F8');

      Row({ space: 10 }) {
        TextInput({ text: this.input, placeholder: '说点什么…' })
          .layoutWeight(1)
          .height(44)
          .onChange((value: string): void => {
            this.input = value;
          })
          .onSubmit((): void => {
            this.send();
          });
        Button('发送')
          .height(44)
          .enabled(this.status === '已连接')
          .onClick((): void => {
            this.send();
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 18 })
      .backgroundColor('#FFFFFF');
    }
    .width('100%')
    .height('100%');
  }
}
