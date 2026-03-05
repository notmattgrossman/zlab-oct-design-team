import java.util.*;
import processing.sound.*;

final int COLS = 3;
final int ROWS = 4;

final float DESIGN_WIDTH = 800f;
final float DESIGN_HEIGHT = 480f;
final float BASE_CARD_WIDTH = 110f;
final float BASE_CARD_HEIGHT = 166f;
final float BASE_CARD_SPACING_X = 114f;
final float BASE_CARD_SPACING_Y = 24f;
final float BASE_HOVER_CIRCLE_RADIUS = 40f;
final float PADDING_X_RATIO = 0.15f;
final float PADDING_Y_RATIO = 0.12f;

final int FILL_DURATION = 5000;
final int FLIP_DURATION = 300;
final int MISMATCH_DURATION = 1500;

PImage bgImage;
PImage blueCard;
PImage redCard;
PImage[] cardVariants;
int[][] cardAssignments;
PFont monoFont;
SoundFile flipSound;
SoundFile fanfareSound;

PGraphics scene;
float viewWidth = 0;
float viewHeight = 0;

float layoutScale = 1f;
float cardWidth = BASE_CARD_WIDTH;
float cardHeight = BASE_CARD_HEIGHT;
float cardSpacingX = BASE_CARD_SPACING_X;
float cardSpacingY = BASE_CARD_SPACING_Y;
float hoverCircleRadius = BASE_HOVER_CIRCLE_RADIUS;
float paddingX = 0;
float paddingY = 0;
float totalGridWidth = 0;
float totalGridHeight = 0;
float startX = 0;
float startY = 0;

ArrayList<FlippedCard> flippedCards = new ArrayList<FlippedCard>();
ArrayList<FlippingCard> flippingCards = new ArrayList<FlippingCard>();
ArrayList<CardPos> matchedCards = new ArrayList<CardPos>();
ArrayList<ConfettiParticle> confettiParticles = new ArrayList<ConfettiParticle>();

long hoverStartTime = -1;
boolean wasHovering = false;
int hoveredCardRow = -1;
int hoveredCardCol = -1;
long mismatchStartTime = -1;
long gameStartTime = -1;
int totalFlips = 0;

String[] CARD_VARIANT_NAMES = {
  "brain",
  "diamond",
  "fire",
  "fish",
  "football",
  "money"
};

void settings() {
  size((int)DESIGN_WIDTH, (int)DESIGN_HEIGHT);
  pixelDensity(2);
}

void setup() {
  surface.setTitle("Z-Lab OCT Casino");
  surface.setResizable(true);
  
  bgImage = loadImage("backrgound.png");
  blueCard = loadImage("bluecard.png");
  redCard = loadImage("redcard.png");
  
  cardVariants = new PImage[CARD_VARIANT_NAMES.length];
  for (int i = 0; i < CARD_VARIANT_NAMES.length; i++) {
    cardVariants[i] = loadImage(CARD_VARIANT_NAMES[i] + ".png");
  }
  
  cardAssignments = new int[ROWS][COLS];
  initializeCardAssignments();
  
  monoFont = createFont("Courier", 12, true);
  textFont(monoFont);
  
  flipSound = new SoundFile(this, "cardflip.mp3");
  fanfareSound = new SoundFile(this, "fanfare.mp3");
  
  gameStartTime = millis();
}

void draw() {
  // Calculate viewport dimensions (split screen in half)
  viewWidth = width / 2.0f;
  viewHeight = height;
  
  // Create or resize scene buffer if needed
  int newSceneW = max(1, int(viewWidth));
  int newSceneH = max(1, int(viewHeight));
  if (scene == null || scene.width != newSceneW || scene.height != newSceneH) {
    scene = createGraphics(newSceneW, newSceneH);
  }
  
  updateLayoutMetrics();  // Keep every drawable element in sync with the window size
  
  // Calculate logical mouse coordinates (map to single screen)
  float logicalMX = mouseX % viewWidth;
  logicalMX = constrain(logicalMX, 0, viewWidth);
  float logicalMY = constrain(mouseY, 0, viewHeight);
  
  // Begin drawing to off-screen buffer
  scene.beginDraw();
  scene.image(bgImage, 0, 0, viewWidth, viewHeight);
  
  boolean isHoveringCard = false;
  int currentHoveredRow = -1;
  int currentHoveredCol = -1;
  
  if (mismatchStartTime >= 0 && flippedCards.size() == 2) {
    if (millis() - mismatchStartTime >= MISMATCH_DURATION) {
      FlippedCard card1 = flippedCards.get(0);
      FlippedCard card2 = flippedCards.get(1);
      
      flippingCards.add(new FlippingCard(card1.row, card1.col, millis(), true));
      playFlipSound();
      flippingCards.add(new FlippingCard(card2.row, card2.col, millis(), true));
      playFlipSound();
      
      flippedCards.clear();
      mismatchStartTime = -1;
    }
  }
  
  for (int row = 0; row < ROWS; row++) {
    for (int col = 0; col < COLS; col++) {
      float x = cardXForCol(col);
      float y = cardYForRow(row);
      boolean matched = isMatched(row, col);
      boolean currentlyFlipped = isCurrentlyFlipped(row, col);
      FlippingCard flippingCard = getFlippingCard(row, col);
      
      if (isMouseOverCard(logicalMX, logicalMY, x, y) &&
          !matched &&
          flippingCard == null &&
          !currentlyFlipped &&
          flippedCards.size() < 2) {
        isHoveringCard = true;
        currentHoveredRow = row;
        currentHoveredCol = col;
      }
      
      if (flippingCard != null) {
        float flipElapsed = millis() - flippingCard.startTime;
        float rawProgress = constrain(flipElapsed / FLIP_DURATION, 0, 1);
        float flipProgress = bezierEase(rawProgress);
        float scaleX;
        boolean showFlipped;
        
        if (flippingCard.isFlippingBack) {
          if (flipProgress < 0.5f) {
            scaleX = 1 - (flipProgress * 2);
            showFlipped = true;
          } else {
            scaleX = (flipProgress - 0.5f) * 2;
            showFlipped = false;
          }
        } else {
          if (flipProgress < 0.5f) {
            scaleX = 1 - (flipProgress * 2);
            showFlipped = false;
          } else {
            scaleX = (flipProgress - 0.5f) * 2;
            showFlipped = true;
          }
        }
        
        scene.pushMatrix();
        scene.translate(x + cardWidth / 2f, y + cardHeight / 2f);
        scene.scale(max(scaleX, 0.001f), 1);
        
        if (showFlipped) {
          int variantIndex = cardAssignments[row][col];
          scene.image(cardVariants[variantIndex], -cardWidth / 2f, -cardHeight / 2f, cardWidth, cardHeight);
        } else {
          boolean isBlue = (row + col) % 2 == 0;
          PImage cardImage = isBlue ? blueCard : redCard;
          scene.image(cardImage, -cardWidth / 2f, -cardHeight / 2f, cardWidth, cardHeight);
        }
        scene.popMatrix();
        
        if (flipProgress >= 1) {
          if (flippingCard.isFlippingBack) {
            removeFromFlipped(row, col);
          } else {
            int variantIndex = cardAssignments[row][col];
            flippedCards.add(new FlippedCard(row, col, variantIndex));
            totalFlips++;
            
            if (flippedCards.size() == 2) {
              FlippedCard card1 = flippedCards.get(0);
              FlippedCard card2 = flippedCards.get(1);
              if (card1.variantIndex == card2.variantIndex) {
                matchedCards.add(new CardPos(card1.row, card1.col));
                matchedCards.add(new CardPos(card2.row, card2.col));
                
                float card1X = cardCenterX(card1.col);
                float card1Y = cardCenterY(card1.row);
                float card2X = cardCenterX(card2.col);
                float card2Y = cardCenterY(card2.row);
                createConfetti(card1X, card1Y);
                createConfetti(card2X, card2Y);
                playFanfare();
                flippedCards.clear();
              } else {
                mismatchStartTime = millis();
              }
            }
          }
          flippingCards.remove(flippingCard);
        }
      } else if (matched) {
        int variantIndex = cardAssignments[row][col];
        scene.image(cardVariants[variantIndex], x, y, cardWidth, cardHeight);
        scene.noStroke();
        scene.fill(0, 128);
        scene.rect(x, y, cardWidth, cardHeight);
      } else if (currentlyFlipped) {
        int variantIndex = cardAssignments[row][col];
        scene.image(cardVariants[variantIndex], x, y, cardWidth, cardHeight);
      } else {
        boolean isBlue = (row + col) % 2 == 0;
        PImage cardImage = isBlue ? blueCard : redCard;
        scene.image(cardImage, x, y, cardWidth, cardHeight);
      }
    }
  }
  
  if (isHoveringCard && currentHoveredRow >= 0 && currentHoveredCol >= 0) {
    noCursor();
    boolean sameCard = (hoveredCardRow == currentHoveredRow && hoveredCardCol == currentHoveredCol);
    if (!wasHovering || !sameCard) {
      hoverStartTime = millis();
      hoveredCardRow = currentHoveredRow;
      hoveredCardCol = currentHoveredCol;
    }
    float elapsed = millis() - hoverStartTime;
    float fillProgress = constrain(elapsed / FILL_DURATION, 0, 1);
    float cardX = cardCenterX(currentHoveredCol);
    float cardY = cardCenterY(currentHoveredRow);
    
    scene.stroke(255, 200);
    scene.strokeWeight(2);
    scene.noFill();
    scene.ellipse(cardX, cardY, hoverCircleRadius * 2, hoverCircleRadius * 2);
    
    if (fillProgress > 0) {
      scene.noStroke();
      scene.fill(255, 150);
      float innerRadius = hoverCircleRadius * (1 - fillProgress);
      scene.ellipse(cardX, cardY, max(innerRadius * 2, 2), max(innerRadius * 2, 2));
    }
    
    if (fillProgress >= 1) {
      if (!isCurrentlyFlipped(hoveredCardRow, hoveredCardCol) &&
          getFlippingCard(hoveredCardRow, hoveredCardCol) == null &&
          !isMatched(hoveredCardRow, hoveredCardCol) &&
          flippedCards.size() < 2) {
        flippingCards.add(new FlippingCard(hoveredCardRow, hoveredCardCol, millis(), false));
        playFlipSound();
      }
      resetHover();
    } else {
      wasHovering = true;
    }
  } else {
    cursor();
    resetHover();
  }
  
  for (int i = confettiParticles.size() - 1; i >= 0; i--) {
    ConfettiParticle particle = confettiParticles.get(i);
    particle.update();
    particle.draw(scene);
    if (particle.isDead()) {
      confettiParticles.remove(i);
    }
  }
  
  // End drawing to off-screen buffer
  scene.endDraw();
  
  // Draw the scene twice for split-screen effect
  image(scene, 0, 0);
  image(scene, viewWidth, 0);
}

void updateLayoutMetrics() {
  float scaleX = viewWidth / DESIGN_WIDTH;
  float scaleY = viewHeight / DESIGN_HEIGHT;
  layoutScale = min(scaleX, scaleY);
  layoutScale = min(layoutScale, 1.0f); // Cap at 1x to prevent cards from growing too large
  
  cardWidth = BASE_CARD_WIDTH * layoutScale;
  cardHeight = BASE_CARD_HEIGHT * layoutScale;
  cardSpacingX = BASE_CARD_SPACING_X * layoutScale;
  cardSpacingY = BASE_CARD_SPACING_Y * layoutScale;
  hoverCircleRadius = BASE_HOVER_CIRCLE_RADIUS * layoutScale;
  
  paddingX = viewWidth * PADDING_X_RATIO;
  paddingY = viewHeight * PADDING_Y_RATIO;
  
  totalGridWidth = (cardWidth * COLS) + (cardSpacingX * (COLS - 1));
  totalGridHeight = (cardHeight * ROWS) + (cardSpacingY * (ROWS - 1));
  
  float availableWidth = max(viewWidth - paddingX * 2f, 0);
  float availableHeight = max(viewHeight - paddingY * 2f, 0);
  float offsetX = max(availableWidth - totalGridWidth, 0) / 2f;
  float offsetY = max(availableHeight - totalGridHeight, 0) / 2f;
  
  startX = paddingX + offsetX;
  startY = paddingY + offsetY;
}

float cardXForCol(int col) {
  return startX + col * (cardWidth + cardSpacingX);
}

float cardYForRow(int row) {
  return startY + row * (cardHeight + cardSpacingY);
}

float cardCenterX(int col) {
  return cardXForCol(col) + cardWidth / 2f;
}

float cardCenterY(int row) {
  return cardYForRow(row) + cardHeight / 2f;
}

void resetHover() {
  hoverStartTime = -1;
  hoveredCardRow = -1;
  hoveredCardCol = -1;
  wasHovering = false;
}

boolean isMouseOverCard(float mx, float my, float x, float y) {
  return mx >= x && mx <= x + cardWidth && my >= y && my <= y + cardHeight;
}

boolean isMatched(int row, int col) {
  for (CardPos pos : matchedCards) {
    if (pos.row == row && pos.col == col) {
      return true;
    }
  }
  return false;
}

boolean isCurrentlyFlipped(int row, int col) {
  for (FlippedCard card : flippedCards) {
    if (card.row == row && card.col == col) {
      return true;
    }
  }
  return false;
}

FlippingCard getFlippingCard(int row, int col) {
  for (FlippingCard card : flippingCards) {
    if (card.row == row && card.col == col) {
      return card;
    }
  }
  return null;
}

void removeFromFlipped(int row, int col) {
  for (int i = flippedCards.size() - 1; i >= 0; i--) {
    FlippedCard card = flippedCards.get(i);
    if (card.row == row && card.col == col) {
      flippedCards.remove(i);
      return;
    }
  }
}

void initializeCardAssignments() {
  IntList indices = new IntList();
  for (int i = 0; i < CARD_VARIANT_NAMES.length; i++) {
    indices.append(i);
    indices.append(i);
  }
  indices.shuffle();
  int idx = 0;
  for (int row = 0; row < ROWS; row++) {
    for (int col = 0; col < COLS; col++) {
      cardAssignments[row][col] = indices.get(idx++);
    }
  }
}

String formatTime(int milliseconds) {
  int totalSeconds = milliseconds / 1000;
  int minutes = totalSeconds / 60;
  int seconds = totalSeconds % 60;
  return nf(minutes, 2) + ":" + nf(seconds, 2);
}

float bezierEase(float t) {
  if (t < 0.5f) {
    return 4 * t * t * t;
  } else {
    float u = -2 * t + 2;
    return 1 - (u * u * u) / 2f;
  }
}

class CardPos {
  int row;
  int col;
  CardPos(int row, int col) {
    this.row = row;
    this.col = col;
  }
}

class FlippedCard {
  int row;
  int col;
  int variantIndex;
  FlippedCard(int row, int col, int variantIndex) {
    this.row = row;
    this.col = col;
    this.variantIndex = variantIndex;
  }
}

class FlippingCard {
  int row;
  int col;
  float startTime;
  boolean isFlippingBack;
  FlippingCard(int row, int col, float startTime, boolean isFlippingBack) {
    this.row = row;
    this.col = col;
    this.startTime = startTime;
    this.isFlippingBack = isFlippingBack;
  }
}

class ConfettiParticle {
  float x;
  float y;
  float vx;
  float vy;
  float rotation;
  float rotationSpeed;
  float size;
  float life = 1.0f;
  float decay;
  int c;
  ConfettiParticle(float x, float y) {
    this.x = x;
    this.y = y;
    this.vx = random(-3, 3);
    this.vy = random(-8, -2);
    this.rotation = random(TWO_PI);
    this.rotationSpeed = random(-0.1f, 0.1f);
    this.size = random(4, 8);
    this.decay = random(0.01f, 0.02f);
    this.c = color(random(255), random(255), random(255), 200);
  }
  void update() {
    x += vx;
    y += vy;
    vy += 0.3f;
    rotation += rotationSpeed;
    life -= decay;
  }
  void draw(PGraphics pg) {
    pg.pushMatrix();
    pg.translate(x, y);
    pg.rotate(rotation);
    pg.noStroke();
    pg.fill(red(c), green(c), blue(c), life * 200);
    pg.rect(-size / 2f, -size / 2f, size, size);
    pg.popMatrix();
  }
  boolean isDead() {
    return life <= 0 || y > viewHeight + 50;
  }
}

void createConfetti(float x, float y) {
  int particleCount = 30;
  for (int i = 0; i < particleCount; i++) {
    confettiParticles.add(new ConfettiParticle(x, y));
  }
}

void playFlipSound() {
  if (flipSound != null) {
    flipSound.stop();
    flipSound.play();
  }
}

void playFanfare() {
  if (fanfareSound != null) {
    fanfareSound.stop();
    fanfareSound.play();
  }
}
