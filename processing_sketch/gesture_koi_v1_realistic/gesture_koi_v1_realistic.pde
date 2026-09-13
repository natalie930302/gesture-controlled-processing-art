/*
【迭代紀錄 v1】寫實錦鯉版 + 離散手勢效果設計。
這是gesture_koi最早的版本:錦鯉配色改用真實品種色系(紅白緋鯉Kohaku、黃金鯉Ogon、
白鯉Shiro、墨鯉Sumi、丹頂系),5種手勢各自觸發明顯不同的離散效果,並用暗角(vignette)
營造聚焦感。後來因為「配色跟審美美學很重要」的回饋,加上想要更連續、更禪意的互動,
朝向水墨風+連續openness驅動的方向重新設計(見 processing_sketch/gesture_koi),
但保留這一版讓迭代過程看得見:從「技術上展示豐富離散效果」到「美學上收斂成連續互動」
的轉折,本身就是這個專案值得記錄的設計決策過程。

手勢 -> 視覺效果對應(這一版的設計):
  手掌位置(即時追蹤)         取代滑鼠,成為魚群游動的吸引目標;手掌經過處持續產生水波、推開附近荷葉
  open_palm                  水面漣漪頻率提高(擾動變多),配色偏冷色
  fist                       魚群游動變慢、對手掌反應變弱,配色偏暖色,漣漪變少(平靜)
  point                      強力吸引魚群聚集到手掌位置(像餵食)
  peace                      魚群分離距離放大(散開游),荷葉被推得更遠(像一陣風吹過)
  thumbs_up(confidence>0.6)  切換「月夜模式」:背景偏暗藍,魚群顏色變亮
  confidence(連續值0~1)      信心值越低,魚群對手掌的反應越弱/越遲鈍,誠實反映辨識的不確定性
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

PGraphics vignette;

void setup() {
  size(800, 600);
  W = width;
  H = height;
  current = new float[W][H];
  previous = new float[W][H];

  // 錦鯉/荷葉的配色用 HSB 設計(比較容易調出接近真實錦鯉品種的色系),
  // 水面像素運算用 RGB(方便跟 red()/green()/blue() 對應),兩段用完各自切回來
  colorMode(HSB, 360, 100, 100);
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

  buildVignette();
}

// 畫面四角暗角,只在 setup 算一次存成貼圖,draw() 裡只是貼上去,不吃效能
void buildVignette() {
  vignette = createGraphics(width, height);
  vignette.beginDraw();
  vignette.noStroke();
  float maxDist = dist(0, 0, width / 2.0, height / 2.0);
  int step = 4;
  for (int vy = 0; vy < height; vy += step) {
    for (int vx = 0; vx < width; vx += step) {
      float d = dist(vx, vy, width / 2.0, height / 2.0);
      float a = map(d, maxDist * 0.35, maxDist, 0, 150);
      a = constrain(a, 0, 150);
      vignette.fill(0, a);
      vignette.rect(vx, vy, step, step);
    }
  }
  vignette.endDraw();
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

  for (Koi v : koi) {
    v.draw();
  }

  loadPixels();
  boolean warm = currentGesture.equals("fist");
  for (int x = 1; x < width - 1; x++) {
    for (int y = 1; y < height - 1; y++) {
      color originalColor = get(x, y);
      float noiseValue = noise(x * 0.02, y * 0.02, frameCount * 0.02);
      float r = red(originalColor) + noiseValue * 100;
      float g = green(originalColor) + noiseValue * 100;
      float b = blue(originalColor) + noiseValue * 100;

      // 預設(平靜)水色走青碧/玉色調,warm/night 兩種手勢模式各自疊自己的濾鏡
      float rCap = 120, gCap = 190, bCap = 205;
      if (warm) {
        r += 50; g *= 0.85; b *= 0.5;
        rCap = 255; gCap = 190; bCap = 120;
      }
      if (nightMode) {
        r *= 0.5; g *= 0.6; b = b * 0.8 + 60;
        rCap = min(rCap, 90); gCap = min(gCap, 130); bCap = 255;
      }
      r = constrain(r, 0, rCap);
      g = constrain(g, 0, gCap);
      b = constrain(b, 0, bCap);

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

  image(vignette, 0, 0);

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
    assignColors();
  }

  // 隨機挑一個接近真實錦鯉品種的配色(紅白緋鯉/黃金鯉/白鯉/墨鯉/丹頂桃紅),
  // 而不是原本沒特別設計過、偏濁的隨機色相
  void assignColors() {
    float roll = random(1);
    float hue, sat, bri;
    if (roll < 0.12) {          // 白鯉(Shiro)
      hue = random(360); sat = random(0, 6); bri = random(90, 100);
    } else if (roll < 0.22) {   // 墨鯉(Sumi)
      hue = random(360); sat = random(0, 10); bri = random(8, 18);
    } else if (roll < 0.45) {   // 緋鯉/紅白(Kohaku)
      hue = random(2, 14); sat = random(75, 95); bri = random(85, 100);
    } else if (roll < 0.70) {   // 黃金鯉(Ogon)
      hue = random(40, 52); sat = random(55, 80); bri = random(85, 100);
    } else {                    // 丹頂/桃紅(Tancho系)
      hue = random(335, 355); sat = random(55, 80); bri = random(80, 95);
    }
    this.c1 = color(hue, sat, bri);
    this.c2 = color(hue, max(sat - 15, 0), max(bri - 18, 10));
  }

  void draw() {
    noStroke();
    update();
    a += dist(0, 0, vx, vy) / 100;
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
    float mag = max(dist(x, y, handX, handY), 0.0001);
    dirX /= mag;
    dirY /= mag;

    // 吸引力道:基本值隨張開度增加,point手勢(像餵食)大幅提高,fist(平靜)大幅降低,
    // 並用信心值衰減——辨識越不確定,魚群反應越弱/越遲鈍
    float attract = 0.15 + openness * 0.2;
    if (currentGesture.equals("point")) attract = 0.6;
    if (currentGesture.equals("fist")) attract *= 0.3;
    attract *= map(confidence, 0, 1, 0.4, 1.0);

    vx += dirX * attract;
    vy += dirY * attract;
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
