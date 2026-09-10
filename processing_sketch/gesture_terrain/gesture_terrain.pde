/*
手勢控制的 3D noise terrain 生成藝術。
改編自原本「Processing 創意編碼」課堂作業 Noise_Terrain.pde(用 mouseX 控制地形流動速度),
這裡改成接收 Python 端(osc_bridge.py)辨識出的手勢,即時驅動地形流動速度/縮放/配色/攝影機角度。
需要先安裝 oscP5 library(Processing IDE: Sketch > Import Library > Add Library... 搜尋 oscP5)。

手勢 -> 視覺效果對應:
  open_palm  地形流動加速,顏色偏冷色
  fist       地形流動變慢/暫停,顏色偏暖色
  point      鏡頭旋轉角度隨張開度改變
  peace      放大地形尺度(scl變大)
  thumbs_up  切換線框/實心顯示模式
  openness (0~1, 連續值) 額外微調流動速度,讓效果不是死板的離散切換
*/
import oscP5.*;

OscP5 oscP5;
int cols, rows;
int scl = 20;
int w = 1000;
int h = 600;
float xoff, yoff;
float flying = 0;
float[][] terrain;

String currentGesture = "none";
float openness = 0;
float confidence = 0;
boolean wireframe = true;

void setup() {
  size(600, 600, P3D);
  cols = w / scl;
  rows = h / scl;
  terrain = new float[cols][rows];
  background(0);
  oscP5 = new OscP5(this, 8000);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/gesture")) {
    currentGesture = msg.get(0).stringValue();
    openness = msg.get(1).floatValue();
    confidence = msg.get(2).floatValue();
    if (currentGesture.equals("thumbs_up") && confidence > 0.6) {
      wireframe = !wireframe;
    }
  }
}

void draw() {
  translate(width/2, height/2 + 50);
  rotateX(PI/3);

  if (currentGesture.equals("point")) {
    rotateZ(map(openness, 0, 1, -PI/6, PI/6));
  }

  translate(-w/2, -h/2);
  background(0);

  float speed = 0.02 + openness * 0.12;
  if (currentGesture.equals("fist")) speed *= 0.15;
  if (currentGesture.equals("open_palm")) speed *= 1.8;
  flying += speed;
  yoff = flying;

  int effectiveScl = scl;
  if (currentGesture.equals("peace")) effectiveScl = int(scl * 1.6);
  int effCols = w / effectiveScl;
  int effRows = h / effectiveScl;
  if (terrain.length != effCols) terrain = new float[effCols][effRows];

  for (int y = 0; y < effRows; y++) {
    xoff = 0;
    for (int x = 0; x < effCols; x++) {
      terrain[x][y] = map(noise(xoff, yoff), 0, 1, -100, 100);
      xoff += 0.2;
    }
    yoff += 0.2;
  }

  boolean warm = currentGesture.equals("fist");

  if (wireframe) {
    stroke(255, 255, 255, 50);
    noFill();
  } else {
    noStroke();
  }

  for (int y = 0; y < effRows - 1; y++) {
    beginShape(TRIANGLE_STRIP);
    for (int x = 0; x < effCols; x++) {
      float currentHeight = terrain[x][y];
      float nextHeight = terrain[x][y+1];

      float col = map(currentHeight, -100, 100, 0, 255);
      if (warm) {
        fill(255, 100 + col * 0.3, 50);
      } else {
        fill(col, 150, 255 - col);
      }

      vertex(x * effectiveScl, y * effectiveScl, currentHeight);
      vertex(x * effectiveScl, (y+1) * effectiveScl, nextHeight);
    }
    endShape();
  }

  camera();
  hint(DISABLE_DEPTH_TEST);
  textSize(16);
  fill(255);
  text("gesture: " + currentGesture + "  openness: " + nf(openness, 1, 2)
       + "  conf: " + nf(confidence, 1, 2), 10, height - 20);
  hint(ENABLE_DEPTH_TEST);
}
