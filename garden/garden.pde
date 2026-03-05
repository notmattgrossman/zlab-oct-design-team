import processing.sound.*;

final int rows = 3;
final int cols = 3;
  float gameStartTime;
  float spacingX, spacingY;
  float viewWidth;
  float globalScale = 1.0;
  PGraphics scene;
  ArrayList<ArrayList<Plant>> plants = new ArrayList<ArrayList<Plant>>();
ArrayList<Droplet> droplets = new ArrayList<Droplet>();

PShape potShape; // unused, kept for reference if needed? No, converting to PImage
PImage potImage;
PImage stemImage;
PImage backgroundImage;
PImage[] flowerImages = new PImage[3];
PFont font;

float canRotation = 0;
final float growTime = 5000;

SoundFile backgroundSound;
SoundFile waterSound;
SoundFile[] twinkleSounds = new SoundFile[3];
float waterVolumeTarget = 0;
float waterVolumeLevel = 0;
boolean waterSoundPlaying = false;
final float waterFadeSpeed = 0.02f;

void settings() {
  size(960, 400);
}

void setup() {
  surface.setResizable(true);
  viewWidth = width / 2.0f;
  scene = createGraphics(int(viewWidth), height);
  gameStartTime = millis();
  // Load assets with absolute paths to ensure they are found
  String potPath = dataPath("img/pot.png");
  File f = new File(potPath);
  if (!f.exists()) println("ERROR: File not found at " + potPath);
  
  potImage = loadImage(dataPath("img/pot.png"));
  stemImage = loadImage(dataPath("img/stem.png"));
  backgroundImage = loadImage(dataPath("img/background.jpg"));
  flowerImages[0] = loadImage(dataPath("img/sunflower.png"));
  flowerImages[1] = loadImage(dataPath("img/pinkflower.png"));
  flowerImages[2] = loadImage(dataPath("img/blueflower.png"));

  // Setup font
  font = createFont("Arial", 14);
  textFont(font);

  spacingX = viewWidth / (cols + 1f);
  spacingY = height / (rows + 1f);

  for (int r = 0; r < rows; r++) {
    ArrayList<Plant> row = new ArrayList<Plant>();
    plants.add(row);
    for (int c = 0; c < cols; c++) {
      float x = (c + 1) * spacingX;
      float y = (r + 1) * spacingY;
      row.add(new Plant(x, y, r, c));
    }
  }

  // Audio setup
  try {
    backgroundSound = new SoundFile(this, dataPath("garden-sfx/background.mp3"));
    backgroundSound.loop();
    backgroundSound.amp(0.35f);

    waterSound = new SoundFile(this, dataPath("garden-sfx/water.mp3"));
    waterSound.loop();
    waterSound.amp(0);

    String[] twinklePaths = {
      dataPath("garden-sfx/twinkle.mp3"),
      dataPath("garden-sfx/twinkle-1.mp3"),
      dataPath("garden-sfx/twinkle-2.mp3")
    };
    for (int i = 0; i < twinkleSounds.length; i++) {
      twinkleSounds[i] = new SoundFile(this, twinklePaths[i]);
    }
  } catch (Exception e) {
    println("Audio setup failed (files missing?): " + e);
  }
}

void draw() {
  // Ensure viewWidth stays in sync if the window changes outside windowResized
  viewWidth = width / 2.0f;
  int newSceneW = max(1, int(viewWidth));
  int newSceneH = max(1, height);
  
  // Calculate global scale based on default design width (960)
  // Current single view width is 'viewWidth'
  // We want to fit the original 960x1080 design into 'viewWidth' x 'height'
  globalScale = min(viewWidth / 960.0f, height / 1080.0f);

  if (scene == null || scene.width != newSceneW || scene.height != newSceneH) {
     scene = createGraphics(newSceneW, newSceneH);
  }

  float logicalMX = mouseX % viewWidth;
  logicalMX = constrain(logicalMX, 0, viewWidth);
  float logicalMY = mouseY;

  int fullyGrown = updateState(logicalMX, logicalMY);

  scene.beginDraw();
  renderScene(scene, logicalMX, logicalMY, fullyGrown);
  scene.endDraw();
  
  imageMode(CORNER);
  image(scene, 0, 0);
  image(scene, viewWidth, 0);
}

int updateState(float mx, float my) {
  boolean isWatering = false;
  int fullyGrown = 0;
  
  Plant targetPlant = null;
  float minDist = Float.MAX_VALUE;
  
  // Calculate spout position in logical coordinates (unscaled) for detection
  // We need to reverse the scaling or apply scaling to detection thresholds
  // But detecting in screen space is easier if we know where things are.
  // Plant positions (x, y) are logical coordinates.
  // mx, my are logical coordinates.
  
  // The previous logic used dist(mx + 75, my + 75, plant.x, plant.y) < 70
  // This implies the "center" of action was offset.
  // Let's use the calculated spout position for more accurate "above" detection.
  
  // We need a spout position relative to the logical mouse position (mx, my)
  // getSpoutPosition uses globalScale. We want logical coordinates.
  // Let's approximate logical spout position:
  float spoutLogicalX = mx + 38 + cos(radians(-20)) * 60; // Approx based on getSpoutPosition base values
  float spoutLogicalY = my - 8 + sin(radians(-20)) * 60;
  
  // Actually, simpler: Use the same offset logic but check bounds.
  // User wants "above that plant".
  // Let's define a hit box around the plant pot.
  // Plant is centered at plant.x, plant.y (center of pot).
  // Pot is roughly 70 wide.
  
  for (ArrayList<Plant> row : plants) {
    for (Plant plant : row) {
      // Check horizontal alignment: Mouse is near the pot center
      if (abs(mx - plant.x) < 35) { // Tighter horizontal check (pot is ~70 wide)
         // Check vertical alignment: STRICTLY hovering the pot area.
         // Pot center is at plant.y. Pot is roughly 60-70px tall visually.
         // Let's say the pot area is from (plant.y - 35) to (plant.y + 35).
         if (abs(my - plant.y) < 35) {
            float d = dist(mx, my, plant.x, plant.y);
            if (d < minDist) {
              minDist = d;
              targetPlant = plant;
            }
         }
      }
    }
  }

  for (ArrayList<Plant> row : plants) {
    for (Plant plant : row) {
      boolean active = (plant == targetPlant);
      plant.update(active);
      
      if (plant.growth >= 1) {
        fullyGrown++;
      }
      
      if (plant.watering) {
        isWatering = true;
        if (random(1) < 0.3f) {
          // Use globalScale for visual spout position
          PVector spout = getSpoutPosition(mx, my);
          droplets.add(new Droplet(spout.x, spout.y, plant));
        }
      }
    }
  }

  float targetRotation = isWatering ? 33 : 0;
  canRotation = lerp(canRotation, targetRotation, 0.15f);

  for (int i = droplets.size() - 1; i >= 0; i--) {
    Droplet d = droplets.get(i);
    d.update();
    if (d.shouldRemove()) {
      droplets.remove(i);
    }
  }

  updateWaterSound(isWatering);
  processWaterFade();
  return fullyGrown;
}

void renderScene(PGraphics pg, float mx, float my, int fullyGrown) {
  if (backgroundImage != null) {
    float bgAspect = (float)backgroundImage.width / backgroundImage.height;
    float viewAspect = (float)pg.width / pg.height;
    
    pg.imageMode(CORNER);
    if (viewAspect > bgAspect) {
         // View is wider relative to image. Scale by width.
         float drawHeight = pg.width / bgAspect;
         float yOffset = (pg.height - drawHeight) / 2;
         pg.image(backgroundImage, 0, yOffset, pg.width, drawHeight);
    } else {
         // View is taller relative to image. Scale by height.
         float drawWidth = pg.height * bgAspect;
         float xOffset = (pg.width - drawWidth) / 2;
         pg.image(backgroundImage, xOffset, 0, drawWidth, pg.height);
    }
  } else {
    // Fallback fill
    pg.noStroke();
    pg.fill(220, 245, 255);
    pg.rect(0, 0, pg.width, pg.height);
  }

  pg.fill(30, 80, 180, 43);
  pg.noStroke();
  pg.rect(0, 0, pg.width, pg.height);

  for (ArrayList<Plant> row : plants) {
    for (Plant plant : row) {
      plant.display(pg, globalScale);
    }
  }

  for (Droplet d : droplets) {
    d.display(pg, globalScale);
  }

  drawCan(pg, mx - 85 * globalScale, my - 85 * globalScale, globalScale);
  drawHud(pg, fullyGrown);
}

void updateWaterSound(boolean pouring) {
  if (waterSound == null) return;
  
  waterVolumeTarget = pouring ? 0.55f : 0;
  if (pouring && !waterSoundPlaying) {
    waterVolumeLevel = 0;
    waterSound.amp(0);
    waterSound.play();
    waterSoundPlaying = true;
  }
}

void processWaterFade() {
  if (waterSound == null) return;
  if (!waterSoundPlaying && waterVolumeLevel == 0 && waterVolumeTarget == 0) {
    return;
  }

  if (abs(waterVolumeLevel - waterVolumeTarget) <= waterFadeSpeed) {
    waterVolumeLevel = waterVolumeTarget;
  } else if (waterVolumeLevel < waterVolumeTarget) {
    waterVolumeLevel += waterFadeSpeed;
  } else {
    waterVolumeLevel -= waterFadeSpeed;
  }

  waterVolumeLevel = constrain(waterVolumeLevel, 0, 0.55f);
  waterSound.amp(waterVolumeLevel);

  if (waterVolumeTarget == 0 && waterVolumeLevel == 0 && waterSoundPlaying) {
    waterSound.stop();
    waterSoundPlaying = false;
  }
}

void drawHud(PGraphics pg, int fullyGrown) {
  float bannerHeight = 35;
  // Draw banner background across the full viewWidth
  pg.fill(144, 238, 144);
  pg.noStroke();
  pg.rect(0, pg.height - bannerHeight, pg.width, bannerHeight);
  
  pg.fill(0, 100, 0);
  pg.textAlign(LEFT, CENTER);
  pg.textSize(14);
  pg.text("Flowers: " + fullyGrown + " / 9", 20, pg.height - bannerHeight / 2);
  
  pg.textAlign(CENTER, CENTER);
  // Ensure center text is actually centered in the view
  pg.text("Water the plants to see the flowers bloom!", pg.width / 2, pg.height - bannerHeight / 2);
  
  int minutes = floor((millis() - gameStartTime) / 60000);
  int seconds = floor(((millis() - gameStartTime) % 60000) / 1000);
  String timeString = nf(minutes, 0) + ":" + nf(seconds, 2);
  pg.textAlign(RIGHT, CENTER);
  pg.text(timeString, pg.width - 20, pg.height - bannerHeight / 2);
}

PVector getSpoutPosition(float canX, float canY) {
  float spoutBaseX = 38 * globalScale;
  float spoutBaseY = -8 * globalScale;
  float spoutAngle = radians(-20);
  float spoutLength = 60 * globalScale;
  float spoutTipX = spoutBaseX + cos(spoutAngle) * spoutLength;
  float spoutTipY = spoutBaseY + sin(spoutAngle) * spoutLength;
  float canAngle = radians(canRotation);
  float rotatedX = spoutTipX * cos(canAngle) - spoutTipY * sin(canAngle);
  float rotatedY = spoutTipX * sin(canAngle) + spoutTipY * cos(canAngle);
  return new PVector(canX + rotatedX, canY + rotatedY);
}

void drawCan(PGraphics pg, float x, float y, float scale) {
  pg.pushMatrix();
  pg.translate(x, y);
  pg.scale(scale);
  pg.rotate(radians(canRotation));
  pg.noStroke();
  pg.fill(60, 170, 255);
  pg.rect(-33, -15, 68, 75);
  pg.fill(90, 190, 255);
  pg.ellipse(0, -15, 68, 23);
  pg.noFill();
  pg.stroke(60, 170, 255);
  pg.strokeWeight(9);
  pg.arc(0, -15, 60, 105, PI, TWO_PI);
  pg.noStroke();
  pg.fill(60, 170, 255);
  pg.pushMatrix();
  pg.translate(38, -8);
  pg.rotate(radians(-20));
  pg.rect(-15, 0, 60, 15, 5);
  pg.quad(38, 15, 53, 23, 53, -8, 38, 0);
  pg.popMatrix();
  pg.popMatrix();
}

class Plant {
  float x, y;
  int row, col;
  boolean watering;
  float growth;
  float startTime;
  boolean twinklePlayed;
  int flowerIndex;

  Plant(float x, float y, int row, int col) {
    this.x = x;
    this.y = y;
    this.row = row;
    this.col = col;
    this.flowerIndex = (row * 2 + col) % flowerImages.length;
  }

  void update(boolean isBeingWatered) {
    if (isBeingWatered) {
      if (growth >= 1) {
        watering = false;
        return;
      }
      if (!watering) {
        watering = true;
        startTime = millis();
        growth = 0;
        twinklePlayed = false;
      }
      growth = constrain((millis() - startTime) / growTime, 0, 1);
      if (growth >= 1 && !twinklePlayed) {
        playTwinkleSound(flowerIndex);
        twinklePlayed = true;
      }
    } else {
      watering = false;
    }
  }

  void display(PGraphics pg, float scale) {
    pg.pushMatrix();
    pg.translate(x, y);
    pg.scale(scale);
    float stemStartY = -25;
    float maxStemHeight = 80;
    
    // Use actual image dimensions to preserve aspect ratio
    float stemRatio = (float)stemImage.width / stemImage.height;
    float fixedStemHeight = 80; // Max height we want
    float fixedStemWidth = fixedStemHeight * stemRatio * 1.1f; // Keep the 10% thickness boost if desired
    
    float flowerCenterY = 0;
    if (growth > 0) {
      float currentStemHeight = maxStemHeight * growth;
      flowerCenterY = stemStartY - currentStemHeight;
    }
    if (growth > 0) {
      float potBottomY = 40;
      float stemBottomY = flowerCenterY + fixedStemHeight;
      float visibleHeight = fixedStemHeight;
      if (stemBottomY > potBottomY) {
        visibleHeight = potBottomY - flowerCenterY;
        // Calculate source cropping based on visible proportion
        int sourceVisibleHeight = (int)((visibleHeight / fixedStemHeight) * stemImage.height);
        
        pg.imageMode(CORNER);
        pg.image(stemImage, -fixedStemWidth / 2, flowerCenterY, fixedStemWidth, visibleHeight, 0, 0, stemImage.width, sourceVisibleHeight);
      } else {
        pg.imageMode(CORNER);
        pg.image(stemImage, -fixedStemWidth / 2, flowerCenterY, fixedStemWidth, fixedStemHeight);
      }
      pg.imageMode(CENTER);
      float maxSize = (flowerIndex == 2) ? 90 : 72;
      float baseSize = 24 + ((maxSize - 24) * growth);
      PImage flower = flowerImages[flowerIndex];
      float aspectRatio = (float)flower.width / flower.height;
      float flowerWidth, flowerHeight;
      if (aspectRatio > 1) {
        flowerWidth = baseSize;
        flowerHeight = baseSize / aspectRatio;
      } else {
        flowerHeight = baseSize;
        flowerWidth = baseSize * aspectRatio;
      }
      pg.image(flower, 0, flowerCenterY, flowerWidth, flowerHeight);
    }
    pg.imageMode(CENTER);
    
    float potMaxDim = 70;
    float potRatio = (float)potImage.width / potImage.height;
    float potW, potH;
    if (potRatio > 1) {
      potW = potMaxDim;
      potH = potMaxDim / potRatio;
    } else {
      potH = potMaxDim;
      potW = potMaxDim * potRatio;
    }
    
    pg.tint(0, 0, 0, 100);
    pg.image(potImage, 2, 8, potW, potH);
    pg.noTint();
    pg.image(potImage, 0, 5, potW, potH);
    pg.popMatrix();
  }
}

class Droplet {
  float x, y;
  float speed;
  float len;
  float targetY;
  boolean done = false;

  Droplet(float x, float y, Plant plant) {
    this.x = x + random(-8, 8);
    this.y = y + random(-8, 8);
    this.speed = random(4, 8);
    this.len = random(8, 15);
    this.targetY = (plant != null) ? plant.y - 30 : height + len;
  }

  void update() {
    if (done) {
      return;
    }
    y += speed;
    if (y + len >= targetY) {
      y = targetY - len;
      done = true;
    }
  }

  void display(PGraphics pg, float scale) {
    pg.stroke(0, 120, 255);
    pg.strokeWeight(3 * scale);
    pg.line(x, y, x, y + len * scale);
  }

  boolean shouldRemove() {
    return done || y > height + len;
  }
}

void playTwinkleSound(int index) {
  if (twinkleSounds[0] == null) { // Check if loaded
    return;
    
  }
  int source = index % twinkleSounds.length;
  SoundFile clip = twinkleSounds[source];
  if (clip != null) {
    clip.play();
  }
}

void windowResized() {
  viewWidth = width / 2.0f;
  spacingX = viewWidth / (cols + 1f);
  spacingY = height / (rows + 1f);

  for (ArrayList<Plant> row : plants) {
    for (Plant plant : row) {
      plant.x = (plant.col + 1) * spacingX;
      plant.y = (plant.row + 1) * spacingY;
    }
  }
}
