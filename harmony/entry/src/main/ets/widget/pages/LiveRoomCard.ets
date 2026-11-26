let storage = new LocalStorage();

@Entry(storage)
@Component
struct LiveRoomCard {
  @LocalStorageProp('roomId') roomId: string = 'chat-lobby';
  @LocalStorageProp('roomType') roomType: string = 'chat';
  @LocalStorageProp('roomName') roomName: string = '大厅闲聊';
  @LocalStorageProp('line1') line1: string = '暂无新消息';
  @LocalStorageProp('line2') line2: string = '点击进入 LiveRoom';
  @LocalStorageProp('time') time: string = '';
  @LocalStorageProp('imgKey') imgKey: string = '';

  build() {
    Column({ space: 4 }) {
      // 顶栏
      Row() {
        Text('LiveRoom')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4F7DF3');
        Blank();
        Text(this.time)
          .fontSize(10)
          .fontColor('#9A9FA8');
      }
      .width('100%');

      if (this.imgKey !== '') {
        // 白板快照模式
        Stack() {
          Image('memory://' + this.imgKey)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .alt($r('app.media.icon'));
          Column() {
            Blank();
            Text(this.roomName + ' · ' + this.line2)
              .fontSize(10)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor('#80000000')
              .borderRadius(6)
              .maxLines(1);
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(4);
        }
        .layoutWeight(1)
        .width('100%');
      } else {
        // 聊天模式
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(this.roomName)
              .fontSize(11)
              .fontColor('#3367C4')
              .backgroundColor('#E8F0FE')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .maxLines(1);
          }
          .width('100%');

          Text(this.line1)
            .fontSize(12)
            .fontColor('#1F2329')
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Blank();

          Text(this.line2)
            .fontSize(10)
            .fontColor('#9A9FA8')
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(HorizontalAlign.Start);
      }

      Text('点击进入 ›')
        .fontSize(10)
        .fontColor('#4F7DF3')
        .width('100%')
        .textAlign(TextAlign.End);
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor('#F5F6F8')
    .borderRadius(14)
    .onClick((): void => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'roomId': this.roomId,
          'roomType': this.roomType,
          'roomName': this.roomName
        }
      });
    });
  }
}
