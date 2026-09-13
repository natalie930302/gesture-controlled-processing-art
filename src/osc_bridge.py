"""
即時執行:開啟webcam -> MediaPipe偵測手部landmark -> features.py轉成幾何特徵
-> gesture_classifier.joblib分類 -> 透過OSC送到Processing,即時驅動視覺效果。

需要先執行 train_classifier.py(用合成資料或真實資料皆可)產生
data/gesture_classifier.joblib,再啟動 Processing 端的
processing_sketch/gesture_terrain/gesture_terrain.pde 監聽 OSC。

OSC 訊息格式:
  /gesture  (string手勢名稱, float openness張開度0~1, float confidence信心值0~1,
             float palmX手掌中心x座標0~1, float palmY手掌中心y座標0~1,
             float tipX食指指尖x座標0~1, float tipY食指指尖y座標0~1)
  palmX/palmY/tipX/tipY 只用來當視覺效果裡的位置座標(取代滑鼠座標),不是分類器的
  輸入特徵,所以不影響 features.py 的手勢辨識不變性設計(對手掌大小/位置/旋轉不變)。

  手勢名稱就是分類器認得的 fist/open_palm/point/peace/thumbs_up 這五種,直接原樣送
  出去,不做任何改名/覆蓋。（先前試過額外訓練一個"rain"手型、也試過把peace改名送成
  "rain"、還試過用手掌位置時間序列偵測動態搖晃——都拿掉了,peace 這個名字本身
  在 Processing 端就代表下雨效果的觸發手勢,不需要中間再繞一層改名。)

  預設不顯示攝影機除錯視窗(手勢名稱/openness/confidence Processing畫面左上角
  本來就有顯示,不用再開第二個視窗重複看),使用者只會看到Processing那一個畫面。
  想除錯手部偵測準不準時,加 --show-camera 參數就會照舊開攝影機預覽視窗。
"""
import argparse
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--show-camera", action="store_true",
                         help="顯示攝影機除錯視窗(預設不顯示,只有這個Python背景程式跟"
                              "Processing的藝術畫面,不用同時開兩個看得見的視窗)")
    args = parser.parse_args()

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

    quit_hint = "按 q 結束" if args.show_camera else "按 Ctrl+C 結束"
    print(f"開始傳送 OSC 到 {OSC_IP}:{OSC_PORT} (address=/gesture)  {quit_hint}")

    try:
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
                pts = [(lm.x, lm.y, lm.z) for lm in hand_landmarks.landmark]
                feat = landmarks_to_features(pts)
                openness = float(np.clip(feat[-1] / 2.0, 0, 1))  # 粗略正規化到0~1

                probs = clf.predict_proba([feat])[0]
                idx = int(np.argmax(probs))
                gesture = clf.classes_[idx]
                confidence = float(probs[idx])

                # 手掌中心(手根+四指根部關節平均),只當視覺效果的位置座標用,
                # 不是分類器特徵,所以不影響 features.py 對手掌位置的不變性設計
                palm_x = float(np.mean([pts[i][0] for i in (0, 5, 9, 13, 17)]))
                palm_y = float(np.mean([pts[i][1] for i in (0, 5, 9, 13, 17)]))
                # 食指指尖(landmark 8),給「食指指向」手勢當魚群的目標位置用
                tip_x = float(pts[8][0])
                tip_y = float(pts[8][1])

                client.send_message("/gesture", [gesture, openness, confidence, palm_x, palm_y, tip_x, tip_y])

            if args.show_camera:
                if results.multi_hand_landmarks:
                    mp_drawing.draw_landmarks(frame, results.multi_hand_landmarks[0], mp_hands.HAND_CONNECTIONS)
                cv2.putText(frame, f"{gesture}  openness={openness:.2f}  conf={confidence:.2f}",
                            (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                cv2.imshow("osc_bridge (q=quit)", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
    except KeyboardInterrupt:
        pass

    cap.release()
    cv2.destroyAllWindows()
    hands.close()

if __name__ == "__main__":
    main()
