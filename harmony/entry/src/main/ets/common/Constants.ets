/**
 * 服务端地址与房间目录。
 *
 * 服务端启动时会在控制台打印可用的局域网地址，例如：
 *   http://192.168.1.23:3000
 * 把其中的 IP:端口填到 App 首页的「服务器地址」输入框即可（不用重新编译）。
 * 下面的 DEFAULT_HOST 只是首次启动的默认值，按你的实际 WiFi 改。
 */
export interface RoomInfo {
  id: string;
  name: string;
  type: string;
  desc: string;
}

export class AppConfig {
  static readonly DEFAULT_HOST: string = '10.64.100.99:3000';

  /**
   * 把用户输入的地址规整成 ws(s)://host:port/ws。
   * 局域网填 IP:端口 走 ws://；公网若用 https 反代，填 https://域名 会自动切到 wss://。
   */
  static wsUrl(input: string): string {
    let secure: boolean = false;
    let host: string = input.trim();
    if (host.startsWith('ws://')) {
      host = host.substring(5);
    } else if (host.startsWith('http://')) {
      host = host.substring(7);
    } else if (host.startsWith('wss://')) {
      secure = true;
      host = host.substring(6);
    } else if (host.startsWith('https://')) {
      secure = true;
      host = host.substring(8);
    }
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    return (secure ? 'wss://' : 'ws://') + host + '/ws';
  }

  /** 房间列表与 server.js 的 ROOMS 保持一致 */
  static rooms(): RoomInfo[] {
    return [
      { id: 'chat-lobby', name: '大厅闲聊', type: 'chat', desc: '随便聊聊，所有人都能进' },
      { id: 'chat-dev', name: '技术茶馆', type: 'chat', desc: 'HarmonyOS / 网络 / 踩坑记录' },
      { id: 'board-canvas', name: '一起画', type: 'board', desc: '多人实时协作白板' },
      { id: 'board-brain', name: '头脑风暴', type: 'board', desc: '画点什么，边聊边改' }
    ];
  }
}
