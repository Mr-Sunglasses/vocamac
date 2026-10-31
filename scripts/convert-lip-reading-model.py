# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#   "torch==2.15.0",
#   "coremltools==9.0",
#   "numpy==2.5.4",
#   "six==1.17.0",
# ]
# ///
"""Build Silent Mode's English lip-reading model.

Converts Auto-AVSR's visual speech recognition checkpoint LRS3_V_WER19.1
(encoder and CTC head) to Core ML, with input lengths every 10 frames up to
750 (30 s at 25 fps), and writes it with its token list where VocaMac looks:

    ~/Library/Application Support/VocaMac/models/lip-reading/
        LipReader.mlpackage
        tokens.json

The weights are not VocaMac's to redistribute: they carry the terms of the
data they were trained on (LRS3 from TED, LRS2 and LRW from the BBC), which
allow research and non-commercial use only. This script downloads them for
your own use on your Mac.

    uv run scripts/convert-lip-reading-model.py            # FP32, ~740 MB, best accuracy
    uv run scripts/convert-lip-reading-model.py --fp16     # ~370 MB, about 2 points more WER
    uv run scripts/convert-lip-reading-model.py --out DIR  # somewhere else (then Import in Settings)

Takes about 10 minutes and 3 GB of downloads (PyTorch and the 958 MB
checkpoint). Measured on 60 LRS3 test clips with greedy decoding: 33.5% WER
(FP32), 35.4% (FP16); PyTorch on unpadded clips 31.9%.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

# Chaplin (MIT) carries Auto-AVSR's model code (Apache-2.0) and the token list.
CHAPLIN_URL = "https://github.com/amanvirparhar/chaplin.git"
CHAPLIN_COMMIT = "7aee1f8fca776ce4f63690063310b53573b7d804"
WEIGHTS_REPO = "https://huggingface.co/Amanvir/LRS3_V_WER19.1/resolve/c0b413f56b164565865a63f00774ee55a9738cc5"
FILES = {
    "model.pth": "e740cef369abeabd0ba2c18e37a0661342e1d94d432d6caa77755a11821d8fe3",
    "model.json": "e062e8c58579f54cb51087e639e674781189809905db4162efe0fe1325356d4f",
}
TOKENS_SHA256 = "29001d967ad290e28f6f1d7d47e07e314354bf67d3b1f494e936fa2fed9a9122"
DEFAULT_OUT = Path.home() / "Library/Application Support/VocaMac/models/lip-reading"
MAX_FRAMES = 750
STEP = 10


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(name: str, folder: Path) -> Path:
    path = folder / name
    if path.exists() and sha256(path) == FILES[name]:
        return path
    print(f"Downloading {name}…", flush=True)
    urllib.request.urlretrieve(f"{WEIGHTS_REPO}/{name}", path)
    if sha256(path) != FILES[name]:
        sys.exit(f"{name} doesn't match its expected SHA-256; not converting it.")
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="where to write the model")
    parser.add_argument("--fp16", action="store_true", help="half the size, slightly less accurate")
    parser.add_argument("--work", type=Path, help="keep downloads here between runs")
    args = parser.parse_args()

    work = args.work or Path(tempfile.mkdtemp(prefix="vocamac-lipreading-"))
    work.mkdir(parents=True, exist_ok=True)
    source = work / "chaplin"
    if not (source / ".git").exists():
        subprocess.run(["git", "clone", "--quiet", CHAPLIN_URL, str(source)], check=True)
    subprocess.run(["git", "-C", str(source), "checkout", "--quiet", CHAPLIN_COMMIT], check=True)
    units_path = source / "pipelines/tokens/unigram5000_units.txt"
    if sha256(units_path) != TOKENS_SHA256:
        sys.exit("The token list doesn't match its expected SHA-256.")
    weights = {name: fetch(name, work) for name in FILES}

    import numpy as np
    import torch
    import coremltools as ct
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.frontend.torch.ops import _get_inputs
    from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op

    sys.path.insert(0, str(source))
    from espnet.nets.pytorch_backend.e2e_asr_transformer import E2E

    @register_torch_op
    def view_as(context, node):
        x, other = _get_inputs(context, node, expected=2)
        context.add(mb.reshape(x=x, shape=mb.shape(x=other), name=node.name))

    conf = json.loads(weights["model.json"].read_text())
    train_args = argparse.Namespace(**(conf if isinstance(conf, dict) else conf[2]))
    units = units_path.read_text().splitlines()
    tokens = ["<blank>"] + [unit.split()[0] for unit in units] + ["<eos>"]
    e2e = E2E(len(tokens), train_args)
    e2e.load_state_dict(torch.load(weights["model.pth"], map_location="cpu"))
    e2e.eval()

    class LipReader(torch.nn.Module):
        """Mouth crops [1, 1, T, 88, 88] → CTC log-probabilities [1, T, vocabulary]."""

        def __init__(self, model):
            super().__init__()
            self.encoder = model.encoder
            self.ctc_lo = model.ctc.ctc_lo

        def forward(self, video):
            encoded, _ = self.encoder(video, None)
            return torch.log_softmax(self.ctc_lo(encoded), dim=-1)

    model = LipReader(e2e).eval()
    with torch.no_grad():
        traced = torch.jit.trace(model, torch.randn(1, 1, 80, 88, 88), check_trace=False)

    print("Converting to Core ML…", flush=True)
    shapes = [(1, 1, length, 88, 88) for length in range(STEP, MAX_FRAMES + 1, STEP)]
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="video", shape=ct.EnumeratedShapes(shapes=shapes, default=(1, 1, 80, 88, 88)), dtype=np.float32)],
        outputs=[ct.TensorType(name="log_probs", dtype=np.float32)],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16 if args.fp16 else ct.precision.FLOAT32,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "Auto-AVSR LRS3_V_WER19.1 visual-only encoder and CTC head: English lip reading."
    mlmodel.license = "Weights: research and non-commercial use only (LRS3, LRS2, LRW terms). Code: Apache-2.0 (mpc001/auto_avsr)."

    # Check against PyTorch before installing anything.
    sample = np.random.default_rng(0).standard_normal((1, 1, 80, 88, 88)).astype(np.float32)
    with torch.no_grad():
        reference = model(torch.from_numpy(sample)).numpy()
    produced = mlmodel.predict({"video": sample})["log_probs"]
    agreement = float((reference.argmax(-1) == produced.argmax(-1)).mean())
    print(f"Agreement with PyTorch on a test input: {agreement:.3f}")
    if agreement < 0.95:
        sys.exit("The converted model disagrees with PyTorch; not installing it.")

    args.out.mkdir(parents=True, exist_ok=True)
    for stale in ("LipReader.mlpackage", "LipReader.mlmodelc"):
        target = args.out / stale
        if target.exists():
            subprocess.run(["rm", "-rf", str(target)], check=True)
    mlmodel.save(str(args.out / "LipReader.mlpackage"))
    (args.out / "tokens.json").write_text(json.dumps(tokens, ensure_ascii=False))
    (args.out / "NOTICE.txt").write_text(
        "Auto-AVSR visual speech recognition model LRS3_V_WER19.1 (Ma et al., ICASSP 2023,\n"
        "https://github.com/mpc001/auto_avsr), converted to Core ML for VocaMac's Silent Mode.\n"
        "The weights carry the terms of their training data and are for research and\n"
        "non-commercial use only. Do not redistribute them.\n"
    )
    print(f"Installed in {args.out}. Restart VocaMac's Silent Mode recording to use it.")


if __name__ == "__main__":
    main()
