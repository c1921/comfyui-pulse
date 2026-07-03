# ComfyUI Pulse

实时 HTTP 请求捕获服务器 —— 接收 HTTP 请求中的图片/文件附件，通过 Flutter 桌面端 / Android 应用实时展示并保存到本地。

## 系统架构

```
[Flutter App (Windows/Android)]  ←  SSE + REST  →  [Python 后端 :8088]
```

## 快速开始

### 1. 启动后端

```bash
cd backend
python main.py --save-request-info
```

### 2. 运行 Flutter 应用

```bash
cd frontend
flutter run -d windows
# 或
flutter run -d android
```

## Docker 部署（后端）

Flutter 前端是原生桌面/移动应用，不在 Docker 中运行。后端可单独用 Docker 部署：

```bash
docker compose up -d
```

## Flutter 应用构建

```bash
flutter build windows --release
flutter build apk --release
```

## 项目结构

后端: backend/src/server/ (Python)
前端: frontend/lib/ (Flutter/Dart)

## 技术栈

- 后端: Python 3.14+（零外部依赖）
- 前端: Flutter 3.32 + Dart 3.8
  - Windows 桌面原生应用
  - Android 移动应用
  - 状态管理: Provider
  - 网络: HTTP + SSE 流式推送
