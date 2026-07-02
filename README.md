# ComfyUI Pulse

实时 HTTP 请求捕获服务器 —— 接收 HTTP 请求中的图片/文件附件，在前端实时展示并自动下载到本地。

## 快速开始

### 本地开发

```bash
# 1. 启动后端（默认 :8088）
cd backend
uv run main.py --save-request-info

# 2. 启动前端开发服务器（新终端）
cd frontend
pnpm install
pnpm dev
```

打开 `http://localhost:5173`，向后端发送含图片的 HTTP 请求即可实时查看。

### 配置参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--host` | `127.0.0.1` | 监听地址，容器内需设为 `0.0.0.0` |
| `--port` | `8088` | 监听端口 |
| `--save-request-info` | 不启用 | 将请求详情保存为文本文件 |
| `--out` | `requests` | 请求详情保存目录 |
| `--max-body-bytes` | 不限 | 单次请求最大 body 字节数 |
| `--frontend-dir` | 不启用 | 前端静态文件目录（生产部署时使用） |

---

## Docker 部署（推荐）

### 构建并启动

```bash
# 在项目根目录执行
docker compose up -d
```

容器启动后，访问 `http://<服务器IP>:8088` 即可打开前端页面。

### 持久化数据

`docker-compose.yml` 已配置两个数据卷：

- `./backend/downloads` —— 接收到的附件文件（图片等）
- `./backend/requests` —— 请求详情文本（启用 `--save-request-info` 时）

### 调整端口

编辑 `docker-compose.yml`，修改 ports 映射：

```yaml
ports:
  - "8088:8088"   # 改为 "你想要的端口:8088"
```

---

## Nginx 反向代理 + HTTPS

> **重要**：`/api/events`（SSE 实时推送端点）必须关闭 `proxy_buffering`，否则前端无法实时收到新图片通知。

```nginx
server {
    listen 80;
    server_name your-domain.com;

    # SSE 端点 - 禁用缓冲
    location /api/events {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
    }

    # API 和文件下载
    location /api/ {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
    }

    location /downloads/ {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
    }

    # 前端页面
    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

建议配合 [acme.sh](https://github.com/acmesh-official/acme.sh) 或 Certbot 配置 HTTPS：

```bash
# 以 acme.sh 为例
acme.sh --issue -d your-domain.com --nginx
acme.sh --install-cert -d your-domain.com --nginx
```

---

## 发送测试请求

服务运行后，可以通过以下方式向其发送图片：

```bash
# multipart/form-data 上传文件
curl -X POST http://localhost:8088/upload \
  -F "image=@photo.jpg"

# 直接发送二进制图片
curl -X POST http://localhost:8088/image \
  -H "Content-Type: image/jpeg" \
  --data-binary @photo.jpg

# JSON 内嵌 base64 图片
curl -X POST http://localhost:8088/api/data \
  -H "Content-Type: application/json" \
  -d '{"image": {"filename": "demo.png", "data": "'$(base64 -w0 photo.png)'"}}'
```

---

## 项目结构

```
comfyui-pulse/
├── docker-compose.yml       # Docker 编排
├── Dockerfile               # 多阶段构建
├── .dockerignore
├── backend/
│   ├── main.py              # 入口
│   ├── pyproject.toml
│   └── src/server/
│       ├── server.py        # HTTP 服务器 + SSE + API
│       ├── attachment.py    # 附件提取逻辑
│       ├── cli.py           # CLI 参数解析
│       ├── events.py        # 事件总线
│       └── utils.py         # 工具函数
├── frontend/
│   ├── src/
│   │   ├── App.vue
│   │   ├── api.ts           # SSE 客户端
│   │   └── components/
│   │       └── ImageGallery.vue
│   └── vite.config.ts
└── README.md
```
