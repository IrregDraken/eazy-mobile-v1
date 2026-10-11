FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY public-site/package.json ./package.json
COPY public-site/ ./
EXPOSE 3000
CMD ["npm", "start"]
