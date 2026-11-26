FROM node:20-alpine

WORKDIR /app

COPY package.json ./
COPY server.js ./
COPY public ./public

# 云平台会注入 PORT，server.js 已支持 process.env.PORT
ENV PORT=3000
ENV HOST=0.0.0.0
EXPOSE 3000

CMD ["node", "server.js"]
