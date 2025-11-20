FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install dependencies
RUN apt-get update && apt-get install -y \
    git \
    lua5.2 \
    liblua5.2 \
    liblua5.2-dev \
    luarocks \
    gcc \
    g++ \
    make \
    build-essential \
    pkg-config \
    zip \
    unzip \
    rlwrap \
    zlib1g-dev \
    lua-posix \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone your repository
RUN git clone https://github.com/sauerbraten-chungus/chungusmod.git /app

# Install Lua modules
RUN luarocks install dkjson
RUN luarocks install luasocket
RUN luarocks install struct 
RUN luarocks install uuid 
RUN luarocks install mmdblua

# Build the server
RUN make

# Expose game server ports
# EXPOSE 28785/tcp
# EXPOSE 28785/udp
# EXPOSE 28786/tcp
# EXPOSE 28786/udp

# Set the default command
ENV CHUNGUS=1
ENV AUTH_URL=http://auth:8081/auth
ENV QUERY_SERVICE_URL=http://localhost:8080/intermission
ENV CHUNGUS_PEER_ADDRESS=host.docker.internal
ENV CHUNGUS_PEER_PORT=30000
ENV ADMIN_NAME=kappachungus
ENV ADMIN_DOMAIN=kappachungus.auth
ENV ADMIN_PUBLIC_KEY=+425ae6707d8c05dead7100fb2f73d44a9778081b6d77c54c
CMD ["./sauer_server"]
# CMD CHUNGUS=1 ./sauer_server
# CMD ["sh", "-c", "echo CHUNGUS=$CHUNGUS && ./sauer_server"]
