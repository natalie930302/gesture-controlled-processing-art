"""
用極少量真人手勢樣本(每個手勢只要3~5筆,不是collect_real_data.py建議的50~100筆)
校準手勢分類器,降低「要真的驗證sim-to-real gap」的門檻。

方法參考 Prototypical Networks(Snell et al., NeurIPS 2017)的核心概念,以及
近年 few-shot 手勢辨識文獻(如 2026年的 EMG-Adapt 用prototype-based few-shot
adaptation處理肌電手勢辨識的個體差異問題)共同採用的做法:
  - 每個類別用少量support examples算出一個「原型」(prototype,通常是特徵空間
    裡的平均向量),分類新樣本時看它離哪個原型最近
  - 這裡進一步結合「合成資料算出的原型」(generate_gesture_templates.py裡手動
    設計的典型中心點)當作先驗知識,用真人少量樣本校準後的原型跟先驗原型做
    加權平均——真人樣本數越多,權重越傾向真人資料;樣本數很少時,先驗知識
    幫忙穩定原型,不會因為只有3筆樣本就被雜訊主導

這個腳本目前執行不了真正的驗證,因為 collect_real_data.py 產生的
real_gestures.npz 還不存在(你還沒錄過真人資料)——執行後會誠實印出這個
提醒,不是bug。等你哪怕只錄了3~5筆/手勢,這支腳本就能立刻用,不需要錄到
collect_real_data.py建議的50~100筆才能看到「合成資料 vs. 真實資料」的
差距,大幅降低你實際驗證sim-to-real gap所需的時間成本。
"""
import json
import os
import numpy as np

MIN_SAMPLES_PER_CLASS = 2  # 至少要有幾筆才能算原型(1筆也能算,但至少2筆才有一點統計意義)
PRIOR_WEIGHT_AT_N1 = 0.7   # 只有1筆真人樣本時,先驗(合成)原型佔的權重
PRIOR_WEIGHT_HALFLIFE = 5  # 真人樣本數增加到這個量級時,先驗權重降到約一半以下


def synthetic_prototypes():
    """從 generate_gesture_templates.py 手動設計的典型中心點,當作先驗原型。"""
    from generate_gesture_templates import GESTURE_TEMPLATES
    return {label: np.array(center, dtype=np.float32) for label, center in GESTURE_TEMPLATES.items()}


def compute_calibrated_prototypes(real_X, real_y, prior_protos):
    """真人少量樣本原型 跟 合成先驗原型 做加權平均,樣本越多真人權重越高。"""
    calibrated = {}
    for label in prior_protos:
        mask = real_y == label
        n = mask.sum()
        prior = prior_protos[label]

        if n == 0:
            calibrated[label] = prior
            continue

        real_proto = real_X[mask].mean(axis=0)
        # 樣本數越多,先驗權重越低(指數衰減),n=1時先驗權重PRIOR_WEIGHT_AT_N1,
        # n=PRIOR_WEIGHT_HALFLIFE時先驗權重約降到PRIOR_WEIGHT_AT_N1的一半
        prior_weight = PRIOR_WEIGHT_AT_N1 * (0.5 ** ((n - 1) / PRIOR_WEIGHT_HALFLIFE))
        calibrated[label] = prior_weight * prior + (1 - prior_weight) * real_proto

    return calibrated


def classify_by_prototype(feat, prototypes):
    """最近原型分類:回傳距離最近的手勢類別。"""
    dists = {label: np.linalg.norm(feat - proto) for label, proto in prototypes.items()}
    return min(dists, key=dists.get)


def main():
    real_data_path = "../data/real_gestures.npz"
    prior_protos = synthetic_prototypes()

    if not os.path.exists(real_data_path):
        print("找不到 ../data/real_gestures.npz——你還沒用 collect_real_data.py 錄過任何真人手勢資料。")
        print(f"這支腳本只需要每個手勢 {MIN_SAMPLES_PER_CLASS}~5 筆左右的真人樣本就能用,")
        print("比 collect_real_data.py 建議的 50~100 筆門檻低很多,先錄一點點試試看:")
        print("  python collect_real_data.py fist")
        print("  python collect_real_data.py open_palm")
        print("  ...(每個手勢錄個3~5次就好)")
        return

    data = np.load(real_data_path, allow_pickle=True)
    real_X, real_y = data["X"], data["y"]

    print(f"讀到 {len(real_X)} 筆真人樣本,各手勢筆數:")
    for label in prior_protos:
        n = (real_y == label).sum()
        print(f"  {label}: {n} 筆")

    calibrated = compute_calibrated_prototypes(real_X, real_y, prior_protos)

    # Leave-one-out驗證:每一筆真人樣本,用「扣掉它之後」的原型去分類它,
    # 這樣才不會用同一筆資料同時算原型又拿來驗證(資料洩漏)
    correct = 0
    for i in range(len(real_X)):
        loo_X = np.delete(real_X, i, axis=0)
        loo_y = np.delete(real_y, i, axis=0)
        loo_protos = compute_calibrated_prototypes(loo_X, loo_y, prior_protos)
        pred = classify_by_prototype(real_X[i], loo_protos)
        if pred == real_y[i]:
            correct += 1

    print(f"\nLeave-one-out 準確率(用真人資料驗證,不是合成資料): {correct}/{len(real_X)} = {correct/len(real_X):.3f}")
    print("這個數字才是真正反映你的手勢在真實webcam環境下的辨識能力。")


if __name__ == "__main__":
    main()
