/*
【迭代紀錄 v2】寶石色調水面嘗試版。
拿掉了v1的暗角效果,水面改成參考七彩倒影畫作設計的寶石色調色盤(深靛藍/青藍/墨綠青/
紫丁香/珊瑚粉/暖金),用大尺度緩慢noise場決定每個區域的顏色,魚的配色也加入呼應水色的
青藍/紫丁香變體,並加了模擬水面倒映樹影的深色垂直波狀紋路,魚的游動加入垂直於前進方向
的正弦擺動讓路徑不是死板直線。

這一版最後被水墨風(見 processing_sketch/gesture_koi)取代,原因記錄下來當作反面教材:
- 水面色塊之間用兩個顏色互相lerpColor內插,在RGB色彩空間裡插值會經過一段濁灰色,
  這是畫面「髒掉」的根本原因,不是配色選得不好,是內插方式本身有問題
- 魚移動時,水色濾鏡抓取畫面上已經畫出來的顏色(get(x,y))去跟調色盤混合,
  魚跟倒影紋路也被一起重複混色,舊位置的顏色沒有機制快速淡出,產生殘影/卡幀感
- 倒影紋路用一格一格貼矩形模擬波浪,格線之間看得出明顯斷層,不夠平滑
這幾點debug經驗在轉往水墨風版本時,直接影響了新版的技術決策(改用主動fade背景、
改用單一調色盤顏色低比例疊加、改用密集重疊圓點取代貼矩形)。
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
float openness = 0;
float confidence = 0;
float handX, handY;
boolean haveHand = false;
boolean nightMode = false;

// 寶石色調色盤(深靛藍/青藍打底,浮著暖金、珊瑚粉、紫丁香斑塊),取代原本單一青碧色的水色設計
color[] pondPalette;

void setup() {
  size(800, 600);
  W = width;
  H = height;
  current = new float[W][H];
  previous = new float[W][H];

  // 錦鯉/荷葉/水色調色盤用 HSB 設計(比較容易調出彼此協調的寶石色系),
  // 水面像素運算用 RGB(方便跟 red()/green()/blue() 對應),兩段用完各自切回來
  colorMode(HSB, 360, 100, 100);
  pondPalette = new color[]{
    color(215, 65, 45),  // 深靛藍
    color(195, 55, 60),  // 青藍
    color(170, 45, 55),  // 墨綠青
    color(280, 35, 55),  // 紫丁香
    color(330, 45, 70),  // 珊瑚粉
    color(40, 60, 80),   // 暖金
  };
  for (int i = 0; i < 30; i++) {
    koi.add(new Koi(200, 100 + i * 100));
  }
  for (int i = 0; i < 10; i++) {
    lotusLeaf.add(new LotusLeaf());
  }
  colorMode(RGB, 255);

  handX = width / 2;
  handY = height / 2;
  oscP5 = new OscP5(this, 8000);
}

// 深色垂直波狀紋路,像水面倒映的樹影,增加畫面的層次感
void drawReflectionStreaks() {
  noStroke();
  fill(8, 16, 26, 45);
  int streaks = 6;
  for (int i = 0; i < streaks; i++) {
    float baseX = (width / float(streaks)) * i + width / (streaks * 2.0);
    for (float y = 0; y < height; y += 5) {
      float wob = (noise(i * 10, y * 0.008, frameCount * 0.0015) - 0.5) * 60;
      float wthick = 5 + noise(i * 20, y * 0.015) * 9;
      ellipse(baseX + wob, y, wthick, wthick * 1.3);
    }
  }
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
    if (currentGesture.equals("thumbs_up") && confidence > 0.6) {
      nightMode = !nightMode;
    }
  }
}

// 沒有 webcam/OSC 時,滑鼠拖曳/點擊仍可手動觸發水波、推開荷葉,方便單機測試
void mouseDragged() {
  applyHandInfluence(mouseX, mouseY, 1.0);
}
void mouseClicked() {
  mouseDragged();
}

// 在 (x, y) 產生水波、推開附近荷葉;strength 讓手勢/信心值調整影響力道
void applyHandInfluence(float x, float y, float strength) {
  int pad = 2;
  int ix = int(x);
  int iy = int(y);
  if (pad <= ix && ix < width - pad && pad <= iy && iy < height - pad) {
    previous[ix][iy] = 255 * strength;
    float radius = currentGesture.equals("peace") ? 180 : 100;
    for (LotusLeaf leaf : lotusLeaf) {
      float distance = dist(x, y, leaf.x, leaf.y);
      if (distance < radius) {
        float angle = atan2(y - leaf.y, x - leaf.x);
        float force = map(distance, 0, radius / 2, 1, 0) * strength;
        leaf.applyForce(force, angle);
      }
    }
  }
}

void draw() {
  // 手掌被持續追蹤時,手掌位置本身就會不斷產生水波,取代原本需要滑鼠拖曳才有效果
  if (haveHand) {
    float reactStrength = (0.5 + openness * 0.5) * map(confidence, 0, 1, 0.3, 1.0);
    applyHandInfluence(handX, handY, reactStrength);
  }

  // 環境漣漪機率:張手時擾動變多(像風吹水面),握拳時平靜
  float rippleChance = map(openness, 0, 1, 0.05, 0.5);
  if (currentGesture.equals("open_palm")) rippleChance *= 1.5;
  if (currentGesture.equals("fist")) rippleChance *= 0.2;
  if (random(1) < rippleChance) {
    previous[int(random(width - 2))][int(random(height - 2))] = 255;
  }

  drawReflectionStreaks();

  for (Koi v : koi) {
    v.draw();
  }

  loadPixels();
  boolean warm = currentGesture.equals("fist");
  for (int x = 1; x < width - 1; x++) {
    for (int y = 1; y < height - 1; y++) {
      color originalColor = get(x, y);

      // 大尺度、緩慢變化的noise場決定這一點落在調色盤的哪個區段,
      // 產生像參考圖那樣一塊一塊、隨時間緩緩流動的寶石色斑塊,而不是單一色調的水
      float paletteNoise = noise(x * 0.006, y * 0.006, frameCount * 0.0025);
      float scaled = paletteNoise * pondPalette.length;
      int idxA = int(scaled) % pondPalette.length;
      int idxB = (idxA + 1) % pondPalette.length;
      color tinted = lerpColor(pondPalette[idxA], pondPalette[idxB], scaled - int(scaled));

      // 跟前一幀畫面緩緩混合,讓色塊之間的過渡更柔和、更有暈染感
      color mixed = lerpColor(originalColor, tinted, 0.05);

      float r = red(mixed);
      float g = green(mixed);
      float b = blue(mixed);

      // warm/night 兩種手勢模式在寶石色調色盤上疊自己的色溫濾鏡
      if (warm) {
        r = r * 1.15 + 25; g *= 0.9; b *= 0.55;
      }
      if (nightMode) {
        r *= 0.55; g *= 0.7; b = b * 0.85 + 35;
      }
      r = constrain(r, 0, 255);
      g = constrain(g, 0, 255);
      b = constrain(b, 0, 255);

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

  // 十字準星:標出目前追蹤到的手掌位置,方便對照手掌跟魚群的空間關係
  if (haveHand) {
    noFill();
    stroke(255, 215, 90, 200);
    strokeWeight(2);
    float pulse = 26 + sin(frameCount * 0.15) * 4;
    ellipse(handX, handY, pulse, pulse);
    line(handX - 16, handY, handX + 16, handY);
    line(handX, handY - 16, handX, handY + 16);
  }

  drawStatusPanel();
}

// 即時狀態面板:直接列出手勢/openness/confidence 數值跟目前生效的效果文字,
// 用來核對「手勢辨識結果」跟「魚群反應」是否對得上,不用只靠肉眼猜
void drawStatusPanel() {
  noStroke();
  fill(0, 0, 0, 135);
  rect(10, 10, 250, 122, 10);

  fill(255);
  textSize(15);
  text("手勢 gesture: " + currentGesture, 22, 32);

  fill(230);
  textSize(12);
  text("openness", 22, 54);
  noFill();
  stroke(255, 120);
  rect(95, 46, 130, 10, 4);
  noStroke();
  fill(120, 200, 255);
  rect(95, 46, 130 * constrain(openness, 0, 1), 10, 4);

  fill(230);
  text("confidence", 22, 74);
  noFill();
  stroke(255, 120);
  rect(95, 66, 130, 10, 4);
  noStroke();
  fill(confidence > 0.6 ? color(120, 255, 150) : color(255, 180, 80));
  rect(95, 66, 130 * constrain(confidence, 0, 1), 10, 4);

  fill(255, 235, 150);
  textSize(13);
  text(activeEffectLabel(), 22, 98);

  fill(200);
  textSize(11);
  String handInfo = haveHand
    ? "hand: (" + int(handX) + "," + int(handY) + ")"
    : "尚未追蹤到手,可用滑鼠拖曳測試";
  text(handInfo, 22, 118);
}

String activeEffectLabel() {
  if (currentGesture.equals("point")) return "-> 強力吸引魚群聚集(像餵食)";
  if (currentGesture.equals("fist")) return "-> 魚群平靜,反應變弱、配色轉暖";
  if (currentGesture.equals("open_palm")) return "-> 漣漪增強,水色偏冷";
  if (currentGesture.equals("peace")) return "-> 魚群散開游動,荷葉被推得更遠";
  if (nightMode) return "-> 月夜模式 ON";
  return "-> 尋常游動(無特殊效果)";
}

class Koi {
  float x, y, vx, vy, s, dx, dy, a, A;
  float wiggleOffset;
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
    this.wiggleOffset = random(1000);
    assignColors();
  }

  // 隨機挑一個配色:多數是接近真實錦鯉品種(紅白緋鯉/黃金鯉/白鯉/墨鯉/丹頂桃紅),
  // 另外加兩種青藍/紫丁香的變體呼應水色的寶石色調色盤,讓魚群跟水面色調融成一體
  void assignColors() {
    float roll = random(1);
    float hue, sat, bri;
    if (roll < 0.10) {          // 白鯉(Shiro)
      hue = random(360); sat = random(0, 6); bri = random(90, 100);
    } else if (roll < 0.18) {   // 墨鯉(Sumi)
      hue = random(360); sat = random(0, 10); bri = random(8, 18);
    } else if (roll < 0.40) {   // 緋鯉/紅白(Kohaku)
      hue = random(2, 14); sat = random(75, 95); bri = random(85, 100);
    } else if (roll < 0.60) {   // 黃金鯉(Ogon)
      hue = random(40, 52); sat = random(55, 80); bri = random(85, 100);
    } else if (roll < 0.75) {   // 丹頂/桃紅(Tancho系)
      hue = random(335, 355); sat = random(55, 80); bri = random(80, 95);
    } else if (roll < 0.88) {   // 青藍(呼應水色)
      hue = random(185, 205); sat = random(50, 70); bri = random(70, 90);
    } else {                    // 紫丁香(呼應水色)
      hue = random(265, 285); sat = random(35, 55); bri = random(75, 92);
    }
    this.c1 = color(hue, sat, bri);
    this.c2 = color(hue, max(sat - 15, 0), max(bri - 18, 10));
  }

  void draw() {
    noStroke();
    update();
    a += mag(vx, vy) / 70;
    float An = sin(a);
    float[] k = {
      -50, 2 + An * 5,
      30, 30 + An * 5,
      30, -30 + An * 5,
      -50, -2 + An * 5,

      -55, -3 + An * 5 + dy,
      -65, -7 + An * 10 + dy,
      -80, -5 + An * 10 + dy,
      -85, 0 + An * 10 + dy,
      -65, 0 + An * 10 + dy,
      -70, 0 + An * 10 + dy,
      -80, 5 + An * 10 + dy,
      -65, 7 + An * 10 + dy,
      -50, 2 + An * 5,

      5, 0 + An * 5,
      5, -5 + An * 5,
      -35, -30 + An * 7,
      -20, -10 + An * 7,
      5, 5 + An * 5,
      -35, 30 + An * 7,
      -20, 10 + An * 7,

      -25, 0 + An * 5,
      -30, 0 + An * 5,
      -60, -20 + An * 5,
      -43, -2 + An * 5,
      -30, 0 + An * 5,
      -60, 20 + An * 5,
      -43, 2 + An * 5,
    };
    float[] p = new float[k.length];
    for (int i = 0; i < k.length; i += 2) {
      p[i] = (k[i] * cos(A) - k[i + 1] * sin(A)) * s;
      p[i + 1] = (k[i] * sin(A) + k[i + 1] * cos(A)) * s;
    }

    fill(c2);
    beginShape();
    vertex(x + p[0], y + p[1]);
    bezierVertex(x + p[2], y + p[3], x + p[4], y + p[5], x + p[6], y + p[7]);
    bezierVertex(x + p[8], y + p[9], x + p[10], y + p[11], x + p[12], y + p[13]);
    bezierVertex(x + p[14], y + p[15], x + p[16], y + p[17], x + p[18], y + p[19]);
    bezierVertex(x + p[20], y + p[21], x + p[22], y + p[23], x + p[24], y + p[25]);
    endShape();

    beginShape();
    vertex(x + p[26], y + p[27]);
    bezierVertex(x + p[28], y + p[29], x + p[30], y + p[31], x + p[32], y + p[33]);
    vertex(x + p[26], y + p[27]);
    bezierVertex(x + p[34], y + p[35], x + p[36], y + p[37], x + p[38], y + p[39]);

    vertex(x + p[40], y + p[41]);
    bezierVertex(x + p[42], y + p[43], x + p[44], y + p[45], x + p[46], y + p[47]);
    vertex(x + p[40], y + p[41]);
    bezierVertex(x + p[48], y + p[49], x + p[50], y + p[51], x + p[52], y + p[53]);
    endShape();
  }

  void update() {
    rules();

    float dirX = handX - x;
    float dirY = handY - y;
    float distToHand = max(dist(x, y, handX, handY), 0.0001);
    dirX /= distToHand;
    dirY /= distToHand;

    // 吸引力道:基本值隨張開度增加,point手勢(像餵食)大幅提高,fist(平靜)大幅降低,
    // 並用信心值衰減——辨識越不確定,魚群反應越弱/越遲鈍
    float attract = 0.15 + openness * 0.2;
    if (currentGesture.equals("point")) attract = 0.6;
    if (currentGesture.equals("fist")) attract *= 0.3;
    attract *= map(confidence, 0, 1, 0.4, 1.0);

    vx += dirX * attract;
    vy += dirY * attract;

    // 垂直於前進方向的正弦擺動,讓魚不是直線衝向目標,而是自然地左右擺尾游過去
    float perpX = -dirY;
    float perpY = dirX;
    float wiggle = sin(frameCount * 0.06 + wiggleOffset) * 0.18;
    vx += perpX * wiggle;
    vy += perpY * wiggle;

    // 限速,避免速度無上限疊加導致動作生硬暴衝,維持優雅的游動節奏
    float maxSpeed = 4.2;
    float speed = mag(vx, vy);
    if (speed > maxSpeed) {
      vx = vx / speed * maxSpeed;
      vy = vy / speed * maxSpeed;
    }

    x += vx;
    y += vy;
    A = atan2(vy, vx);
    dx = 0;
    dy = 0;
  }

  void rules() {
    // peace手勢時魚群分離距離放大,群體看起來更鬆散地散開游
    float sep = currentGesture.equals("peace") ? 170 : 100;
    ArrayList<Koi> closeedKoi = new ArrayList<Koi>();
    for (Koi other : koi) {
      if (other != this && dist(other.x, other.y, x, y) < sep) closeedKoi.add(other);
    }
    if (closeedKoi.size() == 0) return;
    float dx = 0;
    float dy = 0;
    for (Koi other : closeedKoi) {
      float d = dist(other.x, other.y, x, y);
      dx -= (1 - d / sep) * (other.x - x);
      dy -= (1 - d / sep) * (other.y - y);
    }
    this.dx += dx;
    this.dy += dy;

    vx *= 0.9995;
    vy *= 0.9995;
  }
}

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

    // 玉色系荷葉(比原本偏黃濁的隨機綠更接近真實荷葉的青翠感)
    this.leafColor = color(100 + random(-10, 14), random(40, 65), random(45, 70));
    this.vineColor = color(100 + random(-10, 14), random(45, 65), random(20, 35));

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

    // 葉面高光,增加一點光澤質感
    noStroke();
    fill(255, 255, 255, 35);
    ellipse(-r * 0.25, -r * 0.25, r * 0.6, r * 0.35);

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
