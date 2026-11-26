import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  JoinMessage,
  ChatMessageOut,
  StrokeStartOut,
  StrokeMoveOut,
  StrokeIdOut,
  SimpleOut,
  Point
} from '../model/Protocol';

export type RawMessageHandler = (data: string) => void;
export type StateHandler = (state: string) => void;

/**
 * WebSocket 长连接封装。
 * 负责：连接、注册监听、应用层心跳、断线自动重连、重连后自动重新加入房间。
 * 页面只需要设置 onMessage / onState 两个回调，再调用对应的业务方法。
 */
export class RoomClient {
  private socket: webSocket.WebSocket | null = null;
  private url: string = '';
  private roomId: string = '';
  private nickName: string = '';
  private manualClosed: boolean = false;
  private reconnectScheduled: boolean = false;
  private reconnectTimer: number = -1;
  private heartbeatTimer: number = -1;
  private attempts: number = 0;

  onMessage: RawMessageHandler = (_data: string): void => {};
  onState: StateHandler = (_state: string): void => {};

  connect(url: string): void {
    this.url = url;
    this.manualClosed = false;
    this.attempts = 0;
    this.reconnectScheduled = false;
    this.openSocket();
  }

  private openSocket(): void {
    this.onState(this.attempts === 0 ? '连接中…' : `重连中（第 ${this.attempts} 次）`);
    const ws: webSocket.WebSocket = webSocket.createWebSocket();
    this.socket = ws;

    ws.on('open', (err: BusinessError, _value: object): void => {
      if (err) {
        return;
      }
      this.attempts = 0;
      this.onState('已连接');
      // 断线重连成功后自动重新进入原来的房间
      if (this.roomId.length > 0) {
        this.sendJoin(this.roomId, this.nickName);
      }
      this.startHeartbeat();
    });

    ws.on('message', (err: BusinessError, value: string | ArrayBuffer): void => {
      if (err) {
        return;
      }
      if (typeof value === 'string') {
        this.onMessage(value);
      }
    });

    ws.on('close', (err: BusinessError, _value: webSocket.CloseResult): void => {
      this.stopHeartbeat();
      this.socket = null;
      if (this.manualClosed) {
        this.onState('已断开');
        return;
      }
      this.scheduleReconnect();
    });

    ws.on('error', (err: BusinessError): void => {
      console.error(`[LiveRoom] websocket error: ${JSON.stringify(err)}`);
      this.onState('连接异常');
    });

    ws.connect(this.url, (err: BusinessError, _value: boolean): void => {
      if (err) {
        console.error(`[LiveRoom] connect failed: ${JSON.stringify(err)}`);
        this.onState('连接失败，稍后重试');
        this.scheduleReconnect();
      }
    });
  }

  private scheduleReconnect(): void {
    if (this.manualClosed || this.reconnectScheduled) {
      return;
    }
    this.reconnectScheduled = true;
    this.attempts += 1;
    this.onState('连接已断开，3 秒后自动重连');
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectScheduled = false;
      if (!this.manualClosed) {
        this.openSocket();
      }
    }, 3000);
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval((): void => {
      const ping: SimpleOut = { type: 'ping' };
      this.sendRaw(JSON.stringify(ping));
    }, 15000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  private sendRaw(text: string): void {
    const ws: webSocket.WebSocket | null = this.socket;
    if (ws === null) {
      return;
    }
    ws.send(text, (err: BusinessError, _value: boolean): void => {
      if (err) {
        console.error(`[LiveRoom] send failed: ${JSON.stringify(err)}`);
      }
    });
  }

  join(roomId: string, name: string): void {
    this.roomId = roomId;
    this.nickName = name;
    const msg: JoinMessage = { type: 'join', roomId: roomId, name: name };
    this.sendRaw(JSON.stringify(msg));
  }

  private sendJoin(roomId: string, name: string): void {
    const msg: JoinMessage = { type: 'join', roomId: roomId, name: name };
    this.sendRaw(JSON.stringify(msg));
  }

  sendChat(text: string): void {
    const msg: ChatMessageOut = { type: 'chat', text: text };
    this.sendRaw(JSON.stringify(msg));
  }

  strokeStart(id: string, color: string, width: number, x: number, y: number): void {
    const point: Point = { x: x, y: y };
    const msg: StrokeStartOut = { type: 'stroke_start', id: id, color: color, width: width, point: point };
    this.sendRaw(JSON.stringify(msg));
  }

  strokeMove(id: string, x: number, y: number): void {
    const point: Point = { x: x, y: y };
    const msg: StrokeMoveOut = { type: 'stroke_move', id: id, point: point };
    this.sendRaw(JSON.stringify(msg));
  }

  strokeEnd(id: string): void {
    const msg: StrokeIdOut = { type: 'stroke_end', id: id };
    this.sendRaw(JSON.stringify(msg));
  }

  clearBoard(): void {
    const msg: SimpleOut = { type: 'board_clear' };
    this.sendRaw(JSON.stringify(msg));
  }

  /** 主动离开房间：不再自动重连 */
  disconnect(): void {
    this.manualClosed = true;
    this.stopHeartbeat();
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    const ws: webSocket.WebSocket | null = this.socket;
    if (ws !== null) {
      try {
        // SDK 签名：close(options: WebSocketCloseOptions, callback: AsyncCallback<boolean>): void
        // code / reason 必须包成对象，不能直接传两个位置参数
        ws.close({ code: 1000, reason: '离开房间' },
          (err: BusinessError, _value: boolean): void => {
            if (err) {
              console.error(`[LiveRoom] close failed: ${JSON.stringify(err)}`);
            }
          });
      } catch (error) {
        console.error(`[LiveRoom] close failed: ${JSON.stringify(error)}`);
      }
      this.socket = null;
    }
    this.roomId = '';
    this.onState('已断开');
  }
}
