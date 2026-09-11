"""
跨資料集泛化測試:目前的分類器只在你自己的手(491筆自己錄的真人資料)上驗證過,
這支腳本用一個完全不同的人、不同的收集環境的公開資料集(Kaggle:
youssefelebiary/hand-gesture-landmarks,364筆,MediaPipe 21個關鍵點格式)測試
「換一個人比手勢,分類器還準不準」——這是手勢辨識文獻裡常見的關鍵問題
(cross-subject generalization),跟單純的sim-to-real gap是不同層次的問題:
sim-to-real問的是「合成資料 vs 真實資料」,cross-subject問的是「在我的真實資料上
訓練的模型,能不能類化到別人的真實資料」,兩者都是誠實評估模型能力的必要步驟。

資料集手勢類別要對應到我們的5類:
  open/open_inverted       -> open_palm
  close/close_inverted     -> fist
  point/point_inverted     -> point
  peace/peace_inverted     -> peace
  thumb/thumb_inverted     -> thumbs_up
  rock/rock_inverted       -> (我們沒有這個類別,排除)

資料集本身landmark_0(手腕)固定在(0,0,0)(已經做過wrist-centering),但這不影響
features.py的計算——我們的特徵是「相對於掌心的距離/角度」,不依賴手腕的絕對座標。
"""
import sys
import os
import numpy as np
import pandas as pd
import joblib

sys.path.insert(0, os.path.dirname(__file__))
from features import landmarks_to_features

LABEL_MAP = {
    "open": "open_palm", "open_inverted": "open_palm",
    "close": "fist", "close_inverted": "fist",
    "point": "point", "point_inverted": "point",
    "peace": "peace", "peace_inverted": "peace",
    "thumb": "thumbs_up", "thumb_inverted": "thumbs_up",
}


def load_kaggle_dataset(csv_path):
    df = pd.read_csv(csv_path)
    df.columns = [c.strip() for c in df.columns]
    df["gesture_label"] = df["gesture_label"].str.strip()
    df = df[df["gesture_label"].isin(LABEL_MAP.keys())].reset_index(drop=True)

    X, y = [], []
    for _, row in df.iterrows():
        landmarks = [(row[f"landmark_{i}_x"], row[f"landmark_{i}_y"], row[f"landmark_{i}_z"]) for i in range(21)]
        X.append(landmarks_to_features(landmarks))
        y.append(LABEL_MAP[row["gesture_label"]])
    return np.array(X, dtype=np.float32), np.array(y)


def main():
    if len(sys.argv) < 2:
        print("用法: python eval_cross_dataset.py <kaggle_gesture_landmarks.csv路徑>")
        print("資料來源: https://www.kaggle.com/datasets/youssefelebiary/hand-gesture-landmarks")
        sys.exit(1)

    X, y = load_kaggle_dataset(sys.argv[1])
    print(f"跨資料集測試樣本數: {len(X)}")
    for label in sorted(set(y)):
        print(f"  {label}: {(y == label).sum()} 筆")

    real_model_path = "../data/gesture_classifier_real.joblib"
    if not os.path.exists(real_model_path):
        print("找不到 ../data/gesture_classifier_real.joblib,請先跑 train_classifier_real.py")
        sys.exit(1)

    clf = joblib.load(real_model_path)
    pred = clf.predict(X)
    acc = (pred == y).mean()

    from sklearn.metrics import classification_report
    print(f"\n跨資料集(別人的手)準確率: {acc:.3f}")
    print(classification_report(y, pred, zero_division=0))

    print(
        f"\n對照:同一個分類器在自己錄的真人測試集上準確率是 0.992"
        f"(train_classifier_real.py 的結果),跟這裡的 {acc:.3f} 之間的差距,"
        f"反映的是 cross-subject generalization gap,不是 sim-to-real gap——"
        f"這是誠實評估「這個系統換一個人用還可不可靠」的關鍵數字。"
    )


if __name__ == "__main__":
    main()
