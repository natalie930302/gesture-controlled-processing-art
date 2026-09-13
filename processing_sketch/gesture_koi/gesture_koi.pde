/*
手勢控制的錦鯉池生成藝術。
以「Processing 創意編碼」課堂期末小組作業(Final Group Project:水波方程 + boid式
錦鯉群 + 荷葉碰撞)原始程式碼為準,配色、荷葉畫法、水色全部照原版不修改。

輸入完全來自 Python 端(osc_bridge.py)透過 OSC 傳來的手勢辨識結果,不再支援滑鼠
輸入(已全面停用)。每個手勢對應一件事,彼此不重疊:
  食指指(point)  → 魚群被吸引往指尖方向游去(其他手勢完全不影響魚的行為)
  拳頭(fist)     → 在手掌位置持續產生水波(水波同時會推開附近荷葉)
  剪刀手(peace)   → 下雨:在畫面各處隨機灑幾個水波點(原本另外訓練過一個獨立的
                    "rain"手型、也試過動態搖晃偵測,都拿掉了,直接用peace這個
                    分類器本來就認得、辨識度很高的手型觸發)
  比讚(thumbs_up) → 手勢剛比出來的那一刻,直接在手掌位置生一片新荷葉
  手掌展開(open_palm)/peace/沒偵測到手 → 預設狀態,不做任何事

需要先安裝 oscP5 library(Processing IDE: Sketch > Import Library > Add Library... 搜尋 oscP5)。
*/
import oscP5.*;

OscP5 oscP5;

int H, W;
ArrayList<Koi> koi = new ArrayList<Koi>();
ArrayList<LotusLeaf> lotusLeaf = new ArrayList<LotusLeaf>();

float[][] current;
float[][] previous;
float dampening = 0.99;

String currentGesture = "none";
String lastGesture = "none";
float openness = 0.4;
float confidence = 0.8;
float handX, handY;
float tipX, tipY;
boolean haveHand = false;
int ambientRippleCooldown = 0;
int leafSpawnCooldown = 0;
int fistRippleCooldown = 0;
int rainCooldown = 0;
// peace手勢連續比著的幀數——用來讓「雨」越下越大,不是固定強度。手放開/換手勢
// 就歸零,重新開始累積
int peaceHoldFrames = 0;

void setup() {
  size(800, 600);
  W = width;
  H = height;
  // 除錯文字裡有中文,預設字型沒有對應字圖會顯示成方塊,換成系統內建的中文字型
  textFont(createFont("Microsoft JhengHei", 13, true));
  current = new float[W][H];
  previous = new float[W][H];
  // 魚的數量固定維持3隻
  for (int i = 0; i < 3; i++) {
    koi.add(new Koi(200, 100 + i * 100));
  }
  for (int i = 0; i < 10; i++) {
    lotusLeaf.add(new LotusLeaf());
  }

  handX = width / 2;
  handY = height / 2;
  oscP5 = new OscP5(this, 8000);
}

// 比讚:直接在手掌位置生一片新荷葉(不是從邊緣飄進來),像變出來的一樣。
// 跟自動補充的edge版分開,是因為使用者要的是「比讚的地方就長一片新的」,不是
// 隨機從畫面邊緣飄過來
void addHandLeaf() {
  LotusLeaf leaf = new LotusLeaf();
  leaf.x = handX;
  leaf.y = handY;
  leaf.vx = 0;
  leaf.vy = 0;
  leaf.growScale = 0;
  lotusLeaf.add(leaf);
}

// 直接在畫面可視範圍內的隨機座標長一片新荷葉出來(不是從邊緣飄進來),搭配
// growScale由小長大的動畫,看起來像原地冒出來的,不是從外面飄進來的
void addRandomLeaf() {
  LotusLeaf leaf = new LotusLeaf();
  leaf.x = random(W);
  leaf.y = random(H);
  leaf.vx = 0;
  leaf.vy = 0;
  leaf.growScale = 0;
  lotusLeaf.add(leaf);
}

// 荷葉數量低於5片時,在畫面可視範圍內隨機長一片新的出來——避免長時間下來荷葉被
// 推到重疊/消失導致畫面空空的情況。用冷卻時間讓新荷葉一片一片慢慢長出來,
// 不要一次噴一堆
void spawnEdgeLeafIfNeeded() {
  if (lotusLeaf.size() >= 5) return;
  leafSpawnCooldown--;
  if (leafSpawnCooldown > 0) return;
  // 間隔縮短(90~200幀 → 30~70幀),補荷葉的速度更快
  leafSpawnCooldown = int(random(30, 70));
  addRandomLeaf();
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/gesture")) {
    currentGesture = msg.get(0).stringValue();
    openness = msg.get(1).floatValue();
    confidence = msg.get(2).floatValue();
    if (msg.typetag().length() >= 5) {
      handX = constrain(msg.get(3).floatValue() * width, 0, width - 1);
      handY = constrain(msg.get(4).floatValue() * height, 0, height - 1);
      haveHand = true;
    }
    // 食指指尖座標(給「食指指」手勢當魚群目標位置用),沒收到就沿用上一次的值
    if (msg.typetag().length() >= 7) {
      tipX = constrain(msg.get(5).floatValue() * width, 0, width - 1);
      tipY = constrain(msg.get(6).floatValue() * height, 0, height - 1);
    }
  }
}

// 推開附近的荷葉
void pushNearbyLeaves(float x, float y) {
  for (LotusLeaf leaf : lotusLeaf) {
    float distance = dist(x, y, leaf.x, leaf.y);
    // 感應範圍加大(100→140),單次水波的力道也加大(乘3倍)——修完上面「50~100
    // 之間會反向吸過去」那個方向錯誤的bug後,使用者反饋還是覺得「有時候有影響
    // 有時候沒有」,重新檢視發現真正的原因是力道本來就偏弱(單次推力最多只有
    // 原本碰撞力道的量級),水波是一次性事件、不像手掌直接拖曳可以每幀持續施力,
    // 力道不夠強,靠近邊緣時的推擠就會不明顯到看起來像「沒反應」。加大範圍跟力道,
    // 讓單次水波的效果肉眼可見、感覺一致
    if (distance < 140) {
      // 找到「荷葉往水波方向移動」這個怪現象的原因了:這裡的角度算的是「從荷葉
      // 指向水波」的方向,再拿去當推力方向,等於把荷葉往水波那邊拉過去,完全反了。
      // 推力方向應該是「從水波指向荷葉」,才會是真的推開
      float angle = atan2(leaf.y - y, leaf.x - x);
      float force = constrain(map(distance, 0, 140, 1, 0), 0, 1) * 3;
      leaf.applyForce(force, angle);
    }
  }
}

// 在(x,y)附近一小片圓形範圍產生水波(不是單一像素),同時推開附近的荷葉——
// 水波跟荷葉的互動統一收在這一個函式裡,不管水波是哪裡來的(拳頭點擊、下雨、
// 環境隨機),只要有水波就會順便輕輕推一下附近的荷葉,做出「水波會影響荷葉」
// 的效果,不用另外維護兩套邏輯
void spawnRipple(float x, float y) {
  int ix = int(x);
  int iy = int(y);
  int r = 1;
  for (int dx = -r; dx <= r; dx++) {
    for (int dy = -r; dy <= r; dy++) {
      if (dx * dx + dy * dy <= r * r) {
        int px = ix + dx;
        int py = iy + dy;
        if (px >= 1 && px < width - 1 && py >= 1 && py < height - 1) {
          previous[px][py] = 160;
        }
      }
    }
  }
  pushNearbyLeaves(x, y);
}

void draw() {
  // 手勢對應的動作,每個手勢只做一件事,彼此不重疊:
  // 拳頭=在手掌位置持續點擊產生水波(順便推開附近荷葉);搖手=下雨般在畫面各處
  // 隨機灑幾個水波點;比讚=手勢剛比出來的那一刻(不是每一幀)生一片新荷葉;
  // 食指指的效果(魚群往指尖游去)在Koi.update()裡處理;手掌展開/peace/沒偵測到
  // 手=預設狀態,不做任何事
  if (haveHand && currentGesture.equals("fist")) {
    fistRippleCooldown--;
    if (fistRippleCooldown <= 0) {
      spawnRipple(handX, handY);
      // 冷卻時間縮短(14→6),拳頭停留時水波產生得更密集、反應更快
      fistRippleCooldown = 6;
    }
  }

  if (haveHand && currentGesture.equals("peace")) {
    // 比越久,雨下越大:intensity從0(剛比出來)在約5秒內慢慢爬到1(下滿),
    // 用intensity同時調大「每次灑幾滴」跟調短「間隔冷卻時間」,兩個一起加乘,
    // 雨勢變大的感覺才明顯
    peaceHoldFrames++;
    float intensity = constrain(map(peaceHoldFrames, 0, 300, 0, 1), 0, 1);
    rainCooldown--;
    if (rainCooldown <= 0) {
      int drops = int(map(intensity, 0, 1, 3, 14));
      for (int i = 0; i < drops; i++) {
        spawnRipple(random(2, width - 2), random(2, height - 2));
      }
      rainCooldown = int(map(intensity, 0, 1, 26, 5));
    }
  } else {
    peaceHoldFrames = 0;
  }

  if (haveHand && currentGesture.equals("thumbs_up") && !lastGesture.equals("thumbs_up")) {
    addHandLeaf();
  }
  lastGesture = currentGesture;

  // 環境自然波紋,不管手勢是什麼都會有,營造背景的水面波動感,一樣有冷卻時間
  ambientRippleCooldown--;
  if (ambientRippleCooldown <= 0) {
    spawnRipple(random(2, width - 2), random(2, height - 2));
    ambientRippleCooldown = int(random(50, 110));
  }

  spawnEdgeLeafIfNeeded();

  for (Koi v : koi) {
    v.draw();
  }
  loadPixels();
  for (int x = 1; x < width - 1; x++) {
    for (int y = 1; y < height - 1; y++) {
      color originalColor = get(x, y);

      float noiseValue = noise(x * 0.02, y * 0.02, frameCount * 0.02);
      float r = red(originalColor) + noiseValue * 100;
      float g = green(originalColor) + noiseValue * 100;
      float b = blue(originalColor) + noiseValue * 100;
      r = constrain(r, 0, 208);
      g = constrain(g, 0, 202);
      b = constrain(b, 0, 168);

      current[x][y] =
        (previous[x - 1][y] +
        previous[x + 1][y] +
        previous[x][y - 1] +
        previous[x][y + 1]) / 2 -
        current[x][y];
      current[x][y] = current[x][y] * dampening;

      int index = x + y * width;
      color c = lerpColor(color(r, g, b), color(255), current[x][y] / 60);
      pixels[index] = c;
    }
  }
  updatePixels();

  float[][] temp = previous;
  previous = current;
  current = temp;

  // 用倒序索引迴圈,才能安全地在畫的同時把飄出畫面太遠的荷葉移除掉——原本荷葉
  // 只會被推來推去、從來不會真的消失,陣列裡永遠有10片,導致「少於3片就補一片」
  // 的判斷永遠不會成立(count從沒真的降到3以下過),這是之前荷葉沒有飄進來的原因
  for (int i = lotusLeaf.size() - 1; i >= 0; i--) {
    LotusLeaf v = lotusLeaf.get(i);
    v.draw();
    // pad縮小(60→10):之前門檻設太遠,一般推擠的力道很難把荷葉真的推那麼遠出去,
    // 導致「畫面中荷葉數量」實際上還是一直不會降到3以下,補新荷葉的邏輯還是不會
    // 觸發。現在荷葉中心一超出畫面邊緣(加一點點緩衝)就算離開,判定會準確很多。
    //
    // 真正的bug找到了:這裡的pad(移除門檻)之前是r+10,比addEdgeLeaf()裡荷葉「生
    // 出來的位置」(r+20)還要小——也就是說新荷葉一出生,座標本來就已經超過這裡的
    // 移除門檻,同一幀馬上就被判定「已經離開畫面」刪掉,根本沒機會真的飄進來過。
    // 這就是比讚生不出新荷葉、荷葉數量也補不回3片以上的真正原因。移除門檻要設得
    // 比出生位置更寬鬆(更遠),新荷葉才不會一生出來就被自己的移除判斷刪掉
    float pad = v.r + 40;
    if (v.x < -pad || v.x > W + pad || v.y < -pad || v.y > H + pad) {
      lotusLeaf.remove(i);
    }
  }

  // 手掌位置十字準星,方便核對手掌跟魚群的空間關係(唯一保留的非原版元素,先前你要求過)
  if (haveHand) {
    noFill();
    stroke(255, 215, 90, 200);
    strokeWeight(2);
    ellipse(handX, handY, 26, 26);
    line(handX - 16, handY, handX + 16, handY);
    line(handX, handY - 16, handX, handY + 16);

    // 食指指的時候,額外標出指尖目標位置(魚群會往這裡游去),方便核對
    if (currentGesture.equals("point")) {
      stroke(120, 200, 255, 220);
      noFill();
      ellipse(tipX, tipY, 16, 16);
      line(tipX - 10, tipY, tipX + 10, tipY);
      line(tipX, tipY - 10, tipX, tipY + 10);
    }
  }

  // 除錯資訊:目前手勢+荷葉數量,方便直接看得出來荷葉數量到底有沒有真的變化
  noStroke();
  fill(0, 150);
  rect(6, 6, 210, 26);
  fill(255);
  textSize(13);
  text("手勢: " + currentGesture + "   荷葉: " + lotusLeaf.size(), 14, 24);
}

class Koi {
  float x, y, vx, vy, s, dx, dy, a, A, c0;
  float wiggleOffset, bendFactor;
  // turnBend:轉彎時身體往轉彎方向持續彎的偏移量(不是擺尾振盪,是單方向的弧度),
  // 沒有這個的話轉彎只靠魚的朝向A整隻硬轉,看起來像船在原地轉舵、不像魚用身體帶著轉
  float turnBend;
  // 每隻魚自己的速度上限跟打尾巴基礎節奏都不一樣——不然對齊力會讓大家的移動
  // 越靠越同步,看起來像列隊的機器魚而不是各自游動的一群魚
  float maxSpeed, beatRate;
  // noiseT:這隻魚自己的noise時間軸(每隻魚錯開起點,才不會全部同步漂移)。
  // 朝向/速度改成完全由noise驅動、緩慢隨機起伏,不再是算「目標方向」再精準
  // 追過去那種數學導向公式——參考水族館魚/夾娃娃機魚缸的游動感:悠悠地漂,
  // 偶爾轉個彎、偶爾停一下、偶爾游快一點,你永遠不知道牠下一秒要往哪去
  float noiseT;
  color c1, c2;
  // 移動殘影:記錄最近幾幀的姿態(位置/朝向/擺動狀態),不是另外算的假動畫特效,
  // 是真的重播魚最近幾幀本身的樣子疊在一起、越舊的殘影越淡,做出移動時的拖影感
  ArrayList<float[]> trail = new ArrayList<float[]>();

  Koi(float x, float y) {
    this.x = random(W);
    this.y = random(H);
    this.vx = 0;
    this.vy = -random(3, 4);
    this.s = random(0.8, 1.2);
    this.dx = 0;
    this.dy = 0;
    this.a = 0;
    this.A = random(TWO_PI);
    // 這個畫面沒有設colorMode(HSB,...),color()吃到的其實是RGB三個值——
    // 所以原本的c0(0~360)套進R那個位置,超過255的部分會直接被夾到255,
    // 等於「色相」這個概念在這裡並不成立,只是R通道在跑,G/B固定不變。
    // 大部分機率(75%)直接配一組偏紅橘的暖色系RGB(R高、B低,G從低到中決定是
    // 偏紅還是偏橘)。G上限縮小(220→150),避免G太接近R變成偏黃——使用者反饋
    // 不要太黃的魚。其餘機率維持原本的公式,保留一點顏色多樣性
    if (random(1) < 0.75) {
      float rr = random(200, 255);
      float gg = random(30, 150);
      float bb = random(15, 60);
      this.c1 = color(rr, gg, bb);
      this.c2 = color(min(rr + 20, 255), gg, min(bb + 30, 255));
    } else {
      this.c0 = random(360);
      this.c1 = color((int) c0, 80, 50);
      this.c2 = color((int) (c0 + 50) % 360, 80, 50);
    }
    this.wiggleOffset = random(1000);
    this.maxSpeed = random(2.8, 4.3);
    this.beatRate = random(0.07, 0.12);
    this.noiseT = random(1000);
    this.bendFactor = 1.0;
    this.turnBend = 0;
  }

  // 身體外框(鼻頭在+x方向,尾巴在-x方向):直接從使用者提供的參考剪影 SVG
  // 向量路徑反推出來的三次貝茲控制點(matrix變換+座標系旋轉成「鼻頭朝+x」後的
  // 局部座標),整條外框(胸鰭、腹鰭、尾叉全部一體成型)就是參考圖那條路徑本身,
  // 不是自己手畫的近似形狀。用真正的三次貝茲(bezierVertex,不是 curveVertex)
  // 逐段畫,每段控制點都是明確算好的,不會有 Catmull-Rom 在密集尖銳轉折處互相
  // 干擾爆開成鋸齒的風險。
  // anchor[i] = {x, y, 甩動權重}:32個外框頂點(鼻頭權重0,尾叉尖端權重~1)
  // 收窄身寬到0.85倍(使用者反饋0.72還要再胖一點點),x(體長)不動
  // 座標系原點改成鼻頭(鼻頭x=0,尾叉x=-100)——之前原點在身體中間,轉向時是整條魚
  // 繞著身體中心轉,看起來像船在原地轉舵。改成以鼻頭為圓心後,(x,y)代表的是鼻頭的
  // 位置,轉向時自然是「頭在前面帶,身體跟尾巴繞著頭轉」,符合使用者反饋「應該以頭
  // 為中心帶動整隻魚」
  float[][] anchor = {
    {-29.03, 10.22, 0.20},
    {-35.60, 9.96, 0.26},
    {-47.81, 8.60, 0.38},
    {-52.94, 7.86, 0.44},
    {-67.42, 11.30, 0.60},
    {-62.02, 5.92, 0.54},
    {-78.65, 5.21, 0.73},
    {-89.73, 11.17, 0.87},
    {-100.01, 11.40, 1.00},
    {-98.09, 7.98, 0.98},
    {-94.75, 2.58, 0.93},
    {-91.39, -0.11, 0.89},
    {-94.60, -2.29, 0.93},
    {-98.43, -8.32, 0.98},
    {-98.88, -12.12, 0.99},
    {-77.94, -4.77, 0.72},
    {-62.01, -5.92, 0.54},
    {-67.22, -11.52, 0.60},
    {-52.84, -7.70, 0.44},
    {-44.89, -8.97, 0.35},
    {-29.10, -10.23, 0.20},
    {-33.44, -19.57, 0.24},
    {-31.24, -23.54, 0.22},
    {-23.34, -14.69, 0.15},
    {-21.58, -10.23, 0.14},
    {-15.97, -8.99, 0.09},
    {0.01, -0.11, 0.00},
    {-16.57, 9.13, 0.10},
    {-21.13, 9.99, 0.13},
    {-23.26, 14.73, 0.15},
    {-30.74, 23.54, 0.22},
    {-33.54, 19.46, 0.24},
  };
  // ctrl[i] = {c1x,c1y,c1甩動權重, c2x,c2y,c2甩動權重}:第i段(anchor[i] -> anchor[(i+1)%n])的貝茲控制點
  float[][] ctrl = {
    {-30.75, 9.46, 0.22, -33.68, 10.03, 0.24},
    {-39.68, 9.81, 0.30, -43.78, 9.19, 0.34},
    {-49.34, 8.38, 0.40, -51.40, 7.44, 0.42},
    {-56.03, 8.72, 0.49, -64.42, 14.83, 0.55},
    {-66.93, 8.57, 0.58, -63.55, 7.61, 0.56},
    {-66.56, 3.77, 0.60, -74.04, 3.01, 0.67},
    {-82.47, 7.03, 0.78, -85.60, 9.82, 0.82},
    {-91.47, 11.73, 0.91, -99.30, 13.68, 0.96},
    {-100.35, 10.31, 0.99, -98.70, 8.81, 0.98},
    {-96.80, 6.26, 0.96, -96.24, 4.19, 0.95},
    {-93.84, 1.60, 0.92, -91.97, 0.99, 0.90},
    {-92.39, -0.92, 0.90, -93.68, -1.39, 0.92},
    {-96.34, -4.00, 0.95, -97.01, -6.41, 0.96},
    {-99.25, -9.43, 0.98, -101.19, -11.41, 0.98},
    {-91.38, -14.45, 0.90, -84.02, -7.23, 0.81},
    {-73.36, -2.91, 0.66, -66.43, -4.05, 0.60},
    {-63.51, -7.35, 0.56, -67.86, -8.84, 0.58},
    {-61.81, -13.81, 0.54, -57.49, -8.83, 0.49},
    {-51.32, -7.33, 0.41, -46.62, -8.65, 0.38},
    {-40.79, -9.72, 0.30, -32.18, -9.22, 0.25},
    {-33.37, -13.51, 0.21, -35.41, -13.45, 0.23},
    {-33.13, -20.51, 0.23, -32.93, -23.83, 0.23},
    {-27.28, -22.86, 0.20, -24.55, -17.68, 0.17},
    {-22.79, -13.34, 0.15, -22.77, -11.29, 0.14},
    {-20.31, -9.09, 0.12, -17.62, -9.27, 0.11},
    {-11.31, -8.24, 0.06, -0.21, -5.41, 0.03},
    {0.25, 5.69, 0.03, -11.81, 8.24, 0.06},
    {-18.04, 9.41, 0.11, -19.78, 9.32, 0.12},
    {-22.68, 10.74, 0.14, -22.79, 13.38, 0.14},
    {-24.26, 17.63, 0.17, -27.09, 22.71, 0.19},
    {-32.99, 24.03, 0.22, -33.16, 20.81, 0.23},
    {-35.13, 13.73, 0.23, -33.05, 13.46, 0.21},
  };

  void draw() {
    noStroke();
    update();
    // 擺動節奏不能只綁移動速度——真的魚是「用擺尾製造推力」,静止或漂浮時尾巴也一直在
    // 打,不是等速度夠快才動,不然停下來或慢慢靠近時擺動幾乎歸零,看起來很僵硬。改成
    // 固定的持續打尾巴節奏為主,速度只小幅加成(游快時打得快一點)
    a += beatRate + dist(0, 0, vx, vy) / 160;

    // 把這一幀的完整姿態存進殘影歷史,超過長度上限就丟掉最舊的一筆
    trail.add(new float[]{x, y, A, bendFactor, turnBend, a});
    int maxTrail = 6;
    if (trail.size() > maxTrail) trail.remove(0);

    // 由舊到新依序畫出殘影(alpha從很淡漸漸變濃),最後一筆是「現在」的姿態,
    // 用完全不透明畫在最上層——不是另外算的殘影特效貼圖,是真的把最近幾幀魚
    // 本身的樣子重播疊在一起,移動越快、殘影拖得越開,天然就有動態拖影感
    float savedX = x, savedY = y, savedA = A;
    float savedBend = bendFactor, savedTurn = turnBend, savedPhase = a;
    int last = trail.size() - 1;
    for (int i = 0; i <= last; i++) {
      float[] snap = trail.get(i);
      x = snap[0];
      y = snap[1];
      A = snap[2];
      bendFactor = snap[3];
      turnBend = snap[4];
      a = snap[5];
      int alpha = (i == last) ? 255 : (int) map(i, 0, max(last, 1), 30, 150);
      renderBody(alpha);
    }
    x = savedX;
    y = savedY;
    A = savedA;
    bendFactor = savedBend;
    turnBend = savedTurn;
    a = savedPhase;
  }

  // 畫出魚身輪廓本身(不含移動殘影邏輯),依目前的x,y,A,bendFactor,turnBend,a
  // 算出擺尾/轉彎動畫後的形狀,用alpha控制不透明度——同一份繪圖邏輯拿來畫「現在」
  // 跟畫「殘影」共用,只是呼叫時暫時把姿態換成歷史上的某一幀
  void renderBody(int alpha) {
    // 甩動改成「沿身體傳遞的波」,不是整段身體同相位一起硬邦邦傾斜:每個點依自己
    // 在身體上的x位置多算一段相位差(越靠尾巴,相位落後越多),尾巴才會像真的魚一樣
    // 慢半拍才跟上頭部的擺動方向,搭配權重(尾巴權重~1、鼻頭權重~0)做出頭部幾乎不動、
    // 波浪往尾巴傳遞時越晃越大的效果,轉彎越急bendFactor越大,擺動也跟著更明顯
    float amp = 14;
    float waveFreq = 0.026;
    float tailFreqMul = 1.8;
    float tailWhipGain = 8;

    int n = anchor.length;
    float[] wx = new float[n];
    float[] wy = new float[n];
    for (int i = 0; i < n; i++) {
      // 擺尾振盪(waveAn)疊加轉彎方向的持續弧度(turnBend)——兩者都用同一個
      // 甩動權重放大,轉彎時身體是「順著弧出去」,不是整隻繞著中心硬轉
      float wgt = anchor[i][2];
      float phase = a - (-anchor[i][0]) * waveFreq;
      float waveAn = sin(phase) * bendFactor;
      float tailWhip = sin(phase * tailFreqMul) * wgt * wgt * wgt;
      float ly = anchor[i][1] + (waveAn + turnBend) * wgt * amp + tailWhip * tailWhipGain;
      wx[i] = w(anchor[i][0], ly, true);
      wy[i] = w(anchor[i][0], ly, false);
    }

    fill(c1, alpha);
    beginShape();
    vertex(wx[0], wy[0]);
    for (int i = 0; i < n; i++) {
      int j = (i + 1) % n;
      float wgt1 = ctrl[i][2];
      float phase1 = a - (-ctrl[i][0]) * waveFreq;
      float c1An = sin(phase1) * bendFactor + turnBend;
      float c1Whip = sin(phase1 * tailFreqMul) * wgt1 * wgt1 * wgt1;
      float c1ly = ctrl[i][1] + c1An * wgt1 * amp + c1Whip * tailWhipGain;

      float wgt2 = ctrl[i][5];
      float phase2 = a - (-ctrl[i][3]) * waveFreq;
      float c2An = sin(phase2) * bendFactor + turnBend;
      float c2Whip = sin(phase2 * tailFreqMul) * wgt2 * wgt2 * wgt2;
      float c2ly = ctrl[i][4] + c2An * wgt2 * amp + c2Whip * tailWhipGain;
      bezierVertex(
        w(ctrl[i][0], c1ly, true), w(ctrl[i][0], c1ly, false),
        w(ctrl[i][3], c2ly, true), w(ctrl[i][3], c2ly, false),
        wx[j], wy[j]
      );
    }
    endShape(CLOSE);
  }

  // 局部座標的bezierVertex:內部負責轉成世界座標,呼叫端不用自己算旋轉/縮放
  void bez(float c1x, float c1y, float c2x, float c2y, float ax, float ay) {
    bezierVertex(
      w(c1x, c1y, true), w(c1x, c1y, false),
      w(c2x, c2y, true), w(c2x, c2y, false),
      w(ax, ay, true), w(ax, ay, false)
    );
  }

  // 把局部座標(lx,ly)依魚的朝向A、縮放s轉成世界座標;wantX=true回傳x,否則回傳y
  float w(float lx, float ly, boolean wantX) {
    if (wantX) return x + (lx * cos(A) - ly * sin(A)) * s;
    return y + (lx * sin(A) + ly * cos(A)) * s;
  }

  // update() 用noise讓朝向/速度緩慢隨機起伏,參考真實水族館魚/夾娃娃機魚缸裡魚的
  // 游法:大部分時間只是自己悠悠地漂、偶爾轉個彎、偶爾停一下,沒有明確目標、下一秒
  // 要往哪游是不可預測的。手勢重新分工後,魚只在「食指指」的時候才會被吸引,其他
  // 手勢(拳頭/搖手/比讚/手掌展開)完全不影響魚的行為,只影響水波/荷葉
  void update() {
    float oldA = A;

    // 朝向持續被noise緩慢帶著漂移——這是這個做法的核心,取代掉之前所有「算合力
    // 方向、平滑轉過去」的向量運算。noise本身就是連續、平滑、但不可預測的,天生
    // 就長得像悠遊亂晃的感覺,不需要額外再刻意做平滑處理
    noiseT += 0.006;
    A += (noise(noiseT) - 0.5) * 0.09;

    // 只有比出「食指指」的時候,魚才會被吸引往指尖方向去;其他手勢/沒偵測到手時
    // 完全不受手的影響,單純靠自己的noise漂——手勢參數重新分工後,拳頭/搖手/比讚/
    // 手掌展開都只用來操控水波或荷葉,不再牽動魚的行為。
    // 追蹤要「明顯」:離指尖還遠時直接衝過去,靠近之後改成繞著指尖切線方向游,
    // 變成繞圈而不是衝過頭又轉回來回擺盪
    boolean chasing = haveHand && currentGesture.equals("point");
    float distToTip = chasing ? dist(x, y, tipX, tipY) : 0;
    float orbitRadius = 70;
    if (chasing) {
      float toTipAngle = atan2(tipY - y, tipX - x);
      float targetAngle = (distToTip > orbitRadius) ? toTipAngle : (toTipAngle + HALF_PI);
      float tipDiff = atan2(sin(targetAngle - A), cos(targetAngle - A));
      A += tipDiff * 0.2;
    }

    // 靠近畫面邊緣時柔和地把朝向拉回中央,不要真的游出畫面外
    float margin = 90;
    if (x < margin || x > W - margin || y < margin || y > H - margin) {
      float centerAngle = atan2(H / 2 - y, W / 2 - x);
      float centerDiff = atan2(sin(centerAngle - A), cos(centerAngle - A));
      A += centerDiff * 0.05;
    }

    // 把這一幀「總共」轉了多少角度限制在一個上限——平常悠遊漂移時限制得很嚴格
    // (0.005),保證是慢慢的C形弧線;但食指指主動追蹤時放寬很多(0.035),不然
    // 追蹤看起來會不明顯、慢半拍
    float rawDiff = atan2(sin(A - oldA), cos(A - oldA));
    float maxTurnPerFrame = chasing ? 0.035 : 0.005;
    A = oldA + constrain(rawDiff, -maxTurnPerFrame, maxTurnPerFrame);

    // 前進速度平常單純用noise緩慢起伏(風平浪靜時慢悠悠地游),不跟其他手勢掛勾;
    // 但食指指主動追蹤時明顯加速衝過去,抵達指尖附近後改用溫和一點的繞圈速度
    float speed;
    if (chasing) {
      speed = (distToTip > orbitRadius) ? 4.2 : 2.0;
    } else {
      speed = map(noise(noiseT + 777), 0, 1, 0.3, 1.8);
    }
    vx = cos(A) * speed;
    vy = sin(A) * speed;
    x += vx;
    y += vy;

    // 轉彎時的身體彎折要跟轉向幅度直接掛勾,才不會出現「轉很大但尾鰭幾乎沒晃」
    // 的不自然感——參考魚類的C-start轉彎:急轉時全身(不只是尾巴)會一起彎成一個
    // C字形,轉得越急、彎得越深,身體反應要跟得上實際轉向量,不能只是象徵性地擺一下
    float turnRate = atan2(sin(A - oldA), cos(A - oldA));
    float targetBend = 1.0 + constrain(abs(turnRate) * 11, 0, 1.6);
    bendFactor += (targetBend - bendFactor) * 0.45;
    // 轉彎方向的持續彎曲(不是振盪,是有方向性的偏移):轉彎時身體整段順著轉彎方向
    // 弧出去,不是靠朝向角度A整隻硬轉——這樣看起來才像魚用身體「帶著」轉彎,不是
    // 原地轉舵。轉彎結束後(turnRate趨近0)會自己鬆開回直。幅度跟反應速度都加大,
    // 讓身體彎折的量真的對應得上實際轉了多少
    float targetTurnBend = constrain(turnRate * 9, -1.3, 1.3);
    turnBend += (targetTurnBend - turnBend) * 0.4;
  }

  void rules() {
    // 分離距離從100加大到160——魚群沒有手勢輸入時全部被吸引到同一個預設點附近,
    // 距離太小會擠成一團,疊在一起的殘影(水色濾鏡的持續效果)看起來像一團亂毛,
    // 加大分離距離讓魚群保持疏開,不會擠成一堆
    float sepDist = 160;
    ArrayList<Koi> closeedKoi = new ArrayList<Koi>();
    for (Koi other : koi) {
      if (other != this && dist(other.x, other.y, x, y) < sepDist) closeedKoi.add(other);
    }
    if (closeedKoi.size() == 0) return;
    float dx = 0;
    float dy = 0;
    float alignX = 0;
    float alignY = 0;
    for (Koi other : closeedKoi) {
      float d = dist(other.x, other.y, x, y);
      dx -= (1 - d / sepDist) * (other.x - x);
      dy -= (1 - d / sepDist) * (other.y - y);
      alignX += other.vx;
      alignY += other.vy;
    }
    alignX /= closeedKoi.size();
    alignY /= closeedKoi.size();
    // 對齊力調得很輕(6→1):太強的話大家速度會快速趨於一致,看起來像同步列隊的
    // 機器魚而不是各自游動的一群魚,只要一點點意思、不要完全不管同伴方向就好
    this.dx += dx + (alignX - vx) * 1;
    this.dy += dy + (alignY - vy) * 1;
  }
}

// 荷葉
class LotusLeaf {
  float x, y, r;
  int count;
  float[] listX, listY;
  float lineLength;
  int leafColor, vineColor;
  float offsetX, offsetY;
  float vx, vy;
  // travelBudget:只有從邊緣飄進來的荷葉會設這個值(正常擺放/被推走的荷葉維持
  // -1,物理跟原版一樣不帶摩擦力)。飄進來的荷葉走完這段預算距離就自然停下,
  // 不會一路滑出畫面另一側;不用對所有荷葉套用摩擦力,才不會反過來讓使用者
  // 「把荷葉推走」的力道被削弱、推不出畫面外
  float travelBudget = -1;
  // growScale:荷葉出現時由小長大的動畫進度(1.0=已經長到全開)。一開始就存在
  // 池塘裡的荷葉直接是全開的(1.0),只有之後才新生成的荷葉(補充/比讚生出來的)
  // 會從0開始長大,不會憑空「啪」一下直接以完整大小出現
  float growScale = 1.0;

  LotusLeaf() {
    this.x = random(W);
    this.y = random(H);
    this.r = random(20, 50);
    this.count = int(random(15, 24));

    this.listX = new float[count];
    this.listY = new float[count];
    this.lineLength = this.r + random(this.r / 5, this.r / 2);
    for (int i = 0; i < count; i++) {
      float angle = radians((360 / count) * i);
      float len = this.r + random(this.r / 5, this.r / 2);
      this.listX[i] = cos(angle) * len;
      this.listY[i] = sin(angle) * len;
    }

    this.leafColor = color(random(80, 120), random(120, 200), random(80, 120));
    this.vineColor = color(random(50, 70), random(80, 110), random(50, 70));

    this.offsetX = random(1000);
    this.offsetY = random(1000);

    this.vx = 0;
    this.vy = 0;
  }

  void draw() {
    pushMatrix();
    translate(x + sin(offsetX) * 10, y + sin(offsetY) * 10);
    scale(growScale);

    fill(leafColor);
    stroke(leafColor);
    beginShape();
    for (int i = 0; i < count; i++) {
      curveVertex(listX[i], listY[i]);
    }
    endShape(CLOSE);

    stroke(vineColor);
    strokeWeight(1.5);
    for (int i = 0; i < count; i++) {
      line(0, 0, listX[i], listY[i]);
    }

    popMatrix();
    update();
    checkCollision();
  }

  void checkCollision() {
    for (LotusLeaf other : lotusLeaf) {
      if (other != this) {
        float distance = dist(x, y, other.x, other.y);
        if (distance < r + other.r) {
          float angle = atan2(y - other.y, x - other.x);
          float force = map(distance, 0, r + other.r, 1, 0);
          applyForce(force, angle);
          other.applyForce(force, angle + PI);
        }
      }
    }
  }

  void update() {
    offsetX += 0.01;
    offsetY += 0.02;
    x += vx;
    y += vy;
    // 只有從邊緣飄進來的荷葉(travelBudget>0)會扣預算、走完就停下來安頓好;
    // 一般荷葉(travelBudget維持-1)跟原版一樣沒有摩擦力,才能被使用者一路推出畫面外
    if (travelBudget > 0) {
      travelBudget -= mag(vx, vy);
      if (travelBudget <= 0) {
        vx = 0;
        vy = 0;
        travelBudget = -1;
      }
    }
    // 新生成的荷葉由小長大(growScale從0慢慢長到1),不是憑空以完整大小出現
    if (growScale < 1.0) {
      growScale = min(1.0, growScale + 0.035);
    }
  }

  void applyForce(float force, float angle) {
    float forceX = force * 0.2 * cos(angle);
    float forceY = force * 0.2 * sin(angle);
    this.vx += forceX;
    this.vy += forceY;
  }
}
