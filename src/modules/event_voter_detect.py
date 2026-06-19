#!/usr/bin/env python3
"""
ACC Event Voter — panel detector.
Output (stdout): machine-readable KEY=VALUE lines.
Debug info goes to stderr.
"""
import sys
import os
import argparse

try:
    import cv2
    import numpy as np
except ImportError:
    print("ERROR: cv2 (OpenCV) not available. Install with: sudo dnf install python3-opencv",
          file=sys.stderr)
    print("       or: pip install opencv-python-headless", file=sys.stderr)
    sys.exit(2)

# Lower index = higher priority
PRIORITY_ORDER = ["3x_xp", "3x_mutation_chance"]

# Each source specifies which training file contains the label AND which slot
# (left/middle/right) in that file holds that label's visual content.
# Templates are extracted ONLY from the named slot — not from all slots.
TEMPLATE_SOURCES = {
    "3x_xp": [
        ("live_event_seed.png",          "right"),
        ("live_event_seed_xp.png",       "right"),
        ("live_event_seed_mutation.png", "right"),
    ],
    "3x_mutation_chance": [
        ("live_event_seed_mutation.png", "middle"),
    ],
}

MIN_NONZERO_PIXELS = 50
MIN_VARIANCE = 5.0
PANEL_MATCH_THRESHOLD = 0.30


def preprocess(img):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img.copy()
    norm = cv2.normalize(gray, np.zeros_like(gray), 0, 255, cv2.NORM_MINMAX)
    return cv2.Canny(norm, 50, 150)


def crop_region(img, x, y, w, h):
    ih, iw = img.shape[:2]
    x1 = int(np.clip(x, 0, iw - 1))
    y1 = int(np.clip(y, 0, ih - 1))
    x2 = int(np.clip(x + w, x1 + 1, iw))
    y2 = int(np.clip(y + h, y1 + 1, ih))
    return img[y1:y2, x1:x2]


def has_content(arr):
    """Return False if the array is too blank to produce a reliable match."""
    if arr.size == 0:
        return False
    if int(np.count_nonzero(arr)) < MIN_NONZERO_PIXELS:
        return False
    if float(np.var(arr.astype(np.float32))) < MIN_VARIANCE:
        return False
    return True


def match_score(region, tmpl):
    """
    TM_CCOEFF_NORMED score clamped to [0, 1].
    Returns 0.0 if either input lacks sufficient content (prevents blank→1.0 false matches).
    """
    if not has_content(region) or not has_content(tmpl):
        return 0.0
    if tmpl.shape[0] > region.shape[0] or tmpl.shape[1] > region.shape[1]:
        scale = min(region.shape[0] / tmpl.shape[0], region.shape[1] / tmpl.shape[1]) * 0.9
        if scale <= 0:
            return 0.0
        nh = max(1, int(tmpl.shape[0] * scale))
        nw = max(1, int(tmpl.shape[1] * scale))
        tmpl = cv2.resize(tmpl, (nw, nh))
    if tmpl.shape[0] > region.shape[0] or tmpl.shape[1] > region.shape[1]:
        return 0.0
    result = cv2.matchTemplate(region, tmpl, cv2.TM_CCOEFF_NORMED)
    _, mv, _, _ = cv2.minMaxLoc(result)
    return float(np.nan_to_num(np.clip(mv, 0.0, 1.0)))


def find_panel(img, training_dir):
    """
    Locate the vote panel bounding box in img.
    Small images (≤700px in both dims) are assumed to BE the panel.
    Large images: locate by template matching against the mutation training image.
    Returns (x, y, w, h) or None.
    """
    ih, iw = img.shape[:2]
    if iw <= 700 and ih <= 700:
        return (0, 0, iw, ih)

    ref_path = os.path.join(training_dir, "live_event_seed_mutation.png")
    if os.path.isfile(ref_path):
        ref = cv2.imread(ref_path)
        if ref is not None:
            rh, rw = ref.shape[:2]
            if rw <= iw and rh <= ih:
                result = cv2.matchTemplate(img, ref, cv2.TM_CCOEFF_NORMED)
                _, mv, _, loc = cv2.minMaxLoc(result)
                if mv >= PANEL_MATCH_THRESHOLD:
                    print(f"  panel located: loc={loc} score={mv:.3f} size={rw}x{rh}",
                          file=sys.stderr)
                    return (loc[0], loc[1], rw, rh)

    px = _env_int("EVENT_PANEL_CROP_X")
    py = _env_int("EVENT_PANEL_CROP_Y")
    pw = _env_int("EVENT_PANEL_CROP_W")
    ph = _env_int("EVENT_PANEL_CROP_H")
    if all(v is not None for v in (px, py, pw, ph)):
        return (px, py, pw, ph)

    return None


def _env_int(key):
    v = os.environ.get(key, "")
    try:
        return int(v)
    except (ValueError, TypeError):
        return None


def get_slot_crops(panel):
    """Divide panel into left/middle/right thirds; returns absolute (x,y,w,h)."""
    px, py, pw, ph = panel
    tw = pw // 3
    return {
        "left":   (px,        py, tw,        ph),
        "middle": (px + tw,   py, tw,        ph),
        "right":  (px + 2*tw, py, pw - 2*tw, ph),
    }


def load_templates(training_dir, generated_dir):
    """
    Extract one processed crop per (label, source) — from the correct slot only.
    Returns {label: [processed_ndarray, ...]} with possibly multiple arrays per label.
    Taking MAX across them during detection avoids cross-image variance issues.
    """
    os.makedirs(generated_dir, exist_ok=True)
    templates = {}

    for label, sources in TEMPLATE_SOURCES.items():
        for fname, slot_name in sources:
            fpath = os.path.join(training_dir, fname)
            if not os.path.isfile(fpath):
                continue
            img = cv2.imread(fpath)
            if img is None:
                continue

            panel = find_panel(img, training_dir)
            if panel is None:
                print(f"WARNING: cannot locate panel in {fname} — skipping template for {label}",
                      file=sys.stderr)
                continue

            slot_crops = get_slot_crops(panel)
            sx, sy, sw, sh = slot_crops[slot_name]
            raw = crop_region(img, sx, sy, sw, sh)
            proc = preprocess(raw)

            if not has_content(proc):
                print(f"WARNING: template {label}/{fname}[{slot_name}] is blank — skipping",
                      file=sys.stderr)
                continue

            stem = fname.replace(".png", "")
            out = os.path.join(generated_dir, f"template_{label}_{stem}.png")
            cv2.imwrite(out, proc)
            print(f"  template {label}/{fname}[{slot_name}]: {sw}x{sh} nonzero={np.count_nonzero(proc)}",
                  file=sys.stderr)

            templates.setdefault(label, []).append(proc)

    return templates


def _no_detection():
    for label in ("LEFT", "MIDDLE", "RIGHT"):
        print(f"{label}_LABEL=unknown")
        print(f"{label}_CONFIDENCE=0.00")
    print("POPUP_DETECTED=0")
    print("BEST_LABEL=unknown")
    print("BEST_SLOT=none")
    print("BEST_CONFIDENCE=0.00")
    print("SAFE_TO_CLICK=0")


def detect(image_path, training_dir, generated_dir, min_confidence, mode="offline"):
    img = cv2.imread(image_path)
    if img is None:
        print(f"ERROR: cannot read image: {image_path}", file=sys.stderr)
        sys.exit(1)

    templates = load_templates(training_dir, generated_dir)
    if not templates:
        print("WARNING: no templates loaded — cannot detect (add training images)",
              file=sys.stderr)
        _no_detection()
        return

    panel = find_panel(img, training_dir)
    if panel is None:
        print("WARNING: panel not found — configure EVENT_PANEL_CROP_* or add training images",
              file=sys.stderr)
        _no_detection()
        return

    os.makedirs(generated_dir, exist_ok=True)
    slot_crops = get_slot_crops(panel)
    proc_input = preprocess(img)

    slot_results = {}
    for slot in ("left", "middle", "right"):
        sx, sy, sw, sh = slot_crops[slot]
        region = crop_region(proc_input, sx, sy, sw, sh)
        cv2.imwrite(os.path.join(generated_dir, f"input_crop_{slot}.png"), region)

        r_nz = int(np.count_nonzero(region))
        r_var = float(np.var(region.astype(np.float32)))
        print(f"  slot {slot}: {sw}x{sh} nonzero={r_nz} var={r_var:.0f}", file=sys.stderr)

        best_label = "unknown"
        best_conf = 0.0

        for label in PRIORITY_ORDER:
            if label not in templates:
                continue
            # MAX score across all templates for this label
            label_conf = 0.0
            for tmpl in templates[label]:
                c = match_score(region, tmpl)
                t_nz = int(np.count_nonzero(tmpl))
                print(f"    {slot}/{label}: conf={c:.3f} tmpl_nz={t_nz}", file=sys.stderr)
                if c > label_conf:
                    label_conf = c

            if label_conf >= min_confidence and label_conf > best_conf:
                best_conf = label_conf
                best_label = label

        if best_label == "unknown":
            best_conf = 0.0
        slot_results[slot] = (best_label, best_conf)

    # Select best slot: priority first, confidence as tiebreaker
    best_slot = "none"
    best_label = "unknown"
    best_conf = 0.0

    for slot in ("left", "middle", "right"):
        label, conf = slot_results.get(slot, ("unknown", 0.0))
        if label == "unknown" or conf < min_confidence:
            continue
        if best_slot == "none":
            best_slot, best_label, best_conf = slot, label, conf
        else:
            ci = PRIORITY_ORDER.index(label) if label in PRIORITY_ORDER else 999
            bi = PRIORITY_ORDER.index(best_label) if best_label in PRIORITY_ORDER else 999
            if ci < bi or (ci == bi and conf > best_conf):
                best_slot, best_label, best_conf = slot, label, conf

    popup = 1 if best_slot != "none" else 0
    safe = 1 if best_slot != "none" and best_conf >= min_confidence else 0

    def sr(s):
        return slot_results.get(s, ("unknown", 0.0))

    ll, lc = sr("left")
    ml, mc = sr("middle")
    rl, rc = sr("right")

    print(f"POPUP_DETECTED={popup}")
    print(f"LEFT_LABEL={ll}")
    print(f"LEFT_CONFIDENCE={lc:.2f}")
    print(f"MIDDLE_LABEL={ml}")
    print(f"MIDDLE_CONFIDENCE={mc:.2f}")
    print(f"RIGHT_LABEL={rl}")
    print(f"RIGHT_CONFIDENCE={rc:.2f}")
    print(f"BEST_LABEL={best_label}")
    print(f"BEST_SLOT={best_slot}")
    print(f"BEST_CONFIDENCE={best_conf:.2f}")
    print(f"SAFE_TO_CLICK={safe}")

    print(f"Detection: best={best_label} slot={best_slot} conf={best_conf:.2f}",
          file=sys.stderr)


def crops_only(image_path, generated_dir, training_dir):
    img = cv2.imread(image_path)
    if img is None:
        print(f"ERROR: cannot read image: {image_path}", file=sys.stderr)
        sys.exit(1)
    os.makedirs(generated_dir, exist_ok=True)
    panel = find_panel(img, training_dir)
    if panel is None:
        print("WARNING: panel not found — using full image", file=sys.stderr)
        panel = (0, 0, img.shape[1], img.shape[0])
    slot_crops = get_slot_crops(panel)
    proc = preprocess(img)
    for slot, (sx, sy, sw, sh) in slot_crops.items():
        crop = crop_region(proc, sx, sy, sw, sh)
        out = os.path.join(generated_dir, f"input_crop_{slot}.png")
        cv2.imwrite(out, crop)
        print(f"wrote crop [{slot}]: {out} size={sw}x{sh} nonzero={np.count_nonzero(crop)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", default="")
    parser.add_argument("--training-dir", default="runtime_config/event_voter/training")
    parser.add_argument("--generated-dir", default="runtime_config/event_voter/generated")
    parser.add_argument("--mode", choices=["offline", "live"], default="offline")
    parser.add_argument("--min-confidence", type=float, default=0.55)
    parser.add_argument("--crops-only", action="store_true")
    args = parser.parse_args()

    if args.crops_only:
        if not args.image:
            print("ERROR: --crops-only requires --image", file=sys.stderr)
            sys.exit(1)
        if not os.path.isfile(args.image):
            print(f"ERROR: image not found: {args.image}", file=sys.stderr)
            sys.exit(1)
        crops_only(args.image, args.generated_dir, args.training_dir)
        return

    if not args.image:
        print("ERROR: --image is required", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.image):
        print(f"ERROR: image not found: {args.image}", file=sys.stderr)
        sys.exit(2)

    detect(args.image, args.training_dir, args.generated_dir, args.min_confidence, args.mode)


if __name__ == "__main__":
    main()
