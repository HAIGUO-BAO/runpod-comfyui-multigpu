#!/bin/bash
# ComfyUI Multi-GPU 启动脚本（安全版本）
# 方案A：不自动创建模型目录，避免数据丢失风险

set -e

echo "========================================"
echo "🎨 ComfyUI Multi-GPU 启动脚本"
echo "========================================"

# 1. 基础信息
echo "📅 时间: $(date)"
echo "📦 工作目录: /workspace"

# 2. 显示GPU信息
echo "🔍 检测GPU..."
if command -v nvidia-smi &> /dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1 | sed 's/ MiB//')
    echo "🎮 GPU: $GPU_NAME"
    echo "💾 显存: $GPU_MEMORY MB"
else
    echo "❌ 未检测到GPU，请检查NVIDIA驱动"
fi

# 3. 安装基础依赖
echo "📦 安装基础依赖..."
cd /workspace

# 3.1 克隆ComfyUI
if [ ! -d "/workspace/ComfyUI" ]; then
    echo "克隆ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
else
    echo "✅ ComfyUI已存在，跳过克隆"
fi

# 3.2 安装Python依赖
cd /workspace/ComfyUI
echo "安装Python依赖..."
pip install --upgrade pip 2>/dev/null | grep -v "already up-to-date" || true
pip install -r requirements.txt 2>&1 | grep -v "already satisfied" || true

# 3.3 安装额外依赖
echo "安装额外依赖..."
pip install insightface onnxruntime-gpu opencv-python pillow-avif-plugin 2>&1 | grep -v "already satisfied" || true

# 4. GPU优化配置
echo "🔧 GPU优化配置..."

# 检测CUDA可用性
if python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null | grep -q "True"; then
    echo "✅ CUDA可用，使用GPU加速"
    
    # 根据GPU类型设置参数
    if [[ "$GPU_NAME" == *"4090"* ]]; then
        echo "⚡ RTX 4090优化模式"
        COMFYUI_ARGS="--highvram --force-fp16"
    elif [[ "$GPU_NAME" == *"3090"* ]]; then
        echo "⚡ RTX 3090优化模式"
        COMFYUI_ARGS="--highvram --force-fp16"
    elif [[ "$GPU_NAME" == *"6000"* ]]; then
        echo "⚡ RTX 6000优化模式"
        COMFYUI_ARGS="--highvram --gpu-only --force-fp16"
    elif [ "$GPU_MEMORY" -ge 24000 ] 2>/dev/null; then
        echo "⚡ 高显存模式 (24GB+)"
        COMFYUI_ARGS="--highvram --force-fp16"
    elif [ "$GPU_MEMORY" -ge 16000 ] 2>/dev/null; then
        echo "⚡ 普通模式 (16GB+)"
        COMFYUI_ARGS="--normalvram"
    elif [ "$GPU_MEMORY" -ge 8000 ] 2>/dev/null; then
        echo "⚡ 低显存模式 (8GB+)"
        COMFYUI_ARGS="--lowvram"
    else
        echo "⚡ 最低配置模式"
        COMFYUI_ARGS="--lowvram --cpu"
    fi
else
    echo "⚠️  CUDA不可用，使用CPU模式"
    COMFYUI_ARGS="--cpu"
fi

# 基础参数
COMFYUI_ARGS="--port 8188 --listen 0.0.0.0 --preview-method auto --disable-auto-launch --max-upload-size 200 $COMFYUI_ARGS"

echo "启动参数: $COMFYUI_ARGS"

# 5. 安装和启动FileBrowser
echo "🌐 安装FileBrowser..."
if ! command -v filebrowser &> /dev/null; then
    wget -q https://github.com/filebrowser/filebrowser/releases/download/v2.27.0/linux-amd64-filebrowser.tar.gz
    tar -xzf linux-amd64-filebrowser.tar.gz
    mv filebrowser /usr/local/bin/
    rm linux-amd64-filebrowser.tar.gz
    echo "✅ FileBrowser安装完成"
else
    echo "✅ FileBrowser已安装"
fi

# 启动FileBrowser
echo "启动FileBrowser..."
pkill -f filebrowser 2>/dev/null || true

# 初始化配置
filebrowser config init --port 8080 --address 0.0.0.0 --database /workspace/.filebrowser.db --root /workspace >/dev/null 2>&1 || true
filebrowser users add admin admin --perm.admin >/dev/null 2>&1 || true

# 后台运行
nohup filebrowser --port 8080 --address 0.0.0.0 --database /workspace/.filebrowser.db --root /workspace > /tmp/filebrowser.log 2>&1 &
echo "✅ FileBrowser已启动 (端口: 8080)"

# 6. 启动ComfyUI
echo "🎨 启动ComfyUI..."
cd /workspace/ComfyUI

# 检查模型目录并给出提示
if [ ! -d "models" ]; then
    echo ""
    echo "⚠️  ⚠️  ⚠️  重要提示 ⚠️  ⚠️  ⚠️"
    echo "模型目录不存在: /workspace/ComfyUI/models"
    echo "请通过以下方式创建："
    echo "1. 访问 FileBrowser: http://<POD_IP>:8080"
    echo "2. 创建目录: ComfyUI/models/"
    echo "3. 创建子目录: checkpoints, loras, embeddings, vae 等"
    echo "4. 上传模型文件到对应目录"
    echo ""
    echo "继续启动ComfyUI，但可能需要手动创建模型目录..."
fi

# 后台运行ComfyUI
nohup python main.py $COMFYUI_ARGS > /tmp/comfyui.log 2>&1 &
COMFLYUI_PID=$!

# 7. 等待启动完成
echo "等待服务启动..."
sleep 10

# 8. 显示服务状态
echo ""
echo "========================================"
echo "✅ 服务启动完成"
echo "========================================"

# 检查服务状态
echo "📊 服务状态检查:"
echo "----------------------------------------"

# 检查端口监听
echo "端口监听:"
if ss -tulpn 2>/dev/null | grep -q ":8188"; then
    echo "  ✅ ComfyUI: 8188 端口正常"
else
    echo "  ⚠️  ComfyUI: 8188 端口未监听"
fi

if ss -tulpn 2>/dev/null | grep -q ":8080"; then
    echo "  ✅ FileBrowser: 8080 端口正常"
else
    echo "  ⚠️  FileBrowser: 8080 端口未监听"
fi

echo "----------------------------------------"

# 显示访问信息
echo "🔗 访问地址:"
echo "  ComfyUI:     https://${RUNPOD_PUBLIC_IP:-<POD_IP>}-8188.proxy.runpod.net"
echo "  FileBrowser: https://${RUNPOD_PUBLIC_IP:-<POD_IP>}-8080.proxy.runpod.net"
echo "  FileBrowser 账号: admin / 密码: admin"

echo "----------------------------------------"

# 显示模型目录状态
echo "📁 模型目录状态:"
MODEL_BASE="/workspace/ComfyUI/models"
if [ -d "$MODEL_BASE" ]; then
    echo "  ✅ 模型目录存在: $MODEL_BASE"
    echo "  子目录:"
    for dir in checkpoints loras embeddings vae upscale_models controlnet; do
        if [ -d "$MODEL_BASE/$dir" ]; then
            count=$(find "$MODEL_BASE/$dir" -type f 2>/dev/null | wc -l)
            echo "    - $dir: $count 个文件"
        else
            echo "    - $dir: ❌ 不存在"
        fi
    done
else
    echo "  ❌ 模型目录不存在: $MODEL_BASE"
    echo "  请通过FileBrowser创建!"
fi

echo "----------------------------------------"

# 显示重要提示
echo "📝 重要提示:"
echo "1. 首次使用时，请通过FileBrowser创建模型目录"
echo "2. 模型目录结构:"
echo "   /workspace/ComfyUI/models/checkpoints    - 大模型"
echo "   /workspace/ComfyUI/models/loras          - LoRA模型"
echo "   /workspace/ComfyUI/models/embeddings     - 嵌入模型"
echo "   /workspace/ComfyUI/models/vae            - VAE模型"
echo "   /workspace/ComfyUI/models/upscale_models - 超分模型"
echo "   /workspace/ComfyUI/models/controlnet     - ControlNet模型"
echo ""
echo "3. 上传模型后，可能需要重启ComfyUI"
echo "   重启命令: pkill -f 'python main.py' && cd /workspace/ComfyUI && python main.py $COMFYUI_ARGS"

echo "----------------------------------------"

# 显示日志查看命令
echo "📋 日志查看:"
echo "  ComfyUI日志: tail -f /tmp/comfyui.log"
echo "  FileBrowser日志: tail -f /tmp/filebrowser.log"
echo "  GPU状态: watch -n 1 nvidia-smi"

echo "========================================"

# 9. 保持容器运行
echo ""
echo "🔄 容器持续运行中..."
echo "按 Ctrl+C 停止服务"

# 监控进程，如果ComfyUI退出则重启
while true; do
    if ! kill -0 $COMFLYUI_PID 2>/dev/null; then
        echo "ComfyUI进程已停止，正在重启..."
        cd /workspace/ComfyUI
        nohup python main.py $COMFYUI_ARGS > /tmp/comfyui.log 2>&1 &
        COMFLYUI_PID=$!
        echo "✅ ComfyUI已重启 (PID: $COMFLYUI_PID)"
    fi
    sleep 30
done
