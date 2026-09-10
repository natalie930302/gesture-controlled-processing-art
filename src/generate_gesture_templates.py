"""
產生「合成手勢範例資料」,訓練手勢分類器用。

誠實說明:這裡不是模擬 MediaPipe 的 21 個原始關鍵點,而是直接在
features.py 定義的 10 維特徵空間(手指到手掌中心距離+指間張角+張開度)
裡,針對 5 種手勢各設計一個「典型特徵中心點」,再加高斯雜訊生成多筆樣本。
分類器不管輸入特徵是來自合成資料還是真的 MediaPipe landmark,看到的都是
同一組 10 維特徵,所以這樣訓練出來的分類器架構、pipeline 是完整可用的;
但因為典型中心點是手動估計、不是真人手勢量測出來的,實際辨識準確率一定
比不上用真實webcam資料訓練——這點在 README 有清楚說明,也附上
collect_real_data.py 讓之後可以录真人資料重新訓練、直接替換掉這份合成資料。
"""
import numpy as np
import json
import os

np.random.seed(42)

# 特徵順序跟 features.py 的 FEATURE_NAMES 一致:
# [thumb_dist, index_dist, middle_dist, ring_dist, pinky_dist,
#  angle_thumb_index, angle_index_middle, angle_middle_ring, angle_ring_pinky, openness]

# 每種手勢的「典型特徵中心點」,依幾何常識手動估計(距離已經過 palm_size 正規化,
# 手指伸直約 1.3~1.8,捲曲約 0.5~0.8;角度單位是弧度)
GESTURE_TEMPLATES = {
    "fist": [0.6, 0.6, 0.6, 0.6, 0.6, 0.3, 0.3, 0.3, 0.3, 0.6],
    "open_palm": [1.4, 1.7, 1.8, 1.7, 1.5, 0.7, 0.35, 0.3, 0.35, 1.62],
    "point": [0.7, 1.7, 0.6, 0.6, 0.6, 0.8, 0.9, 0.3, 0.3, 0.84],
    "peace": [0.7, 1.7, 1.7, 0.6, 0.6, 0.8, 0.35, 0.9, 0.3, 1.06],
    "thumbs_up": [1.5, 0.6, 0.6, 0.6, 0.6, 0.6, 0.3, 0.3, 0.3, 0.78],
}

GESTURE_NAMES = list(GESTURE_TEMPLATES.keys())
NOISE_STD = 0.12
N_PER_CLASS = 300


def main():
    X, y = [], []
    for label, center in GESTURE_TEMPLATES.items():
        center = np.array(center, dtype=np.float32)
        samples = center[None, :] + np.random.normal(0, NOISE_STD, size=(N_PER_CLASS, len(center)))
        samples = np.clip(samples, 0.05, None)
        X.append(samples)
        y += [label] * N_PER_CLASS

    X = np.vstack(X).astype(np.float32)
    y = np.array(y)

    os.makedirs("../data", exist_ok=True)
    np.savez("../data/synthetic_gestures.npz", X=X, y=y)
    with open("../data/gesture_names.json", "w", encoding="utf-8") as f:
        json.dump(GESTURE_NAMES, f, ensure_ascii=False, indent=2)

    print(f"產生 {len(X)} 筆合成訓練樣本,{len(GESTURE_NAMES)} 種手勢: {GESTURE_NAMES}")
    print("已儲存至 data/synthetic_gestures.npz, data/gesture_names.json")


if __name__ == "__main__":
    main()
