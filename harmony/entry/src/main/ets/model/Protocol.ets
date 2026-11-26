/**
 * 客户端与服务端之间的 JSON 协议模型。
 * 所有字段设为可选：服务端按消息类型只发需要的字段，页面按 type 分支读取。
 */

export interface Point {
  x: number;
  y: number;
}

export interface MemberInfo {
  id: string;
  name: string;
  color: string;
}

export interface RoomSummary {
  id: string;
  name: string;
  type: string;
  members: number;
}

export interface RoomBrief {
  id: string;
  name: string;
  type: string;
  desc: string;
}

/** 聊天列表的一条：kind = chat | system */
export interface ChatItem {
  kind: string;
  id: string;
  fromId: string;
  fromName: string;
  color: string;
  text: string;
  ts: number;
}

/** 一条笔画，points 使用 0~1 归一化坐标，适配不同屏幕尺寸 */
export interface StrokeInfo {
  id: string;
  color: string;
  width: number;
  owner: string;
  points: Point[];
}

/** 服务端下发的统一信封 */
export interface ServerEnvelope {
  type?: string;
  clientId?: string;
  roomId?: string;
  roomName?: string;
  roomType?: string;
  name?: string;
  color?: string;
  text?: string;
  message?: string;
  ts?: number;
  id?: string;
  width?: number;
  point?: Point;
  from?: MemberInfo;
  room?: RoomBrief;
  kind?: string;
  fromId?: string;
  fromName?: string;
  members?: MemberInfo[];
  rooms?: RoomSummary[];
  history?: ChatItem[];
  strokes?: StrokeInfo[];
}

/** 客户端发出的消息 */
export interface JoinMessage {
  type: string;
  roomId: string;
  name: string;
}

export interface ChatMessageOut {
  type: string;
  text: string;
}

export interface StrokeStartOut {
  type: string;
  id: string;
  color: string;
  width: number;
  point: Point;
}

export interface StrokeMoveOut {
  type: string;
  id: string;
  point: Point;
}

export interface StrokeIdOut {
  type: string;
  id: string;
}

export interface SimpleOut {
  type: string;
}
