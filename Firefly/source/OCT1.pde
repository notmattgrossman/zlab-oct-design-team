import processing.sound.*;

final float CAPTURE_DISTANCE = 65;

final float FILL_TIME_MS  = 3000;
final float DRAIN_TIME_MS = 800;

final int   GAMEPLAY_TARGET_CATCHES = 9;
final float CORNER_MARGIN = 70;

final float MAX_SPEED = 3.2;
final float WANDER_STRENGTH = 0.18;

final float BG_MARGIN = 90;
final float BG_FOLLOW = 0.65;

enum Phase { GAMEPLAY, DONE }
Phase phase = Phase.GAMEPLAY;

float progress = 0;


// Firefly
PVector fireflyPos = new PVector();

// grid of fixed spawn positions (3x3)
PVector[] gridPositions;

// Gameplay
int gameplayCatches = 0;
int gridIndex = 0;

// panic movement
PVector fireflyAnchor = new PVector();
PVector fireflyOffset = new PVector();

// BG
PImage bgImage;
String bgFile = "Forest.png";

// Jar cursor
PImage jarOpen;
PImage jarClosed;

// Cap jar size on screen
final float JAR_MAX_W = 150;
final float JAR_MAX_H = 150;

PGraphics glowSprite;
PGraphics scene;
int glowSize = 120;

SoundFile catchSound;
boolean audioStarted = false;
boolean soundDisabled = false;
boolean startSoundPlayed = false;

final int worldW = 800;
final int worldH = 480;

void setup() {
  size(1600, 480);
  surface.setResizable(false);
  noCursor();

  pixelDensity(displayDensity());
  smooth(4);

  bgImage = loadImage(bgFile);
  if (bgImage == null) println("ERROR: Could not load background: " + bgFile + " (check /data and filename case)");

  jarOpen = loadImage("jar_open.png");
  if (jarOpen == null) println("ERROR: Could not load jar_open.png (check /data)");

  jarClosed = loadImage("jar_closed.png");
  if (jarClosed == null) println("ERROR: Could not load jar_closed.png (check /data)");

  // Audio
  try {
    catchSound = new SoundFile(this, "Sound.mp3");
    audioStarted = true;
  } catch (Exception e) {
    println("Audio file not found or error loading sound");
    catchSound = null;
    soundDisabled = true;
  }

  glowSprite = createGraphics(glowSize, glowSize);
  glowSprite.smooth(4);
  buildGlowSprite();

  scene = createGraphics(worldW, worldH);
  scene.smooth(4);

  initGridPositions();
  startGameplay();

  playStartSound();
}

void keyPressed() {
  playStartSound();
}

void mousePressed() {
  playStartSound();
}

void draw() {
  float worldMouseX = map(mouseX, 0, width, 0, worldW);
  float worldMouseY = map(mouseY, 0, height, 0, worldH);
  worldMouseX = constrain(worldMouseX, 0, worldW);
  worldMouseY = constrain(worldMouseY, 0, worldH);

  if (phase == Phase.GAMEPLAY) {
    boolean hovering = dist(worldMouseX, worldMouseY, fireflyPos.x, fireflyPos.y) < CAPTURE_DISTANCE;
    updatePanicFirefly(hovering);
  }

  if (phase != Phase.DONE) updateCatchLogic(worldMouseX, worldMouseY);

  renderWorld(scene, worldMouseX, worldMouseY);

  image(scene, 0, 0);
  image(scene, worldW, 0);
}

void playStartSound() {
  if (startSoundPlayed) return;
  if (!audioStarted || catchSound == null || soundDisabled) return;

  try {
    catchSound.amp(0.3);
    catchSound.play();
    startSoundPlayed = true;
  } catch (Exception e) {
    startSoundPlayed = false;
  }
}

void renderWorld(PGraphics g, float mx, float my) {
  g.beginDraw();

  g.background(0);

  if (bgImage != null) {
    float nx = constrain(mx / worldW, 0, 1);
    float ny = constrain(my / worldH, 0, 1);

    float offX = (nx - 0.5) * 2 * BG_MARGIN * BG_FOLLOW;
    float offY = (ny - 0.5) * 2 * BG_MARGIN * BG_FOLLOW;

    g.image(bgImage,
      -BG_MARGIN - offX,
      -BG_MARGIN - offY,
      worldW + BG_MARGIN * 2,
      worldH + BG_MARGIN * 2);
  } else {
    g.fill(255);
    g.textAlign(CENTER, CENTER);
    g.text("Missing background image: " + bgFile + "\nPut it in /data and match the exact filename.",
      worldW/2, worldH/2);
  }

  if (phase != Phase.DONE) {
    drawFireflyTo(g, fireflyPos.x, fireflyPos.y);
    drawCatcherTo(g, mx, my, progress);
  } else {
    drawCatcherTo(g, mx, my, 0);
  }

  g.endDraw();
}

void startGameplay() {
  phase = Phase.GAMEPLAY;
  gameplayCatches = 0;
  gridIndex = 0;
  spawnGridFirefly();
}

void finishAll() {
  phase = Phase.DONE;
}

void updateCatchLogic(float x, float y) {
  float d = dist(x, y, fireflyPos.x, fireflyPos.y);
  boolean onTarget = d < CAPTURE_DISTANCE;
  float dt = safeDeltaMs();

  if (onTarget) progress += dt / FILL_TIME_MS;
  else          progress -= dt / DRAIN_TIME_MS;

  progress = constrain(progress, 0, 1);

  if (progress >= 1) {
    playCatchSound();
    progress = 0;

    // gameplay only
    gameplayCatches++;
    gridIndex++;
    if (gameplayCatches >= GAMEPLAY_TARGET_CATCHES) finishAll();
    else spawnGridFirefly();
  }
}

void spawnGridFirefly() {
  if (gridPositions == null || gridPositions.length == 0) return;
  if (gridIndex < 0) gridIndex = 0;
  if (gridIndex >= gridPositions.length) gridIndex = gridPositions.length - 1;

  fireflyAnchor.set(gridPositions[gridIndex]);
  fireflyOffset.set(0, 0);
  fireflyPos.set(fireflyAnchor);
}

void updatePanicFirefly(boolean hovering) {
  float dt = safeDeltaMs() / 1000.0; // seconds

  if (!hovering) {
    float maxOffset = 10;

    float t = millis() * 0.00035;

    float nx = noise(1000 + t) * 2 - 1;
    float ny = noise(2000 + t) * 2 - 1;

    PVector target = new PVector(nx * maxOffset, ny * maxOffset);

    float ease = 0.10;
    fireflyOffset.x = lerp(fireflyOffset.x, target.x, ease);
    fireflyOffset.y = lerp(fireflyOffset.y, target.y, ease);

  } else {
    float maxOffset = 34;
    float jitter    = 220;
    float damping   = 0.80;

    fireflyOffset.x += random(-jitter, jitter) * dt;
    fireflyOffset.y += random(-jitter, jitter) * dt;

    fireflyOffset.mult(damping);

    if (fireflyOffset.mag() > maxOffset) {
      fireflyOffset.normalize().mult(maxOffset);
    }
  }

  fireflyPos.set(fireflyAnchor.x + fireflyOffset.x,
                 fireflyAnchor.y + fireflyOffset.y);

  fireflyPos.x = constrain(fireflyPos.x, 20, worldW - 20);
  fireflyPos.y = constrain(fireflyPos.y, 20, worldH - 20);
}

void initGridPositions() {
  gridPositions = new PVector[9];
  // positions at corners and centers of edges/center using a margin
  float[] xs = {CORNER_MARGIN, worldW/2.0, worldW - CORNER_MARGIN};
  float[] ys = {CORNER_MARGIN, worldH/2.0, worldH - CORNER_MARGIN};
  int k = 0;
  for (int j = 0; j < 3; j++) {
    for (int i = 0; i < 3; i++) {
      gridPositions[k++] = new PVector(xs[i], ys[j]);
    }
  }
}

float safeDeltaMs() {
  return (frameRate > 0) ? 1000.0 / frameRate : 16;
}

void buildGlowSprite() {
  glowSprite.beginDraw();
  glowSprite.clear();
  glowSprite.noStroke();
  glowSprite.blendMode(ADD);

  float c = glowSize / 2.0;
  for (int i = 30; i >= 1; i--) {
    float r = map(i, 1, 30, glowSize * 0.48, 0);
    float a = map(i, 1, 30, 0, 255) * 0.14;
    glowSprite.fill(255, 230, 90, a);
    glowSprite.circle(c, c, r * 2);
  }

  glowSprite.blendMode(BLEND);
  glowSprite.fill(255, 255, 210, 240);
  glowSprite.circle(c, c, 10);
  glowSprite.endDraw();
}

void drawFireflyTo(PGraphics g, float x, float y) {
  float pulse = sin(millis() * 0.003) * 0.12 + 1.05;
  g.imageMode(CENTER);
  g.blendMode(ADD);
  g.image(glowSprite, x, y, glowSize * pulse, glowSize * pulse);
  g.blendMode(BLEND);
  g.imageMode(CORNER);
}

// JAR cursor + progress bar
void drawCatcherTo(PGraphics g, float x, float y, float p) {
  float d = dist(x, y, fireflyPos.x, fireflyPos.y);
  boolean hovering = d < CAPTURE_DISTANCE;

  PImage jar = hovering ? jarClosed : jarOpen;
  if (jar == null) jar = jarOpen;

  if (jar == null) return;

  float s = min(JAR_MAX_W / jar.width, JAR_MAX_H / jar.height);
  s = min(s, 1.0);

  float drawW = jar.width * s;
  float drawH = jar.height * s;

  g.imageMode(CENTER);
  g.image(jar, x, y, drawW, drawH);

  float frac = constrain(p, 0, 1);
  if (frac > 0) {
    float radius = max(drawW, drawH) * 0.9;
    float endAngle = -HALF_PI + TWO_PI * frac;

    g.noFill();
    g.blendMode(ADD);

    int glowLayers = 5;
    for (int i = glowLayers; i > 0; i--) {

      float t = i / float(glowLayers);

      float weight = map(t, 0, 1, 2, 10);
      float alpha  = map(t, 0, 1, 20, 100);

      g.stroke(255, 240, 120, alpha);
      g.strokeWeight(weight);

      g.arc(x, y, radius, radius, -HALF_PI, endAngle);
    }

    g.stroke(255, 255, 180);
    g.strokeWeight(4);
    g.arc(x, y, radius, radius, -HALF_PI, endAngle);

    g.blendMode(BLEND);
  }

  g.imageMode(CORNER);
}

void playCatchSound() {
  if (audioStarted && catchSound != null && !soundDisabled) {
    try {
      catchSound.amp(0.3);
      catchSound.play();
    } catch (Exception e) {
      soundDisabled = true;
      catchSound = null;
    }
  }
}
