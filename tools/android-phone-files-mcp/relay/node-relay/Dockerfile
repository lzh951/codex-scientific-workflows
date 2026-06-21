FROM node:22-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js ./

ENV PORT=8788
EXPOSE 8788

CMD ["node", "server.js"]
