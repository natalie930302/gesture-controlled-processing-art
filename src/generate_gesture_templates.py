"""
產生「合成手勢範例資料」,訓練手勢分類器用。

誠實說明:這裡不是模擬 MediaPipe 的 21 個原始關鍵點,而是直接在
features.py 定義的 10 維特徵空間(手指到手掌中心距離+指間張角+張開度)
裡,針對 5 種手勢各設計一個「典型特徵中心點」生成樣本。分類器不管輸入特徵
是來自合成資料還是真的 MediaPipe landmark,看到的都是同一組 10 維特徵,
所以這樣訓練出來的分類器架構、pipeline 是完整可用的;但因為典型中心點是
手動估計、不是真人手勢量測出來的,實際辨識準確率一定比不上用真實webcam
資料訓練——這點在 README 有清楚說明,也附上 collect_real_data.py 讓之後
可以录真人資料重新訓練、直接替換掉這份合成資料。

資料生成方式參考 Domain Randomization(Tobin et al., 2017, "Domain
Randomization for Transferring Deep Neural Networks from Simulation to the
Real World")的精神:與其只在單一個固定中心點外加一層同質的雜訊(原本的做法),
改成隨機化多個「模擬情境參數」,讓合成資料涵蓋更大範圍的變異:
  1. 「虛擬個體」層級:每個模擬出來的人對同一個手勢的比法會有系統性差異
     (例如手指張開的角度習慣性偏大或偏小),不是每次都圍繞同一個中心點,
     而是先幫每個虛擬個體抽一個自己的偏移中心,同一個人比多次會彼此接近,
     但跟其他人有系統性差異——這比單層同質高斯雜訊更接近真實資料的階層結構
     (population variance + individual variance)
  2. 「追蹤雜訊」層級:MediaPipe 在遮擋、光線不佳時偶爾會誤判某個關鍵點,
     以小機率讓某一維特徵出現較大幅度的偏移,模擬這種感測器層級的雜訊
這個改動沒辦法用真實資料驗證「有沒有真的比較好」(還是合成資料,跟原本一樣
不代表真實辨識能力),誠實的說法是:讓合成資料的生成過程更貼近文獻裡建議的
作法,不是保證分類器因此變準。
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

N_VIRTUAL_USERS = 20         # 每個手勢模擬幾個「虛擬個體」
SAMPLES_PER_USER = 15        # 每個虛擬個體重複比幾次(=N_VIRTUAL_USERS*SAMPLES_PER_USER=300,跟原本總數一致)
BETWEEN_PERSON_STD = 0.09    # 不同人之間的系統性差異
WITHIN_PERSON_STD = 0.05     # 同一人重複比的雜訊(比原本0.12小,因為變異已經有一部分被個體差異解釋掉)
TRACKING_GLITCH_PROB = 0.04  # 每個樣本每一維,有這個機率模擬追蹤誤判
TRACKING_GLITCH_STD = 0.35   # 追蹤誤判時的偏移幅度(明顯比正常雜訊大)


def main():
    X, y = [], []
    for label, center in GESTURE_TEMPLATES.items():
        center = np.array(center, dtype=np.float32)

        for _ in range(N_VIRTUAL_USERS):
            # 這個虛擬個體自己的系統性偏移(population-level variation)
            person_offset = np.random.normal(0, BETWEEN_PERSON_STD, size=len(center))
            person_center = center + person_offset

            samples = person_center[None, :] + np.random.normal(
                0, WITHIN_PERSON_STD, size=(SAMPLES_PER_USER, len(center))
            )

            # 模擬 MediaPipe 追蹤誤判:小機率讓某一維出現明顯偏移
            glitch_mask = np.random.random(samples.shape) < TRACKING_GLITCH_PROB
            glitch_noise = np.random.normal(0, TRACKING_GLITCH_STD, size=samples.shape)
            samples = samples + glitch_mask * glitch_noise

            samples = np.clip(samples, 0.05, None)
            X.append(samples)
            y += [label] * SAMPLES_PER_USER

    X = np.vstack(X).astype(np.float32)
    y = np.array(y)

    os.makedirs("../data", exist_ok=True)
    np.savez("../data/synthetic_gestures.npz", X=X, y=y)
    with open("../data/gesture_names.json", "w", encoding="utf-8") as f:
        json.dump(GESTURE_NAMES, f, ensure_ascii=False, indent=2)

    print(f"產生 {len(X)} 筆合成訓練樣本,{len(GESTURE_NAMES)} 種手勢: {GESTURE_NAMES}")
    print(f"(domain randomization: {N_VIRTUAL_USERS}個虛擬個體 x {SAMPLES_PER_USER}次/人,"
          f"含{TRACKING_GLITCH_PROB*100:.0f}%機率的模擬追蹤雜訊)")
    print("已儲存至 data/synthetic_gestures.npz, data/gesture_names.json")


if __name__ == "__main__":
    main()
