# Reference server setup: Canary-Qwen 2.5B on Linux + RTX 4080

This is the original VoiceRider development server. It ran on Linux Mint
with an RTX 4080 (16 GB VRAM) and weights stored on a 1 TB SSD mounted
at `/mnt/1tbssd/`. The instructions below assume that exact setup; if
your paths or distro differ, adjust accordingly — only the protocol
matters to VoiceRider, not the path layout.

> **This document is a snapshot of one working setup, not a polished
> production deployment guide.** Read [README → Server protocol](../README.md#server-protocol)
> first to decide whether you want to run NeMo locally or use a
> simpler alternative server.

---

## 1. Hard requirements

| Requirement | Why | Check |
|---|---|---|
| NVIDIA driver ≥550 | bf16 + CUDA 12.4 wheels | `nvidia-smi` reports CUDA 12.4+ |
| CUDA-capable PyTorch | bf16 inference on RTX 4080 | covered by `cu124` pip wheels in step 4 |
| ≥30 GB free disk | weights + Python deps | `df -h /mnt/1tbssd` |
| Python 3.10 or 3.11 | NeMo 2.x ceiling | `python3 --version` |

If `python3` is 3.12+, install 3.11 via deadsnakes:

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3.11-dev
```

## 2. System packages

```bash
sudo apt update
sudo apt install -y build-essential git curl ffmpeg libsndfile1 \
                    python3-pip python3-venv pkg-config
```

## 3. Directory layout

The reference server pins everything to `/mnt/1tbssd/` (a fast SSD mount
that isn't `$HOME`). Substitute your own path; the rest of this doc
assumes the original layout.

```bash
sudo mkdir -p /mnt/1tbssd/models /mnt/1tbssd/git
sudo chown -R "$USER:$USER" /mnt/1tbssd/models /mnt/1tbssd/git
mkdir -p /mnt/1tbssd/git/canary-server
cd /mnt/1tbssd/git/canary-server
```

## 4. Python virtualenv + dependencies

```bash
python3.11 -m venv .venv         # or: python3 -m venv .venv  (if 3.11 is default)
source .venv/bin/activate
pip install --upgrade pip wheel setuptools

# PyTorch with CUDA 12.4 (matches RTX 4080 + driver 550+)
pip install torch==2.4.1 torchaudio==2.4.1 \
    --index-url https://download.pytorch.org/whl/cu124

# NeMo toolkit (ASR + SpeechLM2 for Canary-Qwen).
# Cython<3 must be present BEFORE the nemo install.
pip install "cython<3" packaging
pip install "nemo_toolkit[asr]==2.0.0"
pip install lhotse

# API server + audio I/O
pip install fastapi==0.115.0 uvicorn[standard]==0.30.6 \
            python-multipart==0.0.9 \
            soundfile==0.12.1 librosa==0.10.2 numpy==1.26.4 \
            huggingface_hub==0.25.2

# CUDA sanity check
python -c "import torch; print('cuda?', torch.cuda.is_available(), torch.cuda.get_device_name(0))"
# expect: cuda? True NVIDIA GeForce RTX 4080
```

## 5. Download the model

Pin the Hugging Face cache to the SSD so weights don't end up under
`$HOME`:

```bash
export HF_HOME=/mnt/1tbssd/models/hf-cache
mkdir -p "$HF_HOME"
echo 'export HF_HOME=/mnt/1tbssd/models/hf-cache' >> ~/.bashrc

huggingface-cli download nvidia/canary-qwen-2.5b \
    --local-dir /mnt/1tbssd/models/canary-qwen-2.5b \
    --local-dir-use-symlinks False

ls -lh /mnt/1tbssd/models/canary-qwen-2.5b
# Should contain config.yaml + .nemo / weight shards (~10 GB)
```

The model card on Hugging Face confirms: input must be 16 kHz mono;
the official inference path uses
`SALM.from_pretrained` and `model.generate` with a prompt that
embeds `model.audio_locator_tag`.

## 6. The server

Full server source lives at `/mnt/1tbssd/git/canary-server/server.py`.
The complete file:

```python
import os
import tempfile
import logging
from typing import Optional

import torch
import soundfile as sf
import librosa
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse, PlainTextResponse
import uvicorn

from nemo.collections.speechlm2.models import SALM

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("canary-asr")

MODEL_DIR = os.environ.get("MODEL_DIR", "/mnt/1tbssd/models/canary-qwen-2.5b")
MODEL_ID  = os.environ.get("MODEL_ID",  "nvidia/canary-qwen-2.5b")
DEVICE    = "cuda" if torch.cuda.is_available() else "cpu"
DTYPE     = torch.bfloat16 if DEVICE == "cuda" else torch.float32

log.info(f"Loading Canary-Qwen from "
         f"{MODEL_DIR if os.path.isdir(MODEL_DIR) else MODEL_ID} "
         f"on {DEVICE} ({DTYPE})")
model = SALM.from_pretrained(
    MODEL_DIR if os.path.isdir(MODEL_DIR) else MODEL_ID)
model = model.to(DEVICE).to(DTYPE).eval()
log.info("Model ready.")

app = FastAPI(title="Canary-Qwen 2.5B ASR (OpenAI-compatible)")

def to_16k_mono_wav(in_path: str) -> str:
    """Resample any input audio to 16 kHz mono WAV; return new path."""
    wav, sr = librosa.load(in_path, sr=16000, mono=True)
    out_path = in_path + ".16k.wav"
    sf.write(out_path, wav, 16000, subtype="PCM_16")
    return out_path

@app.get("/health")
def health():
    return {"status": "ok", "device": DEVICE,
            "model": "nvidia/canary-qwen-2.5b"}

@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model_name: Optional[str] = Form("canary-qwen-2.5b", alias="model"),
    language: Optional[str] = Form("en"),
    prompt: Optional[str] = Form(None),
    response_format: Optional[str] = Form("json"),
    temperature: Optional[float] = Form(0.0),
):
    tmp_in = None
    tmp_16k = None
    try:
        suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
            f.write(await file.read())
            tmp_in = f.name

        tmp_16k = to_16k_mono_wav(tmp_in)

        user_text = prompt or "Transcribe the following:"
        prompts = [[{
            "role": "user",
            "content": f"{user_text} {model.audio_locator_tag}",
            "audio": [tmp_16k],
        }]]

        with torch.inference_mode():
            answer_ids = model.generate(prompts=prompts, max_new_tokens=512)

        ids = answer_ids[0]
        if hasattr(ids, "cpu"):
            ids = ids.cpu().tolist()
        text = model.tokenizer.ids_to_text(ids).strip()

        if response_format == "text":
            return PlainTextResponse(text)
        return JSONResponse({"text": text})
    except Exception as e:
        log.exception("transcription failed")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        for p in (tmp_in, tmp_16k):
            if p and os.path.exists(p):
                try: os.unlink(p)
                except Exception: pass

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0",
                port=int(os.environ.get("PORT", "8000")))
```

## 7. First-run smoke test

```bash
cd /mnt/1tbssd/git/canary-server
source .venv/bin/activate
export HF_HOME=/mnt/1tbssd/models/hf-cache
python server.py
# wait for:  Model ready.
# then:      Uvicorn running on http://0.0.0.0:8000
```

In another terminal:

```bash
# generate a 3-second 16 kHz test tone
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=3" \
       -ar 16000 -ac 1 /tmp/tone.wav

curl -s http://127.0.0.1:8000/health
# expect: {"status":"ok","device":"cuda",...}

curl -s -X POST http://127.0.0.1:8000/v1/audio/transcriptions \
     -F "model=canary-qwen-2.5b" \
     -F "file=@/tmp/tone.wav"
# expect: {"text":""} or a benign short string (sine has no speech)
```

Real-speech smoke test:

```bash
arecord -f S16_LE -r 16000 -c 1 -d 5 /tmp/me.wav
curl -s -X POST http://127.0.0.1:8000/v1/audio/transcriptions \
     -F "model=canary-qwen-2.5b" \
     -F "file=@/tmp/me.wav"
# expect: {"text":"<your spoken words>"}
```

If the speech round-trip works, stop the foreground server (Ctrl-C) and
move to systemd.

## 8. systemd service (autostart on boot)

```bash
USERNAME="$(whoami)"
sudo tee /etc/systemd/system/canary-asr.service > /dev/null <<UNITEOF
[Unit]
Description=Canary-Qwen 2.5B ASR Server (OpenAI-compatible)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USERNAME}
Group=${USERNAME}
WorkingDirectory=/mnt/1tbssd/git/canary-server
Environment=HF_HOME=/mnt/1tbssd/models/hf-cache
Environment=MODEL_DIR=/mnt/1tbssd/models/canary-qwen-2.5b
Environment=PORT=8000
Environment=PYTHONUNBUFFERED=1
ExecStart=/mnt/1tbssd/git/canary-server/.venv/bin/python /mnt/1tbssd/git/canary-server/server.py
Restart=on-failure
RestartSec=5
# Allow up to 5 minutes for cold-load of the model
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNITEOF

sudo systemctl daemon-reload
sudo systemctl enable --now canary-asr.service
systemctl status canary-asr.service --no-pager
journalctl -u canary-asr.service -f
# wait for "Model ready." and "Uvicorn running"
```

## 9. Firewall — allow LAN clients only

```bash
sudo ufw allow from 192.168.0.0/16 to any port 8000 proto tcp
sudo ufw allow from 10.0.0.0/8     to any port 8000 proto tcp
sudo ufw status

# this machine's LAN IP
hostname -I | awk '{print $1}'
# e.g. 192.0.2.42 — note this for the VoiceRider config
```

## 10. Point VoiceRider at your server

On the Mac:

```bash
defaults write com.voicerider voicerider.serverURL  "http://192.0.2.42:8000/v1/audio/transcriptions"
defaults write com.voicerider voicerider.modelName  "canary-qwen-2.5b"
defaults write com.voicerider voicerider.bearerToken "local-no-auth"   # ignored by this server
```

Then update `Resources/Info.plist` so App Transport Security accepts
your LAN host. Either name the host (and add it to `/etc/hosts`):

```xml
<key>NSExceptionDomains</key>
<dict>
    <key>my-asr-server</key>
    <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
    </dict>
</dict>
```

…or use the IP directly with CIDR `/32`:

```xml
<key>NSExceptionDomains</key>
<dict>
    <key>192.0.2.42/32</key>
    <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
    </dict>
</dict>
```

Then `./prod-build.sh --install` and relaunch.

## 11. Optional — Parakeet TDT v3 as a faster fallback

For batch / long-form work where speed > accuracy, NVIDIA's Parakeet
TDT v3 is ~10–100× faster than Canary-Qwen at ~6% WER. Download to the
same SSD; serve on a different port via a parallel `systemd` unit.

```bash
huggingface-cli download nvidia/parakeet-tdt-0.6b-v3 \
    --local-dir /mnt/1tbssd/models/parakeet-tdt-0.6b-v3 \
    --local-dir-use-symlinks False
```

Not wired up by default — only relevant if you outgrow Canary-Qwen for
real-time use.

## Troubleshooting

- **`pip install nemo_toolkit[asr]` fails on Cython 3.x.** Run
  `pip install "cython<3"` *before* the nemo install. Already in §4.

- **`torch.cuda.is_available() == False`.** Driver too old or wrong
  PyTorch wheel. Re-check `nvidia-smi`; reinstall with the cu124
  index URL.

- **`SALM.from_pretrained` errors with "model class not found".**

  ```bash
  pip install --upgrade "nemo_toolkit[asr]"
  python -c "from nemo.collections.speechlm2.models import SALM"
  ```

- **OOM at model load.** Stop other CUDA processes (`nvidia-smi` to
  list); we're already at bf16 so there's no further precision drop
  worth doing.

- **Empty transcription on real speech.** Verify input is genuinely
  16 kHz mono PCM:

  ```bash
  soxi /tmp/me.wav
  # Channels       : 1
  # Sample Rate    : 16000
  # Precision      : 16-bit
  ```

  The server resamples via librosa, but pathological inputs (e.g.
  Opus in a `.wav` container) can still fail upstream of resample.

- **HF cache leaking into `$HOME`.** Confirm:

  ```bash
  du -sh /mnt/1tbssd/models/hf-cache    # should grow
  du -sh ~/.cache/huggingface 2>/dev/null || echo "no home cache (good)"
  ```

  If `~/.cache/huggingface` is nonzero, your `HF_HOME` export didn't
  reach the systemd unit's environment — check the `Environment=` line
  in `/etc/systemd/system/canary-asr.service`.

## Done when

1. `systemctl is-active canary-asr` → `active`
2. `curl http://<lan-ip>:8000/health` from the Mac returns
   `{"status":"ok","device":"cuda",...}`
3. POSTing a 5-second speech `.wav` returns the correct transcription
4. VoiceRider's menu-bar icon round-trips: hold Right Option → speak →
   release → text appears at cursor in TextEdit
