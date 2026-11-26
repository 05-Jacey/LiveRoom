# LiveRoom · 多房间实时聊天 + 多人协作白板

一个用得上 WebSocket 的完整小项目：**聊天室打底，白板是第二种房间类型**。

三端共用同一个服务端、同一套协议、同一批房间，所以 HarmonyOS 手机、朋友的手机浏览器、朋友的电脑浏览器可以同时在同一个房间里聊天或画画。

```
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ HarmonyOS 原生 │  │ 朋友手机浏览器 │  │ 朋友电脑浏览器 │
│   (ArkTS)      │  │   (Web 页)     │  │   (Web 页)     │
└───────┬────────┘  └───────┬────────┘  └───────┬────────┘
        └────────────────────┼────────────────────┘
                             │ WebSocket /ws
                    ┌────────▼─────────┐
                    │  Node.js 服务端  │
                    │  chat / board    │
                    │  房间 · 成员 · 快照│
                    └──────────────────┘
```

服务端**零依赖**，Node 18+ 直接 `node server.js` 就能跑，不用 `npm install`。

---

## 目录

```
LiveRoom/
├─ server/
│  ├─ server.js            WebSocket 服务端 + 静态托管（零依赖）
│  ├─ package.json
│  └─ public/index.html    可分享的 Web 客户端
├─ harmony/                HarmonyOS 工程（DevEco Studio 打开这个目录）
│  └─ entry/src/main/ets/
│     ├─ common/Constants.ets      服务器地址、房间目录
│     ├─ model/Protocol.ets        协议数据模型
│     ├─ service/RoomClient.ets    连接 / 心跳 / 断线重连 / 重新入房
│     └─ pages/
│        ├─ Index.ets              昵称 + 地址 + 房间列表
│        ├─ ChatRoomPage.ets       聊天页
│        └─ BoardRoomPage.ets      Canvas 白板页
└─ README.md
```

---

## 快速开始（3 步）

### 1. 启动服务端

```bash
cd F:\HarmonyOS\LiveRoom\server
node server.js
```

控制台会打印：

```
  LiveRoom 服务端已启动
  本机访问     http://localhost:3000
  分享给朋友   http://10.64.100.99:3000   (WLAN)
  WebSocket    ws://10.64.100.99:3000/ws
```

**以实际打印的 IP 为准**（换 WiFi、换网卡都会变）。换端口用 `PORT=8080 node server.js`。

### 2. 电脑上先自己试

浏览器打开 `http://localhost:3000`，填个昵称，点「大厅闲聊」或「一起画」。
再开一个浏览器窗口（或换个昵称）进同一个房间，两边互发消息 / 画画，确认能实时互通。

### 3. 分享给朋友

把控制台打印的那条**局域网地址**发给朋友：

```
http://10.64.100.99:3000
```

朋友手机连**同一个 WiFi**，用浏览器打开就能进，不用装任何 App。页面上有「复制链接」按钮，也可以你直接复制发微信。

> 如果朋友打不开，九成是电脑防火墙拦了 3000 端口。Windows 上在「Windows Defender 防火墙 → 入站规则」放行 Node.js 或 TCP 3000 即可；或者临时关掉防火墙试一次。

---

## 电脑关了还能用吗

**不能。** 服务端 `node server.js` 跑在你电脑上，它是所有客户端的唯一中枢；电脑关机 / 休眠 / 断网，服务端进程就没了。

| 情况 | 结果 |
|---|---|
| 电脑关了，朋友页面还开着 | 页面还在（浏览器已加载），但连接断开、状态显示「已断开，3 秒后重连」并一直重试；已经显示出来的消息能看，发不出新消息 |
| 电脑重新开机、重新启动服务端 | Web 端和 HarmonyOS 端都有自动重连，朋友**不用刷新页面**就会自己连回来并重新入房 |
| 服务端重启之后 | 聊天历史和白板画布是**空的** |

最后一条要特别注意：**房间、在线成员、聊天历史（最近 120 条）、白板笔画（最近 600 笔）全部只存在内存里**，进程一停就清空，没有落盘。

想让它一直能用：

1. **把服务端放到常开的机器上** —— 云服务器最稳，或家里不关机的 NAS / 迷你主机。按下一节的方案 3 部署，再用 `pm2 start server.js` 之类的工具做进程保活和开机自启。
2. **想重启后聊天和画还在** —— 需要给服务端加持久化：把 `history` / `strokes` 定时写进 `data.json`，启动时读回来。当前版本没做这一步，作业演示用不到，但作为完整应用应该补上。

> 交作业截图的话，演示那会儿电脑开着就够了，不需要 7×24 在线。

---

## 部署到云：真正不用开电脑

先说清楚一件事：**只要用 WebSocket，就一定有一个服务端在某台机器上跑**。「不用开电脑」不是把服务端删掉，而是把 `server/` 搬到一台 7×24 在线的机器上。项目代码几乎不用改 —— 服务端本来就监听 `0.0.0.0`、支持 `PORT` 环境变量，Web 端和 HarmonyOS 端也都会自动切 `wss://`。

### 同时满足「不开电脑 + 不同 WiFi + 免费」

**答案就是 Render 免费层**：邮箱注册、不用信用卡；服务端跑在 Render 的机器上，你的电脑关不关都无所谓；拿到的是公网 `https://` 地址，朋友在哪个网络都能连。

免费层只有两个代价，都能缓解：

| 代价 | 缓解办法 |
|---|---|
| 约 15 分钟无请求会休眠，下次访问冷启动 30~50 秒 | UptimeRobot（免费 50 个监控）每 5 分钟 GET 一次 `https://你的域名/api/info`，服务就不会睡 |
| 聊天历史 / 白板笔画只在内存里，重启清空 | 交作业演示没影响；真要长期留存再加持久化 |

部署完用自检脚本一次验完 HTTP 和 WebSocket：

```bash
node server/verify-deploy.mjs https://liveroom-xxxx.onrender.com
```

四项全 PASS，就说明**电脑关机状态下、朋友用任意网络**都能连。把那个 `https://` 地址发给他，手机 App 首页也填它。

### 三条路

| 方案 | 成本 | 国内访问 | 适合 |
|---|---|---|---|
| 免费云 PaaS（Render / Koyeb） | 0 元 | 一般，可能偏慢 | 交作业、演示、发链接给朋友 |
| 国内学生机 / 轻量服务器 | 约 10 元/月 | 快、稳 | 想长期一直能用 |
| Serverless（Cloudflare Workers + Durable Objects） | 0 元、不休眠 | 不稳 | 进阶，需要改写服务端 |

> 免费 PaaS 两个坑：多数免费层**无流量一段时间会休眠**，下次访问要等冷启动（可以用 UptimeRobot 之类每 10 分钟 ping 一次 `/api/info` 缓解）；容器磁盘是临时的，重启后内存里的聊天和画布照样清空。作业演示够用，想真·随时在线还是学生机实在。

### 方案 A：Render 一键部署（文件已备好）

仓库里放好了 `server/Dockerfile`、`server/.dockerignore` 和根目录的 `render.yaml`。

1. 把 `LiveRoom/` 推到 **GitHub / GitLab / Bitbucket** 之一（免费仓库即可）。

   > Render 只接这三个 Git 平台，**不支持 Gitee / GitCode(AtomGit) / 码云**。已经建在 AtomGit 的话，本地加一个 GitHub remote 双推，或用 GitHub 的 Import repository 镜像过去即可。
   > 创建仓库时**不要勾选**「初始化 README / .gitignore / LICENSE」，本地已经有这些文件，勾了 push 会冲突。

   ```bash
   cd F:/HarmonyOS/LiveRoom
   git init
   git add .
   git commit -m "LiveRoom: WebSocket chat + whiteboard"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/LiveRoom.git
   git push -u origin main
   ```

2. 注册 [render.com](https://render.com)（邮箱即可，不用信用卡）→ Dashboard → **New → Blueprint** → 选中这个仓库，它会读 `render.yaml` 自动创建服务。
3. 构建完成后拿到 `https://liveroom-xxxx.onrender.com`。
4. 先跑自检：`node server/verify-deploy.mjs https://liveroom-xxxx.onrender.com`，四项全 PASS 再往下走。
5. 注册 [uptimerobot.com](https://uptimerobot.com)（免费）→ Add Monitor → 类型 HTTP(s)、URL 填 `https://liveroom-xxxx.onrender.com/api/info`、间隔 5 分钟。这样免费层不会休眠。
6. 把 `https://liveroom-xxxx.onrender.com` 发给朋友，浏览器打开即用；手机 App 首页「服务器地址」也填它（不带端口）。

不用 Blueprint 也行：New → Web Service → Runtime 选 Docker → Docker Context 填 `./server`。

### 方案 B：国内学生机（最稳）

腾讯云 / 阿里云的轻量应用服务器学生优惠约 10 元/月，装好 Node 后：

```bash
# 把 server/ 整个目录传上去
cd server
npm i -g pm2
pm2 start server.js --name liveroom
pm2 startup      # 按提示执行它输出的那条命令，实现开机自启
pm2 save
```

再配 Nginx 反代 + HTTPS 证书（配置见下一节方案 3），用 `https://你的域名` 访问。这样电脑关不关都无所谓。

### 部署完之后，地址怎么填

| 端 | 填什么 |
|---|---|
| 朋友（Web） | 直接发 `https://你的域名`，页面自动用 `wss://` |
| HarmonyOS App | 首页「服务器地址」填 `https://你的域名`，`wsUrl()` 自动拼成 `wss://你的域名/ws` |

`server.js` 目前把聊天历史和白板笔画存在内存里，云端重启后会清空。想要重启也不丢，需要加持久化（把 `history` / `strokes` 写进 `data.json` 或数据库）—— 这一步可以让我帮你加。

> 下面一节的**临时隧道**（cloudflared / ngrok）仍然需要你的电脑开着，只是把局域网地址映射到公网；真正关机也能用的是上面这两个云端方案。

---

## 不在同一个 WiFi 怎么用

**代码不用改**：服务端默认监听 `0.0.0.0`；Web 端按页面协议自动选 `ws://` / `wss://`；HarmonyOS 端在地址栏填 `https://域名`，`Constants.ets` 的 `wsUrl()` 会自动切成 `wss://`。只差给服务端一个**公网能访问到的地址**。

前提：电脑不关机，`node server.js` 一直跑着。

### 方案 1：临时公网链接（最快）

在 **CMD / PowerShell**（不要用 Git Bash）里执行，本机已装 cloudflared 和 ngrok：

```bat
cloudflared tunnel --url http://localhost:3000
```

会打印一个 `https://xxxx.trycloudflare.com` 临时域名，直接发给朋友即可。或者：

```bat
ngrok http 3000
```

ngrok 免费版首次要 `ngrok config add-authtoken <你的token>`（官网注册后能拿到）。

> 如果 npm 的 `cloudflared` 命令没反应，直接调二进制：
> `"C:\Users\jacey\AppData\Roaming\npm\node_modules\cloudflared\bin\cloudflared.exe" tunnel --url http://localhost:3000`

- **Web 端**：朋友打开那个 `https://` 链接就行，页面自动用 `wss://`。
- **HarmonyOS 端**：首页「服务器地址」填 `https://xxxx.trycloudflare.com`（不带端口）。
- 临时域名每次重启都会变；`trycloudflare.com` / ngrok 在国内可能偏慢或偶发连不上，演示够用，长期用看方案 3。
- 国内更稳的同类工具：cpolar、natapp、花生壳（需注册实名，开通隧道时确认「支持 WebSocket」）。

### 方案 2：只给固定几个人（不暴露公网）

Tailscale / ZeroTier 组一个虚拟局域网，朋友装客户端加入后，用分配给电脑的虚拟 IP（如 `100.x.y.z:3000`）访问。走 `ws://`，不用证书。缺点是朋友也要装软件。

### 方案 3：云服务器（最稳）

1. 把 `server/` 整个目录传上去，`node server.js` 跑起来（或 `pm2 start server.js` 保活）。
2. 安全组 / 防火墙放行端口。
3. Nginx 反代 + HTTPS 证书：

```nginx
server {
    listen 443 ssl;
    server_name your.domain.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        # 这三行是 WebSocket 的关键，少了就会连上秒断
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        # 服务端 20 秒一次心跳，超时要留够
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

`nginx -t && nginx -s reload` 后用 `https://your.domain.com` 访问。

### 地址怎么填

| 场景 | 发给朋友的 Web 链接 | HarmonyOS 首页地址栏 |
|---|---|---|
| 同一 WiFi | `http://10.64.100.99:3000` | `10.64.100.99:3000` |
| 临时隧道 / 云服务器 HTTPS | `https://xxxx.trycloudflare.com` | `https://xxxx.trycloudflare.com` |
| 只有 HTTP 的公网 IP | `http://1.2.3.4:3000` | `1.2.3.4:3000` |

### 三个容易踩的坑

- **必须转发 Upgrade 头**：反代或隧道不支持 WebSocket Upgrade 时，页面能打开但连接秒断。
- **https 页面必须配 wss**：浏览器会拦截混合内容；代码已自动处理，别手动填 `ws://`。
- **超时时间**：服务端每 20 秒发一次 ping 帧、60 秒无响应才断开，反代的 `proxy_read_timeout` 别设成 30 秒。

---

## HarmonyOS 原生端

1. DevEco Studio 打开 `F:\HarmonyOS\LiveRoom\harmony`（不是 LiveRoom 根目录）。
2. 首次打开用 **File → Project Structure → Signing Configs → 自动签名**，生成调试证书（本机真机调试用）。
3. 首页「服务器地址」填服务端打印的 `IP:端口`，例如 `10.64.100.99:3000`。
   - 也可以直接改 `entry/src/main/ets/common/Constants.ets` 里的 `DEFAULT_HOST` 当默认值。
   - 手机必须和电脑在**同一个 WiFi**，且能 ping 通这个 IP。
4. 选房间进入。聊天房发文字，白板房用手指画。

> 调试签名绑定设备 UDID，HAP 不能直接发给别人安装，所以「分享入口」请用 Web 端。原生端是给自己用的作品主体。

`module.json5` 里已声明 `ohos.permission.INTERNET` 和 `GET_NETWORK_INFO`。

---

## 协议（都是 JSON 文本帧，端点 `/ws`）

### 客户端 → 服务端

| type | 字段 | 说明 |
|---|---|---|
| `join` | `roomId`, `name` | 进入房间；不存在的房间号会自动创建临时房间 |
| `chat` | `text` | 聊天消息（仅 chat 房有效） |
| `stroke_start` | `id`, `color`, `width`, `point` | 起笔（仅 board 房有效） |
| `stroke_move` | `id`, `point` | 笔迹增量点 |
| `stroke_end` | `id` | 抬笔 |
| `board_clear` | — | 清空画布，广播给所有人 |
| `list_rooms` | — | 请求房间列表 |
| `create_room` | `roomId`, `name`, `roomType` | Web 端新建房间 |
| `leave` | — | 主动离开房间 |
| `ping` | — | 应用层心跳，服务端回 `pong` |

`point` 是 `{x, y}`，取值 **0~1 归一化坐标**，所以不同尺寸的屏幕看到的是同一幅画。

### 服务端 → 客户端

| type | 主要字段 | 说明 |
|---|---|---|
| `hello` | `clientId`, `rooms` | 连接建立 |
| `rooms` | `rooms` | 房间列表 + 实时在线人数 |
| `joined` | `clientId`, `room`, `members`, `history`, `strokes` | 入房成功，附聊天历史或白板快照 |
| `members` | `members` | 成员变动 |
| `chat` / `system` | `fromId`, `fromName`, `color`, `text`, `ts` | 聊天消息 / 系统提示 |
| `stroke_start` / `stroke_move` / `stroke_end` | `id`, `color`, `width`, `point` | 别人的笔迹（不回传给作者本人） |
| `board_clear` | — | 画布已清空 |
| `error` | `message` | 错误提示 |

服务端还每 20 秒发一次 WebSocket `ping` 控制帧，浏览器会自动回 `pong`；60 秒无响应会断开连接。

---

## 内置房间

| 房间号 | 类型 | 名字 |
|---|---|---|
| `chat-lobby` | chat | 大厅闲聊 |
| `chat-dev` | chat | 技术茶馆 |
| `board-canvas` | board | 一起画 |
| `board-brain` | board | 头脑风暴 |

Web 端还能现场新建房间；新建的房间在所有人离开后（临时房间）会被自动回收。

---

## 排错清单

- **Web 页一直显示「已断开，3 秒后重连」** → 服务端没起来，或端口被占用；看控制台有没有打印地址。
- **手机打不开局域网地址** → 防火墙 / 手机连的是访客网络或另一频段 / IP 填成了 `192.168.56.1` 这类虚拟网卡地址。
- **HarmonyOS 端连不上** → 地址栏填的是 `IP:端口`（不要带 `http://`），并且确认 `module.json5` 的 INTERNET 权限在；真机调试需自动签名。
- **编译通过但部署报 `Install Failed ... code:9568320 / no signature file`** → 光有 `signingConfigs` 不够，`build-profile.json5` 的 `products[0]` 里必须有 `"signingConfig": "default"`。DevEco 的「自动签名」只生成证书和 profile 并写入 `signingConfigs`，不会自动补 product 上的这个引用；补上后 Sync 再 Run。
- **公网连上但秒断** → 反代没开 WebSocket Upgrade，或页面是 https 却用了 `ws://`（必须用 `wss://`）。
- **白板上后进来的人看不到之前画的** → 检查 `joined` 消息里的 `strokes` 快照是否正常返回；服务端默认保留最近 600 笔。

---

## 作业截图：三个功能怎么截

课堂上的 `WebSocketPage` 只是老师给的教学案例，**作业交付的是 LiveRoom 这一个项目**：自己写的 WebSocket 应用，要能演示「接服务器 / 发送消息 / 关闭服务器」三个功能。

这里的「关闭服务器」按课堂案例的用法实现为**断开 WebSocket 连接**，不会真的把 Node 服务端停掉。

### 三个功能在 LiveRoom 主流程里的位置

| 作业要求 | LiveRoom 里的实现 |
|---|---|
| 接服务器 | 首页填 `IP:端口` → 点房间卡片建立连接；房间页顶部的「连接服务器」按钮可在关闭后重新连接 |
| 发送消息 | 聊天页输入 + 「发送」；白板房则是画布笔迹实时同步 |
| 关闭服务器 | 聊天页 / 白板页顶部的「关闭服务器」按钮，点击后状态变「已断开」，页面保留便于截图 |

三个功能都在应用主流程里，不是另外拼出来的页面。

### 截图顺序（三张）

前提：服务端 `node server.js` 正在跑，手机和电脑同一 WiFi，应用已 Sync + Run 成功。

1. **接服务器** → 首页填 `10.64.100.99:3000`，点「大厅闲聊」进入，顶部状态变绿「已连接」、成员栏出现在线人数 → 截图 1。
   想拍到「连接」这个动作本身，可以先点「关闭服务器」再点「连接服务器」，状态从「已断开」变回「已连接」时截。
2. **发送消息** → 输入框写点内容，点「发送」，气泡出现在消息列表里；另一个浏览器窗口进同一房间也能同步收到 → 截图 2。
3. **关闭服务器** → 点顶部「关闭服务器」，状态变红「已断开」，页面保留不退出 → 截图 3。

白板房同理：进「一起画」→ 画两笔（同房间其他人实时看到，后进来的人还能拿到完整画布快照）→ 点「关闭服务器」。

**小技巧**：三张图连着截、中间别退出页面，第三张的状态变化和前两张留下的消息记录能互相印证。
