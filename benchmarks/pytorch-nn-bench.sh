#!/bin/bash
# PyTorch Neural Network Throughput Benchmark
# Tests real NN architectures using pure PyTorch (no torchvision dependency)

set -e

IMAGE="${1:-softab:pytorch-fedora-rocm}"
BATCH_SIZE="${2:-32}"
PYTHON="${PYTHON:-python3.12}"

echo "=== PyTorch Neural Network Benchmark ==="
echo "Image: $IMAGE"
echo "Batch Size: $BATCH_SIZE"
echo ""

podman run --rm \
    --device=/dev/kfd --device=/dev/dri \
    --ipc=host \
    --security-opt seccomp=unconfined \
    --security-opt label=disable \
    -e ROCBLAS_USE_HIPBLASLT="${ROCBLAS_USE_HIPBLASLT:-0}" \
    "$IMAGE" \
    $PYTHON << 'PYTHON_EOF'
import torch
import torch.nn as nn
import time
import json
import sys
from datetime import datetime

BATCH_SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 32
WARMUP = 10
ITERATIONS = 50

device = torch.device('cuda')
props = torch.cuda.get_device_properties(0)

print(f"Device: {props.name}")
print(f"GFX: {props.gcnArchName}")
print(f"PyTorch: {torch.__version__}")
print(f"ROCm: {torch.version.hip}")
print(f"Batch Size: {BATCH_SIZE}")
print("")

results = {
    "timestamp": datetime.now().isoformat(),
    "device": props.name,
    "gfx": props.gcnArchName,
    "pytorch": torch.__version__,
    "rocm": str(torch.version.hip),
    "batch_size": BATCH_SIZE,
    "benchmarks": {}
}

def benchmark_model(name, model, input_shape, dtype=torch.float16):
    """Benchmark forward pass throughput"""
    model = model.to(device).to(dtype).eval()
    x = torch.randn(*input_shape, dtype=dtype, device=device)

    # Warmup
    with torch.no_grad():
        for _ in range(WARMUP):
            _ = model(x)
    torch.cuda.synchronize()

    # Benchmark
    start = time.perf_counter()
    with torch.no_grad():
        for _ in range(ITERATIONS):
            _ = model(x)
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    throughput = (BATCH_SIZE * ITERATIONS) / elapsed
    latency_ms = (elapsed / ITERATIONS) * 1000

    del model, x
    torch.cuda.empty_cache()

    return throughput, latency_ms

# --- ResNet-50 (pure PyTorch implementation) ---
class BasicBlock(nn.Module):
    expansion = 1
    def __init__(self, in_planes, planes, stride=1):
        super().__init__()
        self.conv1 = nn.Conv2d(in_planes, planes, 3, stride=stride, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(planes)
        self.conv2 = nn.Conv2d(planes, planes, 3, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(planes)
        self.shortcut = nn.Sequential()
        if stride != 1 or in_planes != planes * self.expansion:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_planes, planes * self.expansion, 1, stride=stride, bias=False),
                nn.BatchNorm2d(planes * self.expansion)
            )
    def forward(self, x):
        out = torch.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        out += self.shortcut(x)
        return torch.relu(out)

class Bottleneck(nn.Module):
    expansion = 4
    def __init__(self, in_planes, planes, stride=1):
        super().__init__()
        self.conv1 = nn.Conv2d(in_planes, planes, 1, bias=False)
        self.bn1 = nn.BatchNorm2d(planes)
        self.conv2 = nn.Conv2d(planes, planes, 3, stride=stride, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(planes)
        self.conv3 = nn.Conv2d(planes, planes * self.expansion, 1, bias=False)
        self.bn3 = nn.BatchNorm2d(planes * self.expansion)
        self.shortcut = nn.Sequential()
        if stride != 1 or in_planes != planes * self.expansion:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_planes, planes * self.expansion, 1, stride=stride, bias=False),
                nn.BatchNorm2d(planes * self.expansion)
            )
    def forward(self, x):
        out = torch.relu(self.bn1(self.conv1(x)))
        out = torch.relu(self.bn2(self.conv2(out)))
        out = self.bn3(self.conv3(out))
        out += self.shortcut(x)
        return torch.relu(out)

class ResNet(nn.Module):
    def __init__(self, block, num_blocks, num_classes=1000):
        super().__init__()
        self.in_planes = 64
        self.conv1 = nn.Conv2d(3, 64, 7, stride=2, padding=3, bias=False)
        self.bn1 = nn.BatchNorm2d(64)
        self.maxpool = nn.MaxPool2d(3, stride=2, padding=1)
        self.layer1 = self._make_layer(block, 64, num_blocks[0], stride=1)
        self.layer2 = self._make_layer(block, 128, num_blocks[1], stride=2)
        self.layer3 = self._make_layer(block, 256, num_blocks[2], stride=2)
        self.layer4 = self._make_layer(block, 512, num_blocks[3], stride=2)
        self.avgpool = nn.AdaptiveAvgPool2d((1, 1))
        self.fc = nn.Linear(512 * block.expansion, num_classes)

    def _make_layer(self, block, planes, num_blocks, stride):
        strides = [stride] + [1] * (num_blocks - 1)
        layers = []
        for stride in strides:
            layers.append(block(self.in_planes, planes, stride))
            self.in_planes = planes * block.expansion
        return nn.Sequential(*layers)

    def forward(self, x):
        out = torch.relu(self.bn1(self.conv1(x)))
        out = self.maxpool(out)
        out = self.layer1(out)
        out = self.layer2(out)
        out = self.layer3(out)
        out = self.layer4(out)
        out = self.avgpool(out)
        out = out.view(out.size(0), -1)
        return self.fc(out)

def ResNet50():
    return ResNet(Bottleneck, [3, 4, 6, 3])

def ResNet18():
    return ResNet(BasicBlock, [2, 2, 2, 2])

# --- VGG-16 ---
class VGG16(nn.Module):
    def __init__(self, num_classes=1000):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(3, 64, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(64, 64, 3, padding=1), nn.ReLU(inplace=True),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(64, 128, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(128, 128, 3, padding=1), nn.ReLU(inplace=True),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(128, 256, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(256, 256, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(256, 256, 3, padding=1), nn.ReLU(inplace=True),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(256, 512, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(512, 512, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(512, 512, 3, padding=1), nn.ReLU(inplace=True),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(512, 512, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(512, 512, 3, padding=1), nn.ReLU(inplace=True),
            nn.Conv2d(512, 512, 3, padding=1), nn.ReLU(inplace=True),
            nn.MaxPool2d(2, 2),
        )
        self.classifier = nn.Sequential(
            nn.Linear(512 * 7 * 7, 4096), nn.ReLU(inplace=True), nn.Dropout(),
            nn.Linear(4096, 4096), nn.ReLU(inplace=True), nn.Dropout(),
            nn.Linear(4096, num_classes),
        )
    def forward(self, x):
        x = self.features(x)
        x = x.view(x.size(0), -1)
        return self.classifier(x)

# --- Vision Transformer (ViT-B/16) ---
class PatchEmbed(nn.Module):
    def __init__(self, img_size=224, patch_size=16, in_chans=3, embed_dim=768):
        super().__init__()
        self.proj = nn.Conv2d(in_chans, embed_dim, patch_size, stride=patch_size)
    def forward(self, x):
        return self.proj(x).flatten(2).transpose(1, 2)

class ViT(nn.Module):
    def __init__(self, img_size=224, patch_size=16, in_chans=3, num_classes=1000,
                 embed_dim=768, depth=12, num_heads=12, mlp_ratio=4.0):
        super().__init__()
        self.patch_embed = PatchEmbed(img_size, patch_size, in_chans, embed_dim)
        num_patches = (img_size // patch_size) ** 2
        self.cls_token = nn.Parameter(torch.zeros(1, 1, embed_dim))
        self.pos_embed = nn.Parameter(torch.zeros(1, num_patches + 1, embed_dim))
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=embed_dim, nhead=num_heads,
            dim_feedforward=int(embed_dim * mlp_ratio),
            batch_first=True, norm_first=True
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=depth)
        self.norm = nn.LayerNorm(embed_dim)
        self.head = nn.Linear(embed_dim, num_classes)

    def forward(self, x):
        x = self.patch_embed(x)
        cls_tokens = self.cls_token.expand(x.shape[0], -1, -1)
        x = torch.cat((cls_tokens, x), dim=1)
        x = x + self.pos_embed
        x = self.encoder(x)
        x = self.norm(x[:, 0])
        return self.head(x)

# --- BERT-style Encoder ---
class BERTEncoder(nn.Module):
    def __init__(self, vocab_size=30522, hidden_size=768, num_layers=12, num_heads=12):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, hidden_size)
        self.pos_embedding = nn.Embedding(512, hidden_size)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=hidden_size, nhead=num_heads,
            dim_feedforward=hidden_size * 4, batch_first=True
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.norm = nn.LayerNorm(hidden_size)

    def forward(self, x):
        seq_len = x.shape[1]
        pos = torch.arange(seq_len, device=x.device).unsqueeze(0)
        x = self.embedding(x) + self.pos_embedding(pos)
        x = self.encoder(x)
        return self.norm(x)

# --- GPT-2 style Decoder ---
class GPT2Decoder(nn.Module):
    def __init__(self, vocab_size=50257, hidden_size=1024, num_layers=24, num_heads=16):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, hidden_size)
        self.pos_embedding = nn.Embedding(1024, hidden_size)
        decoder_layer = nn.TransformerEncoderLayer(  # GPT uses encoder-style (no cross-attn)
            d_model=hidden_size, nhead=num_heads,
            dim_feedforward=hidden_size * 4, batch_first=True
        )
        self.decoder = nn.TransformerEncoder(decoder_layer, num_layers=num_layers)
        self.norm = nn.LayerNorm(hidden_size)
        self.lm_head = nn.Linear(hidden_size, vocab_size, bias=False)

    def forward(self, x):
        seq_len = x.shape[1]
        pos = torch.arange(seq_len, device=x.device).unsqueeze(0)
        x = self.embedding(x) + self.pos_embedding(pos)
        # Causal mask
        mask = nn.Transformer.generate_square_subsequent_mask(seq_len, device=x.device)
        x = self.decoder(x, mask=mask, is_causal=True)
        return self.lm_head(self.norm(x))


# ============ RUN BENCHMARKS ============

print("=" * 50)
print("VISION MODELS (batch={}, 224x224 RGB)".format(BATCH_SIZE))
print("=" * 50)

# ResNet-18
print("\nResNet-18...")
try:
    model = ResNet18()
    throughput, latency = benchmark_model("resnet18", model, (BATCH_SIZE, 3, 224, 224))
    print(f"  Throughput: {throughput:.1f} img/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["resnet18"] = {"throughput_img_s": throughput, "latency_ms": latency}
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["resnet18"] = {"error": str(e)}

# ResNet-50
print("\nResNet-50...")
try:
    model = ResNet50()
    throughput, latency = benchmark_model("resnet50", model, (BATCH_SIZE, 3, 224, 224))
    print(f"  Throughput: {throughput:.1f} img/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["resnet50"] = {"throughput_img_s": throughput, "latency_ms": latency}
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["resnet50"] = {"error": str(e)}

# VGG-16
print("\nVGG-16...")
try:
    model = VGG16()
    throughput, latency = benchmark_model("vgg16", model, (BATCH_SIZE, 3, 224, 224))
    print(f"  Throughput: {throughput:.1f} img/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["vgg16"] = {"throughput_img_s": throughput, "latency_ms": latency}
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["vgg16"] = {"error": str(e)}

# ViT-B/16
print("\nViT-B/16...")
try:
    model = ViT()
    throughput, latency = benchmark_model("vit_b_16", model, (BATCH_SIZE, 3, 224, 224))
    print(f"  Throughput: {throughput:.1f} img/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["vit_b_16"] = {"throughput_img_s": throughput, "latency_ms": latency}
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["vit_b_16"] = {"error": str(e)}

print("")
print("=" * 50)
print("LANGUAGE MODELS (batch={})".format(BATCH_SIZE))
print("=" * 50)

# BERT-base (seq=128)
print("\nBERT-base (seq=128)...")
try:
    model = BERTEncoder()
    input_ids = torch.randint(0, 30522, (BATCH_SIZE, 128), device=device)

    model = model.to(device).to(torch.float16).eval()
    for _ in range(WARMUP):
        with torch.no_grad():
            _ = model(input_ids)
    torch.cuda.synchronize()

    start = time.perf_counter()
    with torch.no_grad():
        for _ in range(ITERATIONS):
            _ = model(input_ids)
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    throughput = (BATCH_SIZE * ITERATIONS) / elapsed
    latency = (elapsed / ITERATIONS) * 1000
    print(f"  Throughput: {throughput:.1f} seq/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["bert_base_128"] = {"throughput_seq_s": throughput, "latency_ms": latency}
    del model
    torch.cuda.empty_cache()
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["bert_base_128"] = {"error": str(e)}

# BERT-base (seq=512)
print("\nBERT-base (seq=512)...")
try:
    model = BERTEncoder()
    input_ids = torch.randint(0, 30522, (BATCH_SIZE, 512), device=device)

    model = model.to(device).to(torch.float16).eval()
    for _ in range(WARMUP):
        with torch.no_grad():
            _ = model(input_ids)
    torch.cuda.synchronize()

    start = time.perf_counter()
    with torch.no_grad():
        for _ in range(ITERATIONS):
            _ = model(input_ids)
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    throughput = (BATCH_SIZE * ITERATIONS) / elapsed
    latency = (elapsed / ITERATIONS) * 1000
    print(f"  Throughput: {throughput:.1f} seq/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["bert_base_512"] = {"throughput_seq_s": throughput, "latency_ms": latency}
    del model
    torch.cuda.empty_cache()
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["bert_base_512"] = {"error": str(e)}

# GPT-2 Medium (seq=512)
print("\nGPT-2 Medium (seq=512)...")
try:
    model = GPT2Decoder()
    input_ids = torch.randint(0, 50257, (BATCH_SIZE, 512), device=device)

    model = model.to(device).to(torch.float16).eval()
    for _ in range(WARMUP):
        with torch.no_grad():
            _ = model(input_ids)
    torch.cuda.synchronize()

    start = time.perf_counter()
    with torch.no_grad():
        for _ in range(ITERATIONS):
            _ = model(input_ids)
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    throughput = (BATCH_SIZE * ITERATIONS) / elapsed
    latency = (elapsed / ITERATIONS) * 1000
    print(f"  Throughput: {throughput:.1f} seq/s")
    print(f"  Latency:    {latency:.2f} ms/batch")
    results["benchmarks"]["gpt2_medium_512"] = {"throughput_seq_s": throughput, "latency_ms": latency}
    del model
    torch.cuda.empty_cache()
except Exception as e:
    print(f"  FAILED: {e}")
    results["benchmarks"]["gpt2_medium_512"] = {"error": str(e)}

print("")
print("=" * 50)
print("JSON RESULTS")
print("=" * 50)
print(json.dumps(results, indent=2))
PYTHON_EOF

echo ""
echo "=== Benchmark Complete ==="
