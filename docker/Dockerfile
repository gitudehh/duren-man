# Use the official Ubuntu image as the base
FROM ubuntu:latest

# Update the package lists & Install Nginx
RUN apt-get update -y && apt-get install -y nginx

# Copy file Hello.txt to /var/www/
COPY hello.txt /var/www/

# Expose port 80 for HTTP traffic
EXPOSE 80

# Start Nginx when the container starts
CMD ["nginx", "-g", "daemon off;"]