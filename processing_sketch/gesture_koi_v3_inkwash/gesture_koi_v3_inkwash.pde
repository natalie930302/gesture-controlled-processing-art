/*
【迭代紀錄 v3】水墨留白風嘗試版。
根據參考圖(水墨魚/荷葉造型 + 七彩倒影的水色構圖)重新設計,把v2的寫實錦鯉池改成
水墨留白風格:墨暈荷葉(InkBlob)、簡化魚剪影(Fish)、宣紙紋理底色(buildPaper),
互動也同步簡化成純連續量驅動(手掌位置+openness決定墨漪暈開範圍跟魚群靠近/驚散,
不做離散手勢分支)。

這一版視覺調性跟原本寫實錦鯉池差異太大,實際看過渲染結果後,決定保留原本錦鯉池的
寫實視覺風格(色彩豐富、真的荷葉、貝茲曲線魚身)當作正式版本,但採納這一版驗證過的
「連續互動(不做離散手勢切換)」設計理念跟幾個細節修正(魚游動平滑轉向、荷葉葉脈改
少量偏一側而非放射狀滿版)。這一版留著當作水墨風方向的完整記錄。
*/
import oscP5.*;

OscP5 oscP5;

color paperColor = color(240, 233, 219);
color inkDark = color(45, 42, 38);
color inkMid = color(75, 71, 64);

ArrayList<InkBlob> blobs = new ArrayList<InkBlob>();
ArrayList<Fish> fishes = new ArrayList<Fish>();
ArrayList<Ripple> ripples = new ArrayList<Ripple>();

String currentGesture = "none";
float openness = 0.4;
float confidence = 0.8;
float handX, handY;
boolean haveHand = false;

PFont uiFont;
PGraphics paper;

void setup() {
  size(800, 600);
  handX = width / 2;
  handY = height / 2;

  for (int i = 0; i < 5; i++) blobs.add(new InkBlob());
  for (int i = 0; i < 6; i++) fishes.add(new Fish());

  oscP5 = new OscP5(this, 8000);
  uiFont = createFont("Microsoft JhengHei", 15, true);
  textFont(uiFont);

  buildPaper();
}

// 宣紙紋理:底色疊上細微的雲霧狀noise斑駁 + 纖維顆粒感,只算一次存成貼圖
void buildPaper() {
  paper = createGraphics(width, height);
  paper.beginDraw();
  paper.background(paperColor);
  paper.loadPixels();
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      float mottle = (noise(x * 0.01, y * 0.01) - 0.5) * 16;
      float fiber = (noise(x * 0.4, y * 0.015) - 0.5) * 8;
      int idx = x + y * width;
      color c = paper.pixels[idx];
      float r = constrain(red(c) + mottle + fiber, 0, 255);
      float g = constrain(green(c) + mottle + fiber, 0, 255);
      float b = constrain(blue(c) + mottle + fiber, 0, 255);
      paper.pixels[idx] = color(r, g, b);
    }
  }
  paper.updatePixels();
  paper.noStroke();
  for (int i = 0; i < 1400; i++) {
    float px = random(width);
    float py = random(height);
    float tone = random(1) < 0.5 ? 255 : 0;
    paper.fill(tone, random(8, 20));
    paper.ellipse(px, py, random(0.6, 1.6), random(0.6, 1.6));
  }
  paper.endDraw();
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

// 沒有 webcam/OSC 時,滑鼠拖曳可模擬手掌位置與墨漪,方便單機測試
void mouseDragged() {
  handX = mouseX;
  handY = mouseY;
  haveHand = true;
  spawnRipple(mouseX, mouseY, 0.7);
}

void spawnRipple(float x, float y, float strength) {
  ripples.add(new Ripple(x, y, strength));
}

void draw() {
  image(paper, 0, 0);

  // 手掌持續停留時,依openness決定多久暈開一圈新墨漪——手越張開,暈開得越頻繁越強
  if (haveHand) {
    int interval = int(map(openness, 0, 1, 26, 6));
    if (frameCount % max(interval, 4) == 0) {
      float strength = map(openness, 0, 1, 0.25, 1.0) * map(confidence, 0, 1, 0.3, 1.0);
      spawnRipple(handX, handY, strength);
    }
  }

  for (int i = ripples.size() - 1; i >= 0; i--) {
    Ripple r = ripples.get(i);
    r.update();
    r.draw();
    if (r.done()) ripples.remove(i);
  }

  for (InkBlob b : blobs) b.draw();
  for (Fish f : fishes) {
    f.update();
    f.draw();
  }

  drawStatusPanel();
}

// 墨漪:手掌位置暈開的一圈圈淡出的墨線,openness決定暈開速度/強度
class Ripple {
  float x, y, r, alpha;
  float growth;

  Ripple(float x, float y, float strength) {
    this.x = x;
    this.y = y;
    this.r = 2;
    this.alpha = 100 * strength;
    this.growth = 0.8 + strength * 2.2;
  }

  void update() {
    r += growth;
    alpha -= 1.3;
  }

  boolean done() {
    return alpha <= 0;
  }

  void draw() {
    noFill();
    stroke(red(inkMid), green(inkMid), blue(inkMid), max(alpha, 0));
    strokeWeight(1.1);
    ellipse(x, y, r * 2, r * 2);
  }
}

// 荷葉:多層漸淡、邊緣不規則的墨暈疊起來,取代原本實心綠圓+放射狀黑線的畫法
class InkBlob {
  float x, y, baseR;
  float[] jitter;
  boolean hasFlower;

  InkBlob() {
    x = random(width * 0.1, width * 0.9);
    y = random(height * 0.15, height * 0.85);
    baseR = random(26, 52);
    jitter = new float[10];
    for (int i = 0; i < jitter.length; i++) jitter[i] = random(0.8, 1.15);
    hasFlower = random(1) < 0.35;
  }

  void draw() {
    noStroke();
    for (int layer = 5; layer >= 1; layer--) {
      float rr = baseR * (0.55 + layer * 0.13);
      float a = map(layer, 1, 5, 60, 10);
      fill(red(inkDark), green(inkDark), blue(inkDark), a);
      beginShape();
      int pts = jitter.length;
      for (int i = 0; i < pts; i++) {
        float ang = TWO_PI * i / pts;
        float rad = rr * jitter[i];
        curveVertex(x + cos(ang) * rad, y + sin(ang) * rad * 0.85);
      }
      endShape(CLOSE);
    }

    // 內部幾條細淡的放射墨紋,量少、半透明,不做滿版放射狀黑線
    stroke(red(inkDark), green(inkDark), blue(inkDark), 30);
    strokeWeight(0.6);
    for (int i = 0; i < 5; i++) {
      float ang = TWO_PI * i / 5 + x * 0.01;
      line(x, y, x + cos(ang) * baseR * 0.65, y + sin(ang) * baseR * 0.6);
    }

    if (hasFlower) drawFlower(x + baseR * 0.35, y - baseR * 0.4, baseR * 0.4);
  }

  void drawFlower(float fx, float fy, float fr) {
    noStroke();
    fill(232, 172, 178, 210);
    for (int i = 0; i < 6; i++) {
      float ang = TWO_PI * i / 6;
      pushMatrix();
      translate(fx + cos(ang) * fr * 0.45, fy + sin(ang) * fr * 0.45);
      ellipse(0, 0, fr * 0.75, fr * 0.55);
      popMatrix();
    }
    fill(212, 150, 92, 230);
    ellipse(fx, fy, fr * 0.45, fr * 0.45);
  }
}

// 魚:簡化成幾筆帶過的小剪影,疏疏落落幾隻獨立游動,
// 用openness連續調整「靠近/被驚散」的方向與力道,不做離散手勢分支
class Fish {
  float x, y, angle, facing, wanderT, speed, size, tailPhase;

  Fish() {
    x = random(width);
    y = random(height);
    angle = random(TWO_PI);
    facing = angle;
    wanderT = random(1000);
    tailPhase = random(1000);
    speed = random(0.35, 0.7);
    size = random(9, 15);
  }

  void update() {
    wanderT += 0.008;
    angle += (noise(wanderT) - 0.5) * 0.12;

    float dx = x - handX;
    float dy = y - handY;
    float d = max(mag(dx, dy), 30);

    // openness小(手收攏)時 pushPull 為負,魚被吸引靠近;openness大(手張開)時為正,魚被推開驚散
    float pushPull = map(openness, 0, 1, -0.4, 0.4);
    float falloff = map(confidence, 0, 1, 0.3, 1.0) * (140 / d);
    float ang2 = atan2(dy, dx);

    float vx = cos(angle) * speed + cos(ang2) * pushPull * falloff;
    float vy = sin(angle) * speed + sin(ang2) * pushPull * falloff;

    x += vx;
    y += vy;

    // 朝向角度用平滑逼近(不是每幀直接snap),身體才不會看起來僵硬地瞬間轉向
    float targetFacing = atan2(vy, vx);
    float diff = atan2(sin(targetFacing - facing), cos(targetFacing - facing));
    facing += diff * 0.12;

    tailPhase += 0.15 + mag(vx, vy) * 0.6;

    if (x < -20) x = width + 20;
    if (x > width + 20) x = -20;
    if (y < -20) y = height + 20;
    if (y > height + 20) y = -20;
  }

  void draw() {
    pushMatrix();
    translate(x, y);
    rotate(facing);
    float wag = sin(tailPhase) * 0.5;
    noStroke();
    // 暈染底層
    fill(red(inkMid), green(inkMid), blue(inkMid), 50);
    ellipse(1, 0, size * 1.6, size * 0.95);
    // 身體用橢圓(比尖角風箏形更像魚的輪廓)
    fill(red(inkDark), green(inkDark), blue(inkDark), 220);
    ellipse(size * 0.05, 0, size * 1.35, size * 0.75);
    // 尾鰭:在身體後方隨wag擺動,製造擺尾游動感
    pushMatrix();
    translate(-size * 0.55, 0);
    rotate(wag * 0.9);
    triangle(0, 0, -size * 0.7, size * 0.4, -size * 0.7, -size * 0.4);
    popMatrix();
    popMatrix();
  }
}

// 即時狀態面板:手勢名稱只當除錯資訊顯示,不驅動任何效果分支
void drawStatusPanel() {
  noStroke();
  fill(255, 255, 255, 150);
  rect(10, 10, 250, 110, 10);

  fill(60);
  textSize(15);
  text("手勢 gesture: " + currentGesture + "(僅供參考)", 22, 32);

  fill(90);
  textSize(12);
  text("openness", 22, 54);
  noFill();
  stroke(120);
  rect(95, 46, 130, 10, 4);
  noStroke();
  fill(120, 150, 170);
  rect(95, 46, 130 * constrain(openness, 0, 1), 10, 4);

  fill(90);
  text("confidence", 22, 74);
  noFill();
  stroke(120);
  rect(95, 66, 130, 10, 4);
  noStroke();
  fill(confidence > 0.6 ? color(120, 170, 130) : color(200, 150, 90));
  rect(95, 66, 130 * constrain(confidence, 0, 1), 10, 4);

  fill(90);
  textSize(12);
  String state = openness > 0.55 ? "手張開,魚被驚散" : "手收攏,魚正靠近";
  text("-> " + state, 22, 96);
}
