"""
【這支腳本需要你自己開webcam執行,才能錄到真實手勢資料】

用法:
    python collect_real_data.py <手勢名稱,例如 fist / open_palm / point / peace / thumbs_up>

執行後會開啟攝影機,對著鏡頭比出該手勢,按空白鍵擷取一筆樣本(建議每種手勢錄
50~100筆,錄的時候手的角度、距離鏡頭遠近、左右手都可以變化,這樣訓練出來的
分類器才會比合成資料更 robust)。按 q 離開。

錄完所有手勢後,樣本會累積存在 ../data/real_gestures.npz,
執行 train_classifier.py 前把資料來源從 synthetic_gestures.npz 換成
real_gestures.npz(或合併兩者),就能用真實資料重新訓練分類器。
"""
import sys
import os
import cv2
import mediapipe as mp
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from features import landmarks_to_features

def main():
    if len(sys.argv) < 2:
        print("用法: python collect_real_data.py <手勢名稱>")
        print("建議手勢名稱: fist, open_palm, point, peace, thumbs_up")
        sys.exit(1)

    label = sys.argv[1]
    out_path = "../data/real_gestures.npz"

    if os.path.exists(out_path):
        data = np.load(out_path, allow_pickle=True)
        X, y = list(data["X"]), list(data["y"])
    else:
        X, y = [], []

    mp_hands = mp.solutions.hands
    mp_drawing = mp.solutions.drawing_utils
    hands = mp_hands.Hands(static_image_mode=False, max_num_hands=1,
                            min_detection_confidence=0.7, min_tracking_confidence=0.5)

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("無法開啟攝影機")
        sys.exit(1)

    count_this_session = 0
    print(f"手勢: {label} | 空白鍵=擷取一筆  q=結束")

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame = cv2.flip(frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = hands.process(rgb)

        current_feat = None
        if results.multi_hand_landmarks:
            hand_landmarks = results.multi_hand_landmarks[0]
            mp_drawing.draw_landmarks(frame, hand_landmarks, mp_hands.HAND_CONNECTIONS)
            pts = [(lm.x, lm.y, lm.z) for lm in hand_landmarks.landmark]
            current_feat = landmarks_to_features(pts)

        cv2.putText(frame, f"gesture: {label}  collected: {count_this_session}",
                    (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.putText(frame, "SPACE=capture  q=quit", (10, 60),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
        cv2.imshow("collect_real_data", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord(" ") and current_feat is not None:
            X.append(current_feat)
            y.append(label)
            count_this_session += 1
            print(f"擷取第 {count_this_session} 筆")
        elif key == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()
    hands.close()

    if count_this_session > 0:
        os.makedirs("../data", exist_ok=True)
        np.savez(out_path, X=np.array(X, dtype=np.float32), y=np.array(y))
        print(f"已儲存,{label} 這次新增 {count_this_session} 筆,累計 {len(X)} 筆於 {out_path}")
    else:
        print("這次沒有擷取到任何樣本")

if __name__ == "__main__":
    main()
