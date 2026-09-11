"""
即時執行:開啟webcam -> MediaPipe偵測手部landmark -> features.py轉成幾何特徵
-> gesture_classifier.joblib分類 -> 透過OSC送到Processing,即時驅動視覺效果。

需要先執行 train_classifier.py(用合成資料或真實資料皆可)產生
data/gesture_classifier.joblib,再啟動 Processing 端的
processing_sketch/gesture_terrain/gesture_terrain.pde 監聽 OSC。

OSC 訊息格式:
  /gesture  (string手勢名稱, float openness張開度0~1, float confidence信心值0~1)
"""
import os
import sys
import cv2
import mediapipe as mp
import numpy as np
import joblib
from pythonosc import udp_client

sys.path.insert(0, os.path.dirname(__file__))
from features import landmarks_to_features

OSC_IP = "127.0.0.1"
OSC_PORT = 8000

def main():
    # 優先用真人資料訓練的分類器(準確率0.992,見train_classifier_real.py的結果),
    # 沒有的話才退回合成資料訓練的版本(準確率只有0.756,見README的sim-to-real gap量化)
    real_model_path = "../data/gesture_classifier_real.joblib"
    model_path = real_model_path if os.path.exists(real_model_path) else "../data/gesture_classifier.joblib"
    print(f"載入分類器: {model_path}")
    clf = joblib.load(model_path)
    client = udp_client.SimpleUDPClient(OSC_IP, OSC_PORT)

    mp_hands = mp.solutions.hands
    mp_drawing = mp.solutions.drawing_utils
    hands = mp_hands.Hands(static_image_mode=False, max_num_hands=1,
                            min_detection_confidence=0.7, min_tracking_confidence=0.5)

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("無法開啟攝影機")
        sys.exit(1)

    print(f"開始傳送 OSC 到 {OSC_IP}:{OSC_PORT} (address=/gesture)  按 q 結束")

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame = cv2.flip(frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = hands.process(rgb)

        gesture, openness, confidence = "none", 0.0, 0.0

        if results.multi_hand_landmarks:
            hand_landmarks = results.multi_hand_landmarks[0]
            mp_drawing.draw_landmarks(frame, hand_landmarks, mp_hands.HAND_CONNECTIONS)
            pts = [(lm.x, lm.y, lm.z) for lm in hand_landmarks.landmark]
            feat = landmarks_to_features(pts)
            openness = float(np.clip(feat[-1] / 2.0, 0, 1))  # 粗略正規化到0~1

            probs = clf.predict_proba([feat])[0]
            idx = int(np.argmax(probs))
            gesture = clf.classes_[idx]
            confidence = float(probs[idx])

            client.send_message("/gesture", [gesture, openness, confidence])

        cv2.putText(frame, f"{gesture}  openness={openness:.2f}  conf={confidence:.2f}",
                    (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.imshow("osc_bridge (q=quit)", frame)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()
    hands.close()

if __name__ == "__main__":
    main()
