/*
【迭代紀錄 v4】身體外框(curveVertex)+ 獨立三角形鰭版本。
把鰭的尖銳凸起從身體外框路徑中抽出來,身體只留平滑漸縮曲線+尾叉(14點
curveVertex),鰭改成另外畫的簡單三角形,根部直接取身體輪廓上已算好的頂點,
解決了「鰭凸起塞進同一條路徑,尖銳轉折太多導致 Catmull-Rom 爆開成鋸齒」的問題。

後來比對使用者提供的參考剪影(黑色魚形圖示,大片胸鰭+較小腹鰭+燕尾式尾叉,
線條比這版更流線寫實),決定改用「直接從參考 SVG 的向量路徑逆向算出貝茲控制點,
整條外框(含鰭、尾叉)當成一條完整的三次貝茲曲線」的做法,精確度更高、也不會有
Catmull-Rom 的鋸齒風險。這一版(三角形鰭)留著當作中間過程的完整記錄。

手勢控制的錦鯉池生成藝術。
以「Processing 創意編碼」課堂期末小組作業(Final Group Project:水波方程 + boid式
錦鯉群 + 荷葉碰撞)原始程式碼為準,配色、荷葉畫法、魚的畫法、水色全部照原版不修改,
只做最必要的手勢佈線:接收 Python 端(osc_bridge.py)辨識出的手掌位置,取代滑鼠
成為魚群游動/水波/荷葉推擠的互動目標。

需要先安裝 oscP5 library(Processing IDE: Sketch > Import Library > Add Library... 搜尋 oscP5)。
沒有連接 webcam/OSC 時,滑鼠拖曳/點擊仍可手動觸發水波、推開荷葉,方便單機測試。
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
float openness = 0.4;
float confidence = 0.8;
float handX, handY;
boolean haveHand = false;
int handRippleCooldown = 0;
int ambientRippleCooldown = 0;
int mouseRippleCooldown = 0;

void setup() {
  size(800, 600);
  W = width;
  H = height;
  current = new float[W][H];
  previous = new float[W][H];
  for (int i = 0; i < 30; i++) {
    koi.add(new Koi(200, 100 + i * 100));
  }
  for (int i = 0; i < 10; i++) {
    lotusLeaf.add(new LotusLeaf());
  }

  handX = width / 2;
  handY = height / 2;
  oscP5 = new OscP5(this, 8000);
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
  }
}

// 推開附近的荷葉(跟原版 mouseDragged 的邏輯完全相同,只是位置來源換成手掌)。
// 這個每一幀都可以持續呼叫,互動才即時不會延遲。
void pushNearbyLeaves(float x, float y) {
  for (LotusLeaf leaf : lotusLeaf) {
    float distance = dist(x, y, leaf.x, leaf.y);
    if (distance < 100) {
      float angle = atan2(y - leaf.y, x - leaf.x);
      float force = map(distance, 0, 50, 1, 0);
      leaf.applyForce(force, angle);
    }
  }
}

// 在(x,y)附近一小片圓形範圍產生水波(不是單一像素)。
// 原本每一幀都寫入單一像素,等於連續不斷造波,波紋疊在一起變成密集的紋路,
// 很像遊艇劃過水面的尾流;改成一小片範圍展開,波紋間距才會自然,比較像
// 石頭丟進水裡、一圈一圈散開的感覺。
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
}

// 沒有 webcam/OSC 時,滑鼠拖曳/點擊仍可手動觸發水波、推開荷葉,方便單機測試。
// mouseDragged每次滑鼠移動就觸發一次,如果每次都直接造波,拖曳幾下就會疊出密集尾流,
// 所以一樣要走冷卻時間,跟手勢追蹤共用同一套節奏
void mouseDragged() {
  handX = mouseX;
  handY = mouseY;
  haveHand = true;
  pushNearbyLeaves(mouseX, mouseY);
  mouseRippleCooldown--;
  if (mouseRippleCooldown <= 0) {
    spawnRipple(mouseX, mouseY);
    mouseRippleCooldown = 10;
  }
}
void mouseClicked() {
  mouseDragged();
}

void draw() {
  // 手掌被持續追蹤時,荷葉推擠每一幀都算(互動要即時);但水波不是每一幀都造一個新的
  // ——加個冷卻時間,波紋才有空間展開、彼此拉開距離,不會疊成連續尾流
  if (haveHand) {
    pushNearbyLeaves(handX, handY);
    handRippleCooldown--;
    if (handRippleCooldown <= 0) {
      spawnRipple(handX, handY);
      // openness(手張開程度)連續控制冷卻時間:手張得越開,波紋造得越頻繁;
      // confidence越低,反應刻意遲鈍一點,不去武斷套用可能誤判的訊號
      float freq = map(openness, 0, 1, 30, 12) * map(confidence, 0, 1, 1.6, 1.0);
      handRippleCooldown = int(freq);
    }
  }

  // 環境自然波紋也一樣加冷卻時間,不要太密集
  ambientRippleCooldown--;
  if (ambientRippleCooldown <= 0) {
    previous[int(random(width - 2))][int(random(height - 2))] = 160;
    ambientRippleCooldown = int(random(50, 110));
  }
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

  for (LotusLeaf v : lotusLeaf) {
    v.draw();
  }

  // 手掌位置十字準星,方便核對手掌跟魚群的空間關係(唯一保留的非原版元素,先前你要求過)
  if (haveHand) {
    noFill();
    stroke(255, 215, 90, 200);
    strokeWeight(2);
    ellipse(handX, handY, 26, 26);
    line(handX - 16, handY, handX + 16, handY);
    line(handX, handY - 16, handX, handY + 16);
  }
}

class Koi {
  float x, y, vx, vy, s, dx, dy, a, A, c0;
  float wiggleOffset, bendFactor;
  color c1, c2;

  Koi(float x, float y) {
    this.x = random(W);
    this.y = random(H);
    this.vx = 0;
    this.vy = -random(3, 4);
    this.s = random(0.8, 1.2);
    this.dx = 0;
    this.dy = 0;
    this.a = 0;
    this.A = 0;
    this.c0 = random(360);
    this.c1 = color((int) c0, 80, 50);
    this.c2 = color((int) (c0 + 50) % 360, 80, 50);
    this.wiggleOffset = random(1000);
    this.bendFactor = 1.0;
  }

  // 身體外框(鼻頭在+x方向,尾巴在-x方向):{x, y, 甩動權重},只有身體本身平滑的
  // 漸縮曲線+尾叉,不把鰭的尖銳凸起塞進這條路徑——尖銳轉折點一多,curveVertex
  // 會在轉折處互相干擾爆開成鋸齒(這是這次踩到的教訓)。鰭改成另外畫的簡單三角形。
  float[][] silhouette = {
    {40, 0, 0.00},     // 鼻頭尖端
    {30, 10, 0.08},    // 肩部(胸鰭長在這個點上)
    {6, 9, 0.20},      // 頸部
    {-20, 12, 0.40},   // 身體中段(第二片鰭長在這個點上)
    {-42, 8, 0.58},    // 身體漸窄
    {-58, 22, 0.80},   // 尾鰭尖端(+)
    {-48, 3, 0.70},    // 靠近缺口
    {-44, 0, 0.65},    // 尾叉缺口中心
    {-48, -3, 0.70},   // 靠近缺口(鏡射)
    {-58, -22, 0.80},  // 尾鰭尖端(-)
    {-42, -8, 0.58},
    {-20, -12, 0.40},  // 身體中段(鏡射)
    {6, -9, 0.20},
    {30, -10, 0.08},   // 肩部(鏡射)
  };

  void draw() {
    noStroke();
    update();
    a += dist(0, 0, vx, vy) / 100;
    // 轉彎越急,身體彎折幅度越大(像真的魚甩尾轉向);直線游動時幅度回到正常
    float An = sin(a) * bendFactor;

    int n = silhouette.length;
    float[] wx = new float[n];
    float[] wy = new float[n];
    for (int i = 0; i < n; i++) {
      float ly = silhouette[i][1] + An * silhouette[i][2] * 12;
      wx[i] = w(silhouette[i][0], ly, true);
      wy[i] = w(silhouette[i][0], ly, false);
    }

    fill(c1);
    beginShape();
    curveVertex(wx[n - 1], wy[n - 1]);
    for (int i = 0; i < n; i++) curveVertex(wx[i], wy[i]);
    curveVertex(wx[0], wy[0]);
    curveVertex(wx[1], wy[1]);
    endShape(CLOSE);

    // 胸鰭:簡單三角形,支點直接取身體輪廓上「已經算好的」頂點(index 1、3,
    // 分別是肩部/身體中段),鰭根保證精確長在身體表面上,不會脫節
    fill(c2);
    drawFin(wx[1], wy[1], wx[2], wy[2], 30, -1);
    drawFin(wx[n - 2], wy[n - 2], wx[n - 1], wy[n - 1], 30, 1);
    drawFin(wx[3], wy[3], wx[4], wy[4], 20, -1);
    drawFin(wx[n - 4], wy[n - 4], wx[n - 3], wy[n - 3], 20, 1);
  }

  // 簡單三角形鰭:從身體輪廓上兩個相鄰頂點(p1,p2,已經是世界座標)之間長出去,
  // 尖端往side方向撐開len距離
  void drawFin(float p1x, float p1y, float p2x, float p2y, float len, float side) {
    float midX = (p1x + p2x) / 2;
    float midY = (p1y + p2y) / 2;
    float dirX = p2x - p1x;
    float dirY = p2y - p1y;
    float mag = max(mag(dirX, dirY), 0.0001);
    float perpX = -dirY / mag * side;
    float perpY = dirX / mag * side;
    triangle(p1x, p1y, p2x, p2y, midX + perpX * len, midY + perpY * len);
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

  void update() {
    rules();
    float handXDir = handX - x;
    float handYDir = handY - y;
    float handDirMagnitude = max(dist(x, y, handX, handY), 0.0001);
    handXDir /= handDirMagnitude;
    handYDir /= handDirMagnitude;
    // openness連續調整魚對手掌的反應方向與力道:手收攏(openness低)時被吸引靠近(像好奇),
    // 手張開(openness高)時被推開驚散;confidence越低,反應越弱越遲鈍,不做離散手勢分支
    float attract = map(openness, 0, 1, 0.42, -0.15);
    attract *= map(confidence, 0, 1, 0.35, 1.0);
    vx += handXDir * attract;
    vy += handYDir * attract;

    // 垂直於前進方向的正弦擺動,讓魚不是直線衝向目標,而是自然地左右擺尾游過去
    float perpX = -handYDir;
    float perpY = handXDir;
    float wiggle = sin(frameCount * 0.06 + wiggleOffset) * 0.22;
    vx += perpX * wiggle;
    vy += perpY * wiggle;

    x += vx;
    y += vy;

    // 朝向角度平滑轉過去(不是每幀直接snap到新方向)——魚群裡的分離力常常讓速度方向
    // 一瞬間跳來跳去,如果每幀都直接對齊,轉彎會很生硬像機器人;平滑地追過去才自然
    float oldA = A;
    float targetA = atan2(vy, vx);
    float angleDiff = atan2(sin(targetA - A), cos(targetA - A));
    A += angleDiff * 0.18;
    float turnRate = atan2(sin(A - oldA), cos(A - oldA));
    float targetBend = 1.0 + constrain(abs(turnRate) * 6, 0, 0.8);
    bendFactor += (targetBend - bendFactor) * 0.3;

    dx = 0;
    dy = 0;
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
    for (Koi other : closeedKoi) {
      float d = dist(other.x, other.y, x, y);
      dx -= (1 - d / sepDist) * (other.x - x);
      dy -= (1 - d / sepDist) * (other.y - y);
    }
    this.dx += dx;
    this.dy += dy;

    vx *= 0.9995;
    vy *= 0.9995;
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
  }

  void applyForce(float force, float angle) {
    float forceX = force * 0.2 * cos(angle);
    float forceY = force * 0.2 * sin(angle);
    this.vx += forceX;
    this.vy += forceY;
  }
}
