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
EXPOSE 28785/tcp
EXPOSE 28785/udp
EXPOSE 28786/tcp
EXPOSE 28786/udp

# Set the default command
ENV CHUNGUS=1
# CMD ["./sauer_server"]
# CMD CHUNGUS=1 ./sauer_server
CMD ["sh", "-c", "echo CHUNGUS=$CHUNGUS && ./sauer_server"]
