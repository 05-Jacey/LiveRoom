import { router } from '@kit.ArkUI';
import { AppConfig, RoomInfo } from '../common/Constants';

@Entry
@Component
struct Index {
  @State nick: string = '鸿蒙访客';
  @State host: string = AppConfig.DEFAULT_HOST;
  private rooms: RoomInfo[] = AppConfig.rooms();

  private enter(room: RoomInfo): void {
    const url: string = room.type === 'board' ? 'pages/BoardRoomPage' : 'pages/ChatRoomPage';
    router.pushUrl({
      url: url,
      params: {
        roomId: room.id,
        roomName: room.name,
        host: this.host,
        name: this.nick
      }
    });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 6 }) {
          Text('LiveRoom')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2329')
            .width('100%');
          Text('多房间实时聊天 · 多人协作白板')
            .fontSize(14)
            .fontColor('#8A8F99')
            .width('100%');
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%');

        Column({ space: 12 }) {
          Text('连接设置')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%');

          Text('昵称')
            .fontSize(13)
            .fontColor('#8A8F99')
            .width('100%');
          TextInput({ text: this.nick, placeholder: '你的昵称' })
            .height(44)
            .width('100%')
            .onChange((value: string): void => {
              this.nick = value;
            });

          Text('服务器地址（IP:端口）')
            .fontSize(13)
            .fontColor('#8A8F99')
            .width('100%');
          TextInput({ text: this.host, placeholder: '10.64.100.99:3000' })
            .height(44)
            .width('100%')
            .onChange((value: string): void => {
              this.host = value;
            });

          Text('填服务端启动时打印的局域网地址。手机和电脑要连同一个 WiFi。')
            .fontSize(12)
            .fontColor('#9A9FA8')
            .width('100%');
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(14);

        Column({ space: 10 }) {
          Text('选择房间')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%');

          ForEach(this.rooms, (item: RoomInfo) => {
            Column({ space: 4 }) {
              Row() {
                Text(item.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1F2329');
                Blank();
                Text(item.type === 'board' ? '白板' : '聊天')
                  .fontSize(12)
                  .fontColor(item.type === 'board' ? '#B2603A' : '#3367C4')
                  .backgroundColor(item.type === 'board' ? '#FCEEE6' : '#E8F0FE')
                  .padding({ left: 9, right: 9, top: 2, bottom: 2 })
                  .borderRadius(10);
              }
              .width('100%');

              Text(item.desc)
                .fontSize(13)
                .fontColor('#8A8F99')
                .width('100%');
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .onClick((): void => {
              this.enter(item);
            });
          }, (item: RoomInfo) => item.id);
        }
        .width('100%');

        Text('同一房间的 HarmonyOS 端、手机浏览器、电脑浏览器消息互通。')
          .fontSize(12)
          .fontColor('#9A9FA8')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 4, bottom: 20 });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8');
  }
}
