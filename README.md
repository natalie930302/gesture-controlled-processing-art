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

- **`src/generate_gesture_templates.py`**:在 10 維特徵空間手動設計 5 種手勢(fist/open_palm/point/peace/thumbs_up)的「典型中心點」生成合成樣本。**這不是真人手勢量測資料**,只是為了讓整條 pipeline(特徵設計→訓練→分類→OSC→Processing)完整可跑、可展示。
- **資料生成套用了 Domain Randomization**(Tobin et al., 2017):不是單純在一個固定中心點外加同質高斯雜訊,而是先隨機生成20個「虛擬個體」各自的系統性偏移(population-level variation,模擬不同人比同一個手勢會有系統性差異),同一個體重複比出的樣本再加一層較小的雜訊(within-person variation),另外以4%機率模擬 MediaPipe 追蹤誤判造成的異常偏移。這是階層式的變異結構,比原本單層同質雜訊更貼近真實資料的樣子——但這個改動**沒辦法用真實資料驗證有沒有真的比較好**,誠實的說法是生成過程更貼近文獻建議的做法,不是保證分類器因此更準。
- **`src/train_classifier.py`** 在合成資料上訓練 SVM,測試集準確率 0.997——這個數字只反映合成資料本身分得很開,**不代表真實辨識準確率**,腳本執行完會印出這個提醒。
- **`src/collect_real_data.py`**:需要你自己開 webcam 執行,對著鏡頭比出每種手勢按空白鍵錄製,存成 `data/real_gestures.npz`。錄完後把 `train_classifier.py` 的資料來源從 `synthetic_gestures.npz` 換成 `real_gestures.npz` 重新訓練,才會得到有意義的真實準確率。**這一步需要你本人操作**,我沒有辦法幫你錄製手勢影像。

## 與理論的關聯

合成資料訓練出的高準確率跟真實辨識能力之間的落差,對應機器學習裡的 **Sim-to-Real Gap(模擬到真實的落差)/ Distribution Shift(分布偏移)**:分類器在訓練分布上表現完美,不代表在真實分布(不同的手型、角度、光線、鏡頭誤差)上也一樣好,兩個分布之間的差距就是問題所在。這是機器人學/電腦視覺裡一個獨立的研究子領域,**Domain Randomization**(Tobin, J. et al., "Domain Randomization for Transferring Deep Neural Networks from Simulation to the Real World", IROS 2017)正是因應這個問題發展出來的代表性方法之一——核心想法是隨機化模擬環境裡足夠多的參數,讓訓練分布的變異範圍蓋過真實世界的變異,而不是只模擬一個「乾淨」的單一情境。這個專案的資料生成邏輯已經套用了這個精神(見上方說明),跟 Portfolio 裡另外幾個「小資料下微調失效」的案例是同一個大主題的不同側面:**當真實標註資料不足時,不管是「乾脆不訓練、硬寫規則」「用合成資料頂替」還是「直接微調」,都各自有各自的失效模式,合成資料最危險的地方在於它會製造一個看起來很漂亮、但具有誤導性的高分**。

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
