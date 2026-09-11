"""
用真人錄製的手勢資料(data/real_gestures.npz)訓練分類器,並且直接量化
「合成資料訓練出的分類器,套用在真人資料上」的真實落差——這是整個專案
理論部分一直在講的 Sim-to-Real Gap,這支腳本第一次真的量出數字,不是
只停留在文獻引用。
"""
import numpy as np
import json
import joblib
from sklearn.svm import SVC
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score

with open("../data/gesture_names.json", encoding="utf-8") as f:
    gesture_names = json.load(f)

real_data = np.load("../data/real_gestures.npz", allow_pickle=True)
X_real, y_real = real_data["X"], real_data["y"]
print(f"真人資料總筆數: {len(X_real)}")
for label in gesture_names:
    print(f"  {label}: {(y_real == label).sum()} 筆")

X_train, X_test, y_train, y_test = train_test_split(
    X_real, y_real, test_size=0.25, stratify=y_real, random_state=42
)

# --- 1. 合成資料訓練的分類器,直接套用在真人測試集上(量化sim-to-real gap) ---
synthetic_clf = joblib.load("../data/gesture_classifier.joblib")
synthetic_on_real_pred = synthetic_clf.predict(X_test)
synthetic_on_real_acc = accuracy_score(y_test, synthetic_on_real_pred)

# --- 2. 用真人資料重新訓練 ---
real_clf = SVC(kernel="rbf", C=10, gamma="scale", probability=True)
real_clf.fit(X_train, y_train)
real_pred = real_clf.predict(X_test)
real_acc = accuracy_score(y_test, real_pred)

print(f"\n=== 合成資料訓練的分類器,套用在真人測試集(n={len(X_test)}) ===")
print(f"準確率: {synthetic_on_real_acc:.3f}")
print(classification_report(y_test, synthetic_on_real_pred, target_names=gesture_names, zero_division=0))

print(f"\n=== 真人資料訓練的分類器,測試在真人測試集(n={len(X_test)}) ===")
print(f"準確率: {real_acc:.3f}")
print(classification_report(y_test, real_pred, target_names=gesture_names, zero_division=0))

print(f"\n=== Sim-to-Real Gap 量化結果 ===")
print(f"合成資料訓練 → 真人測試集: {synthetic_on_real_acc:.3f}")
print(f"真人資料訓練 → 真人測試集: {real_acc:.3f}")
print(f"差距: {real_acc - synthetic_on_real_acc:+.3f}")

joblib.dump(real_clf, "../data/gesture_classifier_real.joblib")
print("\n已儲存真人資料訓練的分類器至 data/gesture_classifier_real.joblib")

with open("../data/sim_to_real_gap_results.json", "w", encoding="utf-8") as f:
    json.dump({
        "n_real_samples": len(X_real),
        "n_test_samples": len(X_test),
        "synthetic_trained_on_real_test_acc": synthetic_on_real_acc,
        "real_trained_on_real_test_acc": real_acc,
        "gap": real_acc - synthetic_on_real_acc,
    }, f, ensure_ascii=False, indent=2)
print("已儲存至 data/sim_to_real_gap_results.json")
