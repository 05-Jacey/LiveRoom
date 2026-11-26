import { router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { AppConfig } from '../common/Constants';
import { RoomClient } from '../service/RoomClient';
import { CardSync } from '../service/CardSync';
import {
  Point, MemberInfo, StrokeInfo, ServerEnvelope
} from '../model/Protocol';

interface RoomParams {
  roomId: string;
  roomName: string;
  host: string;
  name: string;
}

@Entry
@Component
struct BoardRoomPage {
  @State roomName: string = '协作白板';
  @State status: string = '连接中…';
  @State memberText: string = '';
  @State color: string = '#1F2329';
  @State lineWidth: number = 4;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private client: RoomClient = new RoomClient();
  private strokes: StrokeInfo[] = [];
  private current: StrokeInfo | null = null;
  private lastSent: Point = { x: 0, y: 0 };
  private canvasW: number = 0;
  private canvasH: number = 0;
  private selfId: string = '';
  private roomId: string = 'board-canvas';
  private host: string = AppConfig.DEFAULT_HOST;
  private name: string = '访客';
  private joinedOnce: boolean = false;
  private colors: string[] = ['#1F2329', '#4F7DF3', '#E8794B', '#2E9E7B', '#9B6BDB', '#D9538A'];
  private widths: number[] = [2, 4, 8];

  aboutToAppear(): void {
    const raw: Object = router.getParams();
    const p: RoomParams = raw ? (raw as RoomParams) : {
      roomId: 'board-canvas', roomName: '协作白板', host: AppConfig.DEFAULT_HOST, name: '访客'
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
        this.strokes = msg.strokes ?? [];
        this.applyMembers(msg.members ?? []);
        this.redraw();
        break;
      case 'members':
        this.applyMembers(msg.members ?? []);
        break;
      case 'stroke_start': {
        const p: Point = msg.point ?? { x: 0, y: 0 };
        const s: StrokeInfo = {
          id: msg.id ?? '', color: msg.color ?? '#1F2329',
          width: msg.width ?? 3, owner: '', points: [p]
        };
        this.strokes.push(s);
        this.drawDot(s, p);
        break;
      }
      case 'stroke_move': {
        const s: StrokeInfo | null = this.findStroke(msg.id ?? '');
        const p: Point = msg.point ?? { x: 0, y: 0 };
        if (s !== null && s.points.length > 0) {
          const prev: Point = s.points[s.points.length - 1];
          s.points.push(p);
          this.drawSegment(s, prev, p);
        }
        break;
      }
      case 'stroke_end': {
        // 自己或他人画完一笔 → 截图刷新桌面卡片
        this.pushBoardCard();
        break;
      }
      case 'board_clear':
        this.strokes = [];
        this.current = null;
        this.redraw();
        this.pushBoardCard();
        break;
      case 'error': {
        this.status = msg.message ?? '出错了';
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

  /** 把当前白板截成图，推送到桌面卡片（缩小到卡片通道允许的尺寸内） */
  private pushBoardCard(): void {
    const ctx: Context = getContext(this).getApplicationContext();
    this.getUIContext().getComponentSnapshot().get('board_canvas', { scale: 0.25 })
      .then((pm: image.PixelMap): void => {
        CardSync.push({
          roomId: this.roomId, roomType: 'board', roomName: this.roomName,
          line1: this.roomName + ' 白板已更新',
          line2: '笔迹 ' + this.strokes.length + ' 条',
          ts: Date.now()
        }, pm, ctx);
      })
      .catch((): void => {
        // 截图失败就只推文字
        CardSync.push({
          roomId: this.roomId, roomType: 'board', roomName: this.roomName,
          line1: this.roomName + ' 白板已更新',
          line2: '笔迹 ' + this.strokes.length + ' 条',
          ts: Date.now()
        }, undefined, ctx);
      });
  }

  private findStroke(id: string): StrokeInfo | null {
    for (const s of this.strokes) {
      if (s.id === id) {
        return s;
      }
    }
    return null;
  }

  private toPx(p: Point): Point {
    return { x: p.x * this.canvasW, y: p.y * this.canvasH };
  }

  private drawDot(s: StrokeInfo, p: Point): void {
    if (this.canvasW <= 0) {
      return;
    }
    const q: Point = this.toPx(p);
    this.ctx.fillStyle = s.color;
    this.ctx.beginPath();
    this.ctx.arc(q.x, q.y, Math.max(1, s.width) / 2, 0, Math.PI * 2);
    this.ctx.fill();
  }

  private drawSegment(s: StrokeInfo, a: Point, b: Point): void {
    if (this.canvasW <= 0) {
      return;
    }
    const pa: Point = this.toPx(a);
    const pb: Point = this.toPx(b);
    this.ctx.strokeStyle = s.color;
    this.ctx.lineWidth = s.width;
    this.ctx.beginPath();
    this.ctx.moveTo(pa.x, pa.y);
    this.ctx.lineTo(pb.x, pb.y);
    this.ctx.stroke();
  }

  private redraw(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    this.ctx.fillStyle = '#FFFFFF';
    this.ctx.fillRect(0, 0, this.canvasW, this.canvasH);
    for (const s of this.strokes) {
      if (s.points.length === 1) {
        this.drawDot(s, s.points[0]);
      } else {
        for (let i: number = 1; i < s.points.length; i++) {
          this.drawSegment(s, s.points[i - 1], s.points[i]);
        }
      }
    }
  }

  private newId(): string {
    return 'k' + Date.now().toString() + Math.floor(Math.random() * 10000).toString();
  }

  private onTouchDraw(event: TouchEvent): void {
    if (this.status !== '已连接' || this.canvasW <= 0 || this.canvasH <= 0 || event.touches.length === 0) {
      return;
    }
    const t: TouchObject = event.touches[0];
    const p: Point = {
      x: Math.max(0, Math.min(1, t.x / this.canvasW)),
      y: Math.max(0, Math.min(1, t.y / this.canvasH))
    };

    if (event.type === TouchType.Down) {
      const id: string = this.newId();
      const s: StrokeInfo = {
        id: id, color: this.color, width: this.lineWidth,
        owner: this.selfId, points: [p]
      };
      this.strokes.push(s);
      this.current = s;
      this.lastSent = p;
      this.drawDot(s, p);
      this.client.strokeStart(id, s.color, s.width, p.x, p.y);
    } else if (event.type === TouchType.Move) {
      const s: StrokeInfo | null = this.current;
      if (s === null) {
        return;
      }
      const dist: number = Math.abs(p.x - this.lastSent.x) + Math.abs(p.y - this.lastSent.y);
      if (dist < 0.003) {
        return;
      }
      const prev: Point = s.points[s.points.length - 1];
      s.points.push(p);
      this.drawSegment(s, prev, p);
      this.lastSent = p;
      this.client.strokeMove(s.id, p.x, p.y);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const s: StrokeInfo | null = this.current;
      if (s !== null) {
        this.client.strokeEnd(s.id);
        this.current = null;
        this.pushBoardCard();
      }
    }
  }

  /** ① 接服务器：进入页面时自动连；供关闭后手动重连 */
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
      .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      .backgroundColor('#FFFFFF');

      Text(this.memberText)
        .fontSize(12)
        .fontColor('#8A8F99')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
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
      .padding({ left: 16, right: 16, bottom: 8 })
      .backgroundColor('#FFFFFF');

      Row({ space: 8 }) {
        ForEach(this.colors, (c: string) => {
          Text('')
            .width(26)
            .height(26)
            .backgroundColor(c)
            .borderRadius(13)
            .border({ width: this.color === c ? 2 : 0, color: '#1F2329' })
            .onClick((): void => {
              this.color = c;
            });
        }, (c: string) => c);

        Blank();

        ForEach(this.widths, (w: number) => {
          Text(w === 2 ? '细' : (w === 8 ? '粗' : '中'))
            .fontSize(12)
            .fontColor(this.lineWidth === w ? '#FFFFFF' : '#5F636B')
            .backgroundColor(this.lineWidth === w ? '#4F7DF3' : '#EFF1F4')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(8)
            .onClick((): void => {
              this.lineWidth = w;
            });
        }, (w: number) => '' + w);
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 });

      Canvas(this.ctx)
        .id('board_canvas')
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .onReady((): void => {
          this.canvasW = this.ctx.width;
          this.canvasH = this.ctx.height;
          this.redraw();
        })
        .onTouch((event: TouchEvent): void => {
          this.onTouchDraw(event);
        });

      Row() {
        Text('用手指或鼠标直接在画布上画，其他人会实时看到')
          .fontSize(12)
          .fontColor('#9A9FA8');
        Blank();
        Text('清空画布')
          .fontSize(13)
          .fontColor('#C0563B')
          .onClick((): void => {
            this.client.clearBoard();
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 18 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8');
  }
}
