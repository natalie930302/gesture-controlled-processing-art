"""
用 generate_gesture_templates.py 產生的合成特徵資料訓練手勢分類器。
"""
import numpy as np
import json
import joblib
from sklearn.svm import SVC
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score

data = np.load("../data/synthetic_gestures.npz", allow_pickle=True)
X, y = data["X"], data["y"]

with open("../data/gesture_names.json", encoding="utf-8") as f:
    gesture_names = json.load(f)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, stratify=y, random_state=42
)

clf = SVC(kernel="rbf", C=10, gamma="scale", probability=True)
clf.fit(X_train, y_train)

pred = clf.predict(X_test)
acc = accuracy_score(y_test, pred)
print(f"測試集準確率: {acc:.3f}\n")
print(classification_report(y_test, pred, target_names=gesture_names))

joblib.dump(clf, "../data/gesture_classifier.joblib")
print("已儲存模型至 data/gesture_classifier.joblib")

print(
    "\n注意:這個準確率是在合成資料的訓練/測試切分上測得,"
    "不代表真人手勢辨識的實際表現。真實表現需要用 collect_real_data.py "
    "錄自己的手勢資料後重新訓練評估。"
)
