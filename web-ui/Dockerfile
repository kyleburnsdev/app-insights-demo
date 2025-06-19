# Build stage
FROM node:20-alpine AS build
WORKDIR /app
RUN apk update && apk upgrade --no-cache
# Copy only package.json and package-lock.json first for better cache usage
COPY package*.json ./
RUN npm install --production=false
# Now copy the rest of the source
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
