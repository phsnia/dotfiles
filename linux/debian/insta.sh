# [Firmware]
sudo apt update && sudo apt install firmware-linux-nonfree alsa-utils -y

# [WM]
sudo apt update && sudo apt install i3 xorg lightdm thunar -y

# [Audio]
sudo apt update && sudo apt install pavucontrol pulseaudio -y

# [Browser]
sudo apt update && sudo apt install extrepo -y
sudo extrepo enable librewolf
sudo apt update && sudo apt install librewolf -y

curl -O mes.deb "https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_138.0.3351.55-1_amd64.deb"
sudo dpkg -i microsoft-edge-stable_138.0.3351.55-1_amd64.deb

# [Code]
curl -L -o code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
sudo dpkg -i code.deb

# [Windsurf]
sudo apt-get install wget gpg
wget -qO- "https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/windsurf.gpg" | gpg --dearmor > windsurf-stable.gpg
sudo install -D -o root -g root -m 644 windsurf-stable.gpg /etc/apt/keyrings/windsurf-stable.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/windsurf-stable.gpg] https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt stable main" | sudo tee /etc/apt/sources.list.d/windsurf.list > /dev/null
rm -f windsurf-stable.gpg

sudo apt install apt-transport-https
sudo apt update

sudo apt install windsurf -y

# [Network]
sudo apt install network-manager -y

# [Terminal]
sudo apt install kitty fish -y

# [Bar]
sudo apt install polybar picom -y

# [Search]
sudo apt install rofi -y

# [Image]
sudo apt install nitrogen -y

# [Dotnet]
curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
chmod +x ./dotnet-install.sh
./dotnet-install.sh --channel 9.0
echo 'export DOTNET_ROOT=$HOME/.dotnet' >> ~/.bashrc
echo 'export PATH=$PATH:$HOME/.dotnet' >> ~/.bashrc
source ~/.bashrc

# [Temurin (Open java)]
sudo apt install -y wget apt-transport-https gpg
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list

sudo apt install -y temurin-21-jdk

# [Nim]
curl https://nim-lang.org/choosenim/init.sh -sSf | sh

# [Go]
mkdir -p ~/.go
wget https://go.dev/dl/$(curl -s https://go.dev/VERSION?m=text | head -1).linux-amd64.tar.gz -O ~/.go/go.tar.gz

rm -rf ~/.go/go
tar -C ~/.go -xzf ~/.go/go.tar.gz

echo 'export PATH=$PATH:$HOME/.go/go/bin' >> ~/.bashrc
source ~/.bashrc

# [Php]
php_installation_pipeline() {

}

# [Bun]
curl -fsSL https://bun.sh/install | bash

# [Ollama]
curl -fsSL https://ollama.com/install.sh | sh

ollama pull
ollama rm

# [Docker engine]
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo groupadd docker

sudo usermod -aG docker $USER

# [Other deps]
sudo apt update
sudo apt install libgl1-mesa-dev libglu1-mesa-dev libx11-dev libxcursor-dev libxinerama-dev libxrandr-dev libxi-dev

# Container
## Portainer
docker volume create portainer_data
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:sts
## Redis-stack
docker run -d --name redis-stack \
  -p 6379:6379 \
  -p 8001:8001 \
  --restart always \
  redis/redis-stack:7.4.0-v8-x86_64
## Neo4j
docker run \
    --name my-neo4j \
    -p 7474:7474 -p 7687:7687 \
    -v $HOME/neo4j/data:/data \
    --env NEO4J_AUTH=neo4j/12345678 \
    --restart always \
    -d \
    neo4j:5.26.25-community-trixie
