"""
把 MediaPipe 的 21 個手部關鍵點,轉換成跟手掌大小/位置/旋轉無關的幾何特徵,
給分類器當輸入。比直接數手指數量(手勢辨識專案原本的做法)更豐富、更適合訓練模型。

特徵設計:
- 5根手指指尖到手掌中心的正規化距離(5維)
- 相鄰手指指尖之間的張開角度(4維)
- 手掌的整體「張開程度」(所有指尖距離的平均,1維)

MediaPipe landmark 編號: 0=手腕, 4=拇指尖, 8=食指尖, 12=中指尖, 16=無名指尖, 20=小指尖
"""
import numpy as np

WRIST = 0
TIPS = [4, 8, 12, 16, 20]
MCPS = [2, 5, 9, 13, 17]  # 各手指根部關節,用來算手掌中心


def landmarks_to_features(landmarks):
    """
    landmarks: list of 21 個 (x, y, z) tuple,MediaPipe 輸出格式
    回傳: numpy array,10維特徵
    """
    pts = np.array(landmarks)  # shape (21, 3)
    wrist = pts[WRIST]
    palm_center = pts[MCPS].mean(axis=0)

    # 手掌大小(用來正規化,消除手離鏡頭遠近的影響)
    palm_size = np.linalg.norm(pts[MCPS[0]] - pts[MCPS[-1]]) + 1e-6

    # 1. 五指指尖到手掌中心的正規化距離
    tip_dists = [np.linalg.norm(pts[t] - palm_center) / palm_size for t in TIPS]

    # 2. 相鄰指尖之間的張開角度(以手掌中心為頂點)
    angles = []
    for i in range(len(TIPS) - 1):
        v1 = pts[TIPS[i]] - palm_center
        v2 = pts[TIPS[i + 1]] - palm_center
        cos_a = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6)
        angles.append(np.arccos(np.clip(cos_a, -1, 1)))

    # 3. 整體張開程度
    openness = float(np.mean(tip_dists))

    return np.array(tip_dists + angles + [openness], dtype=np.float32)


FEATURE_NAMES = [
    "thumb_dist", "index_dist", "middle_dist", "ring_dist", "pinky_dist",
    "angle_thumb_index", "angle_index_middle", "angle_middle_ring", "angle_ring_pinky",
    "openness",
]
