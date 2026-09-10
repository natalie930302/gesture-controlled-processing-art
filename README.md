# gesture-controlled-processing-art

用 MediaPipe 手部偵測 + 自己訓練的手勢分類器,即時透過 OSC 驅動 Processing 的生成藝術(改編自課堂作業 `Noise_Terrain.pde` 的 3D noise 地形)。動機是把課程作業累積的「手勢辨識」(`課程與多媒體/手勢辨識/detect_gesture.py`,原本是純規則式數手指數量控制 Arduino小車)跟「Processing 創意編碼」兩塊獨立作業,結合成一個用真正訓練出來的模型驅動的互動藝術作品。

## 架構

```
webcam --MediaPipe--> 21個手部關鍵點 --features.py--> 10維幾何特徵
                                                          |
                                                  訓練好的手勢分類器(SVM)
                                                          |
                                                    python-osc 送出
                                                          |
                                                          v
                                    Processing (oscP5監聽) --> 即時視覺效果
```

## 為什麼用幾何特徵,不是直接數手指數量

原本 `detect_gesture.py` 是比較指尖/關節的 y 座標,規則式判斷手指是否伸直,再用 if-else 對應到固定指令,沒有用到任何模型訓練。這個專案改成:先把 21 個 landmark 轉換成 10 維、跟手掌大小/位置/旋轉無關的幾何特徵(`src/features.py`:5指指尖到掌心距離、4個指間張角、1個整體張開度),再用這組特徵訓練分類器——這樣才是「訓練模型」而不是硬寫規則,也更容易之後加入更多手勢類別或换更複雜的分類器。

## 誠實說明:合成資料 vs. 真實資料

- **`src/generate_gesture_templates.py`**:在 10 維特徵空間手動設計 5 種手勢(fist/open_palm/point/peace/thumbs_up)的「典型中心點」,加高斯雜訊生成 1500 筆合成樣本。**這不是真人手勢量測資料**,只是為了讓整條 pipeline(特徵設計→訓練→分類→OSC→Processing)完整可跑、可展示。
- **`src/train_classifier.py`** 在合成資料上訓練 SVM,測試集準確率 1.000——這個數字只反映合成資料本身分得很開,**不代表真實辨識準確率**,腳本執行完會印出這個提醒。
- **`src/collect_real_data.py`**:需要你自己開 webcam 執行,對著鏡頭比出每種手勢按空白鍵錄製,存成 `data/real_gestures.npz`。錄完後把 `train_classifier.py` 的資料來源從 `synthetic_gestures.npz` 換成 `real_gestures.npz` 重新訓練,才會得到有意義的真實準確率。**這一步需要你本人操作**,我沒有辦法幫你錄製手勢影像。

## 手勢 → 視覺效果對應

| 手勢 | 效果 |
|---|---|
| open_palm | 地形流動加速,配色偏冷色 |
| fist | 流動變慢,配色偏暖色 |
| point | 鏡頭依張開度左右旋轉 |
| peace | 放大地形網格尺度 |
| thumbs_up | 切換線框/實心顯示模式 |
| openness(連續值0~1) | 微調流動速度,避免效果死板切換 |

## 如何執行

```bash
# 1. 產生合成資料並訓練分類器(或改用真實資料,見上方說明)
cd src
python generate_gesture_templates.py
python train_classifier.py

# 2. 用 Processing IDE 開啟 processing_sketch/gesture_terrain/gesture_terrain.pde
#    先安裝 oscP5 library(Sketch > Import Library > Add Library... 搜尋 oscP5),按執行

# 3. 開啟webcam,即時辨識手勢並送出OSC
python osc_bridge.py
```

## 檔案結構

```
src/
  features.py                    landmark -> 10維幾何特徵
  generate_gesture_templates.py  合成訓練資料
  train_classifier.py            訓練SVM分類器
  collect_real_data.py           【需要你自己執行】錄製真實手勢資料
  osc_bridge.py                  即時webcam辨識 + OSC傳送
data/
  synthetic_gestures.npz         合成訓練資料
  gesture_names.json             手勢類別名稱
  gesture_classifier.joblib      訓練好的分類器
processing_sketch/
  gesture_terrain/gesture_terrain.pde   接收OSC、驅動視覺效果
```

## 後續可以做的改進

- 用真實資料重新訓練(見上),並且用 `student_id`-like 的切分方式(不同錄製時段/不同光線)測試泛化能力,而不是同一次錄製內隨機切分
- 加入時序資訊(不只用單一frame的手勢,而是一小段時間內的手勢變化軌跡),可以辨識更豐富的動態手勢
- 目前 `train_classifier.py` 用固定的 SVM 超參數,可以加入 cross-validation 做超參數搜尋
