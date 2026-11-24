FROM nginx:1.30.8-alpine

COPY index.html jeonse-example-rooms.png /usr/share/nginx/html/

EXPOSE 80
