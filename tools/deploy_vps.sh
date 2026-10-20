#!/usr/bin/env bash
# KONG 联机部署脚本：在 Ubuntu VPS 上装依赖/Godot、拉代码、起 目录+专用服务器、开防火墙。
# 幂等，可重复执行。在 VPS 上运行：
#   bash deploy_vps.sh
# 可覆盖：
#   REPO=... BRANCH=... GAME_PORT=7007 DIR_PORT=8080 ACCOUNT_PORT=8090 ADVERTISE=<公网IP> bash deploy_vps.sh
set -euo pipefail

REPO="${REPO:-https://github.com/XiShaoDong/Cambio-Rouglike.git}"
BRANCH="${BRANCH:-agent/feature-online}"
GAME_PORT="${GAME_PORT:-7007}"
DIR_PORT="${DIR_PORT:-8080}"
ACCOUNT_PORT="${ACCOUNT_PORT:-8090}"
ADVERTISE="${ADVERTISE:-129.213.203.137}"
ROOM_CODE="${ROOM_CODE:-KONG}"
APP_DIR="${APP_DIR:-$HOME/kong}"
GODOT_VER="${GODOT_VER:-4.6.2-stable}"
GODOT_BIN="/usr/local/bin/godot"

log() { printf '\n[deploy] %s\n' "$*"; }

log "1/6 安装系统依赖"
sudo apt-get update -y
sudo apt-get install -y python3 git unzip curl libfontconfig1

log "2/6 安装 Godot ${GODOT_VER}（linux.x86_64）"
if ! command -v godot >/dev/null 2>&1; then
  sudo mkdir -p /opt/godot
  cd /opt/godot
  URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"
  sudo curl -fL -o godot.zip "$URL"
  sudo unzip -o godot.zip
  sudo chmod +x Godot_v${GODOT_VER}_linux.x86_64
  sudo ln -sf /opt/godot/Godot_v${GODOT_VER}_linux.x86_64 "$GODOT_BIN"
fi
godot --version || true

log "3/6 拉取/更新代码到 $APP_DIR（分支 $BRANCH）"
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch --all
  # 先丢弃上一次部署对 project.godot 的本地改动（剥离 MCP），避免 pull 冲突
  git -C "$APP_DIR" checkout -- project.godot 2>/dev/null || true
  git -C "$APP_DIR" checkout "$BRANCH"
  git -C "$APP_DIR" pull --ff-only || true
else
  git clone "$REPO" "$APP_DIR"
  git -C "$APP_DIR" checkout "$BRANCH"
fi

log "4/6 首次导入 Godot 资源（headless）"
# 服务器/部署机不需要 MCP 编辑器插件：它 auto_start 一个 HTTP 服务，会让 headless
# 的 --import（会加载编辑器）不退出而“卡住”。这里在部署副本中剥离该插件与其 autoload。
cd "$APP_DIR"
if grep -q 'godot_mcp\|MCPRuntimeProbe' project.godot; then
  sed -i '/godot_mcp/d' project.godot
  sed -i '/MCPRuntimeProbe/d' project.godot
  echo "[deploy] 已从 project.godot 剥离 MCP 编辑器插件/autoload（部署机不需要）"
fi
# 类缓存：服务器只需脚本的 class_name 解析，不需要逐个导入美术资源。
# 小机器上 `--import`（会加载整个编辑器）极慢甚至超时，故直接用仓库内预生成的类缓存。
mkdir -p .godot
if [ -f deploy/godot_global_script_class_cache.cfg ]; then
  cp deploy/godot_global_script_class_cache.cfg .godot/global_script_class_cache.cfg
  echo "[deploy] 已放置预生成类缓存"
fi
echo "[deploy] 类缓存检查：$(grep -c DirectoryClient .godot/global_script_class_cache.cfg 2>/dev/null) 处 DirectoryClient"
# 需要完整美术导入时（例如跑 Linux 客户端）设 FULL_IMPORT=1 再跑本脚本：
if [ "${FULL_IMPORT:-0}" = "1" ]; then
  echo "[deploy] FULL_IMPORT=1 → 执行完整导入（较慢）"
  timeout 1800 godot --headless --import || echo "[deploy] import 超时/出错，继续"
fi

log "5/6 安装 systemd 服务（目录 + 专用服务器）"
sudo tee /etc/systemd/system/kong-directory.service >/dev/null <<EOF
[Unit]
Description=KONG Directory Service
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR/server/directory
ExecStart=/usr/bin/python3 $APP_DIR/server/directory/directory.py --port $DIR_PORT --advertise-host $ADVERTISE
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/kong-server.service >/dev/null <<EOF
[Unit]
Description=KONG Dedicated Server
After=network-online.target kong-directory.service
Wants=network-online.target
Requires=kong-directory.service

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$GODOT_BIN --headless --path . res://scenes/server.tscn -- --port $GAME_PORT --directory http://127.0.0.1:$DIR_PORT --advertise $ADVERTISE --code $ROOM_CODE
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 重启服务并校验"真的换了进程"：某些情况下 restart 可能未生效，则强制 stop/start。
restart_service() {
  local svc="$1"
  local pid_before pid_after
  pid_before="$(systemctl show -p MainPID --value "$svc" 2>/dev/null || echo 0)"
  sudo systemctl restart "$svc" || true
  sleep 2
  pid_after="$(systemctl show -p MainPID --value "$svc" 2>/dev/null || echo 0)"
  if [ "$pid_after" = "0" ] || [ "$pid_after" = "$pid_before" ]; then
    echo "[deploy] $svc 重启未生效（pid $pid_before → $pid_after），强制 stop/start"
    sudo systemctl reset-failed "$svc" 2>/dev/null || true
    sudo systemctl stop "$svc" 2>/dev/null || true
    sleep 1
    sudo systemctl start "$svc" || true
    sleep 2
    pid_after="$(systemctl show -p MainPID --value "$svc" 2>/dev/null || echo 0)"
  fi
  echo "[deploy] $svc pid=$pid_after"
}

sudo systemctl daemon-reload
sudo systemctl enable kong-directory.service kong-server.service
restart_service kong-directory.service
restart_service kong-server.service

log "6/6 防火墙（iptables，兼容 Oracle 自带规则）"
# Oracle Ubuntu 镜像自带 iptables REJECT 规则，ufw 未必生效；直接插 ACCEPT 并持久化。
add_ipt() { # proto port
  if ! sudo iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT -p "$1" --dport "$2" -j ACCEPT
  fi
}
add_ipt tcp "$DIR_PORT"
add_ipt udp "$GAME_PORT"
add_ipt tcp "$ACCOUNT_PORT"
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save || true
elif command -v iptables-save >/dev/null 2>&1; then
  sudo mkdir -p /etc/iptables
  sudo sh -c 'iptables-save > /etc/iptables/rules.v4' || true
fi
# 若系统用 ufw，也一并放行（幂等）
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow ${DIR_PORT}/tcp || true
  sudo ufw allow ${GAME_PORT}/udp || true
  sudo ufw allow ${ACCOUNT_PORT}/tcp || true
fi

log "完成。状态："
systemctl --no-pager --lines=0 status kong-directory.service || true
systemctl --no-pager --lines=0 status kong-server.service || true

log "房间码（等几秒让服务器登记后再看）："
sleep 4
sudo journalctl -u kong-server.service --no-pager -n 20 | grep -E 'room code|listening|directory' || true

cat <<EOF

==== 下一步（务必做）====
1) Oracle 控制台 Security List 放行入方向：UDP $GAME_PORT、TCP $DIR_PORT（可选 TCP $ACCOUNT_PORT）。
2) 本机自测：  curl http://$ADVERTISE:$DIR_PORT/health   → {"ok":true,...}
3) 房间码见上：journalctl -u kong-server -f
4) 朋友端：设置→目录地址 = http://$ADVERTISE:$DIR_PORT ，再输房间码加入。
EOF
