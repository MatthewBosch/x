set -euo pipefail

pause () {
  echo
  echo "=============================="
  echo "DONE: $1"
  echo "Press ENTER to continue..."
  echo "=============================="
  read -r
}


# ========= [A] 基础仓库 =========
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y restricted || true
sudo add-apt-repository -y multiverse || true
sudo apt-get update
pause "A) base repos ready"

# ========= [B] 清理 CUDA repo/keyring 冲突 =========
sudo rm -f /etc/apt/sources.list.d/nvidia-cuda.list || true
sudo rm -f /etc/apt/sources.list.d/cuda*.list || true
sudo rm -f /usr/share/keyrings/nvidia-cuda.gpg || true
sudo apt-get update
pause "B) cleaned duplicated CUDA repo/keyring"

# ========= [C] 安装 570 driver + fabric（对齐版本） =========
DRIVER_VER="570.195.03-0ubuntu0.24.04.1"
FM_VER="570.195.03-0ubuntu0.24.04.2"

sudo apt-get install -y \
  "nvidia-driver-570=${DRIVER_VER}" \
  "nvidia-utils-570=${DRIVER_VER}" \
  "nvidia-compute-utils-570=${DRIVER_VER}" \
  "libnvidia-compute-570=${DRIVER_VER}" \
  "libnvidia-gl-570=${DRIVER_VER}" \
  "libnvidia-extra-570=${DRIVER_VER}" \
  "libnvidia-decode-570=${DRIVER_VER}" \
  "libnvidia-encode-570=${DRIVER_VER}" \
  "libnvidia-cfg1-570=${DRIVER_VER}" \
  "xserver-xorg-video-nvidia-570=${DRIVER_VER}" \
  "nvidia-fabricmanager-570=${FM_VER}"

sudo systemctl enable --now nvidia-fabricmanager
sudo systemctl status nvidia-fabricmanager --no-pager || true
pause "C) driver+fabric installed & fabric running"

# （强烈建议此处重启一次，尤其新装驱动时）
# sudo reboot

# ========= [D] CUDA 12.8 toolkit/runtime（不碰驱动） =========
cd /tmp
curl -fsSLO https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb

cat <<'EOF' | sudo tee /etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list >/dev/null
deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /
EOF

sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-8 cuda-cudart-12-8
pause "D) cuda 12.8 toolkit+cudart installed"

# ========= [E] Docker + NVIDIA Container Toolkit =========
sudo apt-get install -y ca-certificates curl gnupg
sudo apt-get install -y docker.io
sudo systemctl enable --now docker

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
pause "E) docker+nvidia-container-toolkit ready"

# ========= [F] venv + torch（只影响 host，不影响 docker） =========
sudo apt-get install -y python3-venv python3-pip
python3 -m venv /opt/torch-venv
/opt/torch-venv/bin/python -m pip install -U pip setuptools wheel numpy
/opt/torch-venv/bin/pip install --index-url https://download.pytorch.org/whl/cu124 torch
pause "F) host venv torch installed"

# ========= [G] 验证 =========
nvidia-smi
/opt/torch-venv/bin/python - <<'PY'
import torch
print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())
print("gpu count:", torch.cuda.device_count())
if torch.cuda.is_available():
    print("gpu0:", torch.cuda.get_device_name(0))
PY

docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
pause "G) validation done"
