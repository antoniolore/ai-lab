#!/usr/bin/env python3
"""Random-weight BitNet GGUF in the 1bitLLM/"bitnet" layout (arXiv 2410.16144 Appendix A sizes).

lab, the bench author, 2026-11-18. For timing only: weights are random ternary, output is meaningless.
Writes TQ2_0 (stock llama.cpp) or I2_S (bitnet.cpp fork) ternary matrices, F16 token embedding,
F32 norms. KV metadata and tokenizer are copied from a template GGUF of bitnet_b1_58-large
(vocab 32,002, same as Microsoft's dummy generator). Streams tensor by tensor.

usage: gen_dummy_bitnet.py --layout {large,7B,13B,100B} --type {tq2_0,i2_s} --template T.gguf --out O.gguf
Needs gguf-py of stock llama.cpp on PYTHONPATH.
"""
import argparse
import numpy as np
from gguf import GGUFReader, GGUFWriter, GGUFValueType, GGMLQuantizationType

LAYOUTS = {  # from utils/generate-dummy-bitnet-model.py / 2410.16144 Appendix A (no GQA)
    "large": dict(hidden=1536, ff=4096, layers=24, heads=16),
    "7B":    dict(hidden=4096, ff=12032, layers=32, heads=32),
    "13B":   dict(hidden=5120, ff=13824, layers=40, heads=40),
    "100B":  dict(hidden=8192, ff=45568, layers=72, heads=64),
}
I2_S_ID = 36          # GGML_TYPE_I2_S in the bitnet.cpp fork
TQ2_0 = GGMLQuantizationType.TQ2_0
SKIP = {"general.file_type", "general.name", "general.size_label", "general.basename", "general.organization"}

rng = np.random.default_rng(42)
# bytes whose four 2-bit fields are all in {0,1,2} (= ternary -1/0/+1 in both formats; 3 is never used)
VALID = np.array([b for b in range(256) if all(((b >> s) & 3) != 3 for s in (0, 2, 4, 6))], dtype=np.uint8)


def ternary_bytes(n):
    return VALID[rng.integers(0, len(VALID), size=n, dtype=np.int64)]


def tq2_0(rows, cols):  # block_tq2_0 = qs[64] + fp16 d, 256 weights per block
    assert cols % 256 == 0
    nb = rows * cols // 256
    blk = np.empty((nb, 66), dtype=np.uint8)
    blk[:, :64] = ternary_bytes(nb * 64).reshape(nb, 64)
    blk[:, 64:] = np.frombuffer(np.float16(0.01).tobytes(), dtype=np.uint8)
    return blk.reshape(-1)


def i2_s(rows, cols):  # bitnet.cpp: rows*cols/4 packed bytes, then 32 bytes (float32 scale first)
    out = np.zeros(rows * cols // 4 + 32, dtype=np.uint8)
    out[: rows * cols // 4] = ternary_bytes(rows * cols // 4)
    out[rows * cols // 4: rows * cols // 4 + 4] = np.frombuffer(np.float32(1.0).tobytes(), dtype=np.uint8)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layout", required=True, choices=LAYOUTS)
    ap.add_argument("--type", required=True, choices=["tq2_0", "i2_s"])
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    L = LAYOUTS[a.layout]
    h, ff, nl, nh = L["hidden"], L["ff"], L["layers"], L["heads"]

    tpl = GGUFReader(a.template)
    arch = tpl.fields["general.architecture"].contents()
    assert arch == "bitnet", arch
    vocab = len(tpl.fields["tokenizer.ggml.tokens"].contents())

    w = GGUFWriter(a.out, arch)
    over = {
        f"{arch}.block_count": nl, f"{arch}.embedding_length": h, f"{arch}.feed_forward_length": ff,
        f"{arch}.attention.head_count": nh, f"{arch}.attention.head_count_kv": nh,
        f"{arch}.attention.key_length": h // nh, f"{arch}.attention.value_length": h // nh,
    }
    for k, f in tpl.fields.items():
        if k.startswith("GGUF.") or k == "general.architecture" or k in SKIP or k in over:
            continue
        vt = f.types[0]
        sub = f.types[-1] if vt == GGUFValueType.ARRAY else None
        w.add_key_value(k, f.contents(), vt, sub_type=sub)
    for k, v in over.items():
        w.add_key_value(k, v, GGUFValueType.UINT32)
    w.add_name(f"dummy BitNet {a.layout} ({a.type}, random weights)")

    tern = (lambda r, c: tq2_0(r, c)) if a.type == "tq2_0" else (lambda r, c: i2_s(r, c))
    tdt = TQ2_0 if a.type == "tq2_0" else I2_S_ID

    plan = [("token_embd.weight", (vocab, h), "f16"), ("output_norm.weight", (h,), "norm")]
    for i in range(nl):
        b = f"blk.{i}."
        plan += [(b + "attn_norm.weight", (h,), "norm"), (b + "attn_q.weight", (h, h), "t"),
                 (b + "attn_k.weight", (h, h), "t"), (b + "attn_v.weight", (h, h), "t"),
                 (b + "attn_output.weight", (h, h), "t"), (b + "attn_sub_norm.weight", (h,), "norm"),
                 (b + "ffn_norm.weight", (h,), "norm"), (b + "ffn_gate.weight", (ff, h), "t"),
                 (b + "ffn_up.weight", (ff, h), "t"), (b + "ffn_down.weight", (h, ff), "t"),
                 (b + "ffn_sub_norm.weight", (ff,), "norm")]

    def nbytes(shape, kind):
        if kind == "f16": return shape[0] * shape[1] * 2
        if kind == "norm": return shape[0] * 4
        r, c = shape
        return r * c // 256 * 66 if a.type == "tq2_0" else r * c // 4 + 32

    for name, shape, kind in plan:
        if kind == "f16":
            w.add_tensor_info(name, shape, np.dtype(np.float16), nbytes(shape, kind))
        elif kind == "norm":
            w.add_tensor_info(name, shape, np.dtype(np.float32), nbytes(shape, kind))
        else:  # logical shape (rows, cols), stored as raw quantized bytes
            w.add_tensor_info(name, shape, np.dtype(np.float32), nbytes(shape, kind), raw_dtype=tdt)
    w.write_header_to_file()
    w.write_kv_data_to_file()
    w.write_ti_data_to_file()
    total = 0
    for name, shape, kind in plan:
        if kind == "f16":
            arr = (rng.standard_normal(shape, dtype=np.float32) * 0.02).astype(np.float16)
        elif kind == "norm":
            arr = np.ones(shape, dtype=np.float32)
        else:
            arr = tern(*shape)
        assert arr.nbytes == nbytes(shape, kind), (name, arr.nbytes, nbytes(shape, kind))
        w.write_tensor_data(arr)
        total += arr.nbytes
    w.close()
    params = vocab * h + nl * (4 * h * h + 3 * h * ff)
    print(f"wrote {a.out}: {total/1e9:.2f} GB tensor data, {params/1e9:.2f} B params (layout {a.layout})")


if __name__ == "__main__":
    main()
