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

## Sim-to-Real Gap:已經用真實資料量化驗證過了

錄了 491 筆真人手勢資料(fist 47、open_palm 129、point 108、peace 116、thumbs_up 91),`src/train_classifier_real.py` 直接量出合成資料訓練的分類器,套用在真人資料上到底差多少:

| 分類器 | 測試對象 | 準確率 |
|---|---|---|
| 合成資料訓練 | 真人測試集(n=123) | **0.756** |
| **真人資料訓練** | 真人測試集(n=123) | **0.992** |

**差距 23.6 個百分點**——這不是理論推測,是真的量出來的數字,證實了下方理論段落一直在講的 Sim-to-Real Gap 確實存在,而且幅度不小。`osc_bridge.py` 已經改成優先載入真人資料訓練的分類器(`gesture_classifier_real.joblib`),準確率 0.992 這個版本才是實際在跑的模型。

`src/few_shot_calibrate.py` 用 leave-one-out 方式在全部491筆真人資料上驗證,準確率 0.892——比完整訓練/測試切分的 0.992 略低(leave-one-out比較嚴格,每次只用剩下的資料重估原型,而且prototype-based分類本身不如SVM在這個資料量級表現好),但同樣遠高於合成資料訓練的0.756,方向一致。

### 方法論(仍然保留,現在有真實數字佐證)

- **`src/generate_gesture_templates.py`**:在 10 維特徵空間手動設計 5 種手勢的「典型中心點」生成合成樣本,套用 **Domain Randomization**(Tobin et al., 2017)的階層式變異設計(虛擬個體系統性偏移+個體內雜訊+模擬MediaPipe追蹤誤判)
- **`src/train_classifier.py`**:在合成資料上訓練 SVM,測試集準確率 0.997(只反映合成資料本身分得很開,不代表真實辨識準確率——上面已經證實了)
- **`src/collect_real_data.py`**:錄製真人資料的工具,這次錄了491筆(遠超過建議的50~100筆/手勢)
- **`src/few_shot_calibrate.py`**:少樣本原型校準(Prototypical Networks, Snell et al. 2017),適合只錄了2~5筆時使用
- **`src/train_classifier_real.py`**(新增):完整重新訓練+量化sim-to-real gap的主要腳本

> `data/real_gestures.npz`、`data/gesture_classifier_real.joblib` 都已加進 `.gitignore`,不進版控——後者雖然是「訓練好的模型」,但因為是SVM+RBF kernel,實際上把84筆真實訓練樣本當作support vector原封不動存在模型檔裡,等於間接包含真人手勢生物特徵資料,所以比照其他專案「真實個資不上public repo」的原則處理。

## Cross-Subject Generalization:換一個人比手勢,還準不準?

Sim-to-Real Gap 問的是「合成資料 vs. 真實資料」,但還有另一個常被手勢辨識文獻提到的問題沒驗證過:**這個分類器只在我自己的手上訓練/測試過,換一個完全不認識的人來比,還可靠嗎?**這是不同層次的泛化問題,單純錄更多自己的資料解決不了。

用 Kaggle 上 [`youssefelebiary/hand-gesture-landmarks`](https://www.kaggle.com/datasets/youssefelebiary/hand-gesture-landmarks)(MIT license,已存一份副本在 `data/external/`)測試——這是完全不同的人、不同收集環境錄的 MediaPipe landmark 資料,篩選出跟我們對應的5類手勢共295筆:

| 測試對象 | 準確率 |
|---|---|
| 自己錄的真人測試集(同分佈) | 0.992 |
| **Kaggle 公開資料集(不同的人,跨資料集)** | **0.939** |

差距只有 5.3 個百分點,比原本擔心的還小——代表 `features.py` 設計的幾何特徵(距離/角度都經過 palm_size 正規化,跟手掌大小、位置、部分旋轉無關)確實有一定的跨個體泛化能力,不是只認得我自己的手。`fist` 跟 `thumbs_up` 這兩類在跨資料集測試裡掉得比較多(precision/recall都在0.8~0.9之間),可能是這兩個手勢的幾何形狀本來就比較容易因人而異(拇指擺放角度、握拳鬆緊程度),值得之後多收集這兩類的資料加強。

執行方式:`python eval_cross_dataset.py ../data/external/kaggle_gesture_landmarks.csv`

## 與理論的關聯

合成資料訓練出的高準確率跟真實辨識能力之間的落差,對應機器學習裡的 **Sim-to-Real Gap(模擬到真實的落差)/ Distribution Shift(分布偏移)**:分類器在訓練分布上表現完美,不代表在真實分布(不同的手型、角度、光線、鏡頭誤差)上也一樣好,兩個分布之間的差距就是問題所在。這是機器人學/電腦視覺裡一個獨立的研究子領域,**Domain Randomization**(Tobin, J. et al., "Domain Randomization for Transferring Deep Neural Networks from Simulation to the Real World", IROS 2017)正是因應這個問題發展出來的代表性方法之一——核心想法是隨機化模擬環境裡足夠多的參數,讓訓練分布的變異範圍蓋過真實世界的變異,而不是只模擬一個「乾淨」的單一情境。這個專案的資料生成邏輯已經套用了這個精神(見上方說明),跟 Portfolio 裡另外幾個「小資料下微調失效」的案例是同一個大主題的不同側面:**當真實標註資料不足時,不管是「乾脆不訓練、硬寫規則」「用合成資料頂替」還是「直接微調」,都各自有各自的失效模式,合成資料最危險的地方在於它會製造一個看起來很漂亮、但具有誤導性的高分**。

## 研究歷程

### 研究動機與路徑

起點是兩份互相獨立的課堂作業:一份是純規則式的手勢辨識(比較指尖座標的if-else判斷),一份是Processing生成藝術。單純把兩個接起來(規則判斷觸發視覺效果)不需要任何模型訓練,所以研究路徑的第一個決定,是把手勢辨識從「寫規則」換成「訓練分類器」——這個決定本身就要求先做特徵工程(10維幾何特徵,對手掌大小/位置/部分旋轉不變),而不是直接把21個原始landmark丟給分類器。

沒有真人資料的情況下,先用 Domain Randomization 生成合成資料訓練,測試集準確率0.997。這個數字本身就是後續研究路徑的轉折點:**0.997 高到不合理,如果直接拿來當「成果」寫進README,就是一個具有誤導性的數字**。所以下一步不是停在這裡,而是想辦法讓「用真人資料驗證」這件事變得可行——先用 Prototypical Networks 做少樣本校準,把驗證門檻從建議的50~100筆/手勢降到2~5筆,才讓「自己錄491筆真人資料驗證」這件事在時間允許的範圍內做得到。真人資料驗證量出Sim-to-Real Gap是23.6個百分點,證實了合成資料分數的誤導性。

驗證到這裡還沒結束:Sim-to-Real Gap問的是「合成 vs. 真實」,但另一個常被忽略的問題是「這個模型是不是只認得我自己的手」。這是不同的泛化軸線,不能用同一組數據回答,所以額外去找了一個跟自己錄的資料完全獨立(不同人、不同環境)的 Kaggle 資料集做跨資料集驗證,量出只掉5.3個百分點——確認特徵工程的正規化設計(對手掌大小/位置不變)確實有跨個體的泛化能力,不是只在自己的資料上表現好看。

### 研究方法

- **不變性導向的特徵設計**:10維特徵全部經過手掌大小正規化,設計時就是為了讓分類器學到的是「手勢的幾何形狀」而不是「這個人的手有多大、放在畫面哪個位置」——這個設計選擇直接決定了後面跨資料集測試會不會成功
- **階層式合成資料變異**(Domain Randomization, Tobin et al. 2017):個體間系統性偏移 + 個體內雜訊 + 模擬追蹤誤判三層疊加,而不是單一層同質高斯雜訊,讓合成資料的變異範圍更貼近真實世界的分散程度
- **把兩種泛化問題分開驗證,不能混為一談**:Sim-to-Real Gap(訓練分布 vs. 部署分布)跟 Cross-Subject Generalization(換人測試)是兩個不同的問題,各自需要不同的資料源(自己錄的真人資料 vs. 外部獨立資料集)才能分別驗證
- **對「太漂亮的數字」保持警覺**:0.997的合成資料準確率沒有被當作最終結果直接寫進成果,而是被當作「需要進一步驗證」的訊號去推動後續研究

### 遇到的困難

- **SVM(RBF kernel)的隱私問題**:訓練好的分類器把84筆真實訓練樣本當作 support vector 原封不動存在模型檔裡,等於模型檔本身間接包含真人手勢的生物特徵資料——這不是一開始預期的問題,是檢查模型內部結構時才發現的,最後決定把訓練好的模型檔排除在 `.gitignore` 之外,不上public repo,即使這是專案的核心產出之一
- **合成資料的「表現太好」本身就是一個要除錯的訊號**:0.997 不是一個要慶祝的數字,是一個要懷疑的數字——這跟其他專案「結果不如預期」的除錯不同,這裡是「結果好到不合理」也要停下來檢查
- **實際錄製491筆真人資料的執行成本**:每個手勢要重複多次、涵蓋不同角度跟握持鬆緊度,是這個Portfolio裡少數需要實際花時間做人工資料收集,而不是單純寫程式跑實驗的環節

### 時程(依實際執行順序)

1. 設計10維幾何特徵工程,取代原本規則式的手指計數
2. 用 Domain Randomization 生成合成資料,訓練SVM分類器(合成測試集0.997,標記為不可靠、需要真人驗證)
3. 設計 Prototypical Networks 少樣本校準方法,降低真人資料驗證的門檻
4. 自己實際錄製491筆真人手勢資料,量化 Sim-to-Real Gap(23.6個百分點)
5. 找到獨立的 Kaggle 外部資料集,驗證 Cross-Subject Generalization(跨個體只掉5.3個百分點)

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
  collect_real_data.py           【需要你自己執行】錄製真實手勢資料(建議50~100筆/手勢)
  few_shot_calibrate.py          用少量真人樣本(2~5筆/手勢)校準,門檻更低
  train_classifier_real.py       用真人資料訓練+量化sim-to-real gap
  eval_cross_dataset.py          用Kaggle公開資料集測試跨受試者泛化
  osc_bridge.py                  即時webcam辨識 + OSC傳送
data/
  synthetic_gestures.npz         合成訓練資料
  gesture_names.json             手勢類別名稱
  gesture_classifier.joblib      合成資料訓練的分類器
  sim_to_real_gap_results.json   sim-to-real gap量化結果
  external/kaggle_gesture_landmarks.csv   跨資料集泛化測試用(MIT license)
processing_sketch/
  gesture_terrain/gesture_terrain.pde   接收OSC、驅動視覺效果
```

## 後續可以做的改進

- 用真實資料重新訓練(見上),並且用 `student_id`-like 的切分方式(不同錄製時段/不同光線)測試泛化能力,而不是同一次錄製內隨機切分
- 加入時序資訊(不只用單一frame的手勢,而是一小段時間內的手勢變化軌跡),可以辨識更豐富的動態手勢
- 目前 `train_classifier.py` 用固定的 SVM 超參數,可以加入 cross-validation 做超參數搜尋
