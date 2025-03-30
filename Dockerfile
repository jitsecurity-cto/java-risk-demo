FROM debian:buster

# Run as root (security issue)
USER root

# Install packages without verification and leave cache (bloat + security risk)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    wget \
    netcat \
    nmap

# Expose sensitive environment variables in image
ENV AWS_ACCESS_KEY="AKIA123456789" \
    AWS_SECRET_KEY="verysecretkey123" \
    API_TOKEN="mytokenshouldnotbehere"

# Copy with wrong permissions
COPY --chmod=777 . /app/

# Expose multiple ports
EXPOSE 22 80 443 3306 5432
