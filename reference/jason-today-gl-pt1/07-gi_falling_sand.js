// @run
class Particle {
    constructor(color, empty = false) {
      this.color = color;
      this.empty = empty;
      this.maxSpeed = 8;
      this.acceleration = 0.4;
      this.velocity = 0;
      this.modified = false;
    }
  
    update() {
      if (this.maxSpeed === 0) {
        this.modified = false;
        return;
      }
      this.updateVelocity();
      this.modified = this.velocity !== 0;
    }
  
    updateVelocity() {
      let newVelocity = this.velocity + this.acceleration;
      if (Math.abs(newVelocity) > this.maxSpeed) {
        newVelocity = Math.sign(newVelocity) * this.maxSpeed;
      }
      this.velocity = newVelocity;
    }
  
    resetVelocity() {
      this.velocity = 0;
    }
  
    getUpdateCount() {
      const abs = Math.abs(this.velocity);
      const floored = Math.floor(abs);
      const mod = abs - floored;
      return floored + (Math.random() < mod ? 1 : 0);
    }
  }
  
  class Sand extends Particle {
    constructor(color) {
      super(color);
    }
  }
  
  class Solid extends Particle {
    constructor(color) {
      super(color);
      this.maxSpeed = 0;
    }
  
    update() {
      this.modified = true;
    }
  }
  
  class Empty extends Particle {
    constructor() {
      super({ r: 0, g: 0, b: 0 }, true);
      this.maxSpeed = 0;
    }
  
    update() {
      this.modified = true;
    }
  }
  
  class FallingSandSurface extends PaintableCanvas {
    constructor(options) {
      super(options);
      this.grid = new Array(this.width * this.height).fill(null).map(() => new Empty());
      this.tempGrid = new Array(this.width * this.height).fill(null).map(() => new Empty());
      this.colorGrid = new Array(this.width * this.height * 3).fill(0);
      this.modifiedIndices = new Set();
      this.cleared = false;
      this.rowCount = Math.floor(this.grid.length / this.width);
      requestAnimationFrame(() => this.updateSand());
      this.mode = Sand;
  
      document.querySelector("#sand-mode-button").addEventListener("click", () => {
        this.mode = Sand;
      });
  
      document.querySelector("#solid-mode-button").addEventListener("click", () => {
        debugger;
        this.mode = Solid;
      });
  
      document.querySelector("#empty-mode-button").addEventListener("click", () => {
        this.mode = Empty;
      });
    }
  
    onMouseMove(event) {
      if (!this.isDrawing) return false;
      this.mouseMoved = true;
      this.currentMousePosition = this.getMousePos(event);
      return true;
    }
  
    varyColor(color) {
      const hue = color.h;
      let saturation = color.s + Math.floor(Math.random() * 20) - 20;
      saturation = Math.max(0, Math.min(100, saturation));
      let lightness = color.l + Math.floor(Math.random() * 10) - 5;
      lightness = Math.max(0, Math.min(100, lightness));
      return this.hslToRgb(hue, saturation, lightness);
    }
  
    hslToRgb(h, s, l) {
      s /= 100;
      l /= 100;
      const k = n => (n + h / 30) % 12;
      const a = s * Math.min(l, 1 - l);
      const f = n =>
        l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
      return {
        r: Math.round(255 * f(0)),
        g: Math.round(255 * f(8)),
        b: Math.round(255 * f(4))
      };
    }
  
    rgbToHsl(rgb) {
      const r = rgb.r / 255;
      const g = rgb.g / 255;
      const b = rgb.b / 255;
      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      let h, s, l = (max + min) / 2;
  
      if (max === min) {
        h = s = 0; // achromatic
      } else {
        const d = max - min;
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        switch (max) {
          case r: h = (g - b) / d + (g < b ? 6 : 0); break;
          case g: h = (b - r) / d + 2; break;
          case b: h = (r - g) / d + 4; break;
        }
        h /= 6;
      }
  
      return { h: h * 360, s: s * 100, l: l * 100 };
    }
  
    drawSmoothLineFallback(from, to) {
      this.drawParticleLine(from, to, this.mode);
      this.updateTexture();
    }
  
    drawParticleLine(from, to, ParticleType) {
      const radius = this.RADIUS;
      const dx = to.x - from.x;
      const dy = to.y - from.y;
      const distance = Math.sqrt(dx * dx + dy * dy);
      const steps = Math.max(Math.abs(dx), Math.abs(dy));
  
      for (let i = 0; i <= steps; i++) {
        const t = (steps === 0) ? 0 : i / steps;
        const x = Math.round(from.x + dx * t);
        const y = Math.round(from.y + dy * t);
  
        for (let ry = -radius; ry <= radius; ry++) {
          for (let rx = -radius; rx <= radius; rx++) {
            if (rx * rx + ry * ry <= radius * radius) {
              const px = x + rx;
              const py = y + ry;
              if (px >= 0 && px < this.width && py >= 0 && py < this.height) {
                const index = py * this.width + px;
                const variedColor = this.varyColor(this.rgbToHsl(this.currentColor));
                this.setParticle(index, new ParticleType(variedColor));
              }
            }
          }
        }
      }
    }
  
    updateSand() {
      if (this.isDrawing) {
        this.doDraw();
      }
      
      this.cleared = false;
      this.modifiedIndices = new Set();
  
      for (let row = this.rowCount - 1; row >= 0; row--) {
        const rowOffset = row * this.width;
        const leftToRight = Math.random() > 0.5;
        for (let i = 0; i < this.width; i++) {
          const columnOffset = leftToRight ? i : -i - 1 + this.width;
          let index = rowOffset + columnOffset;
          const particle = this.grid[index];
  
          particle.update();
  
          if (!particle.modified) {
            continue;
          }
  
          this.modifiedIndices.add(index);
  
          for (let v = 0; v < particle.getUpdateCount(); v++) {
            const newIndex = this.updatePixel(index);
  
            if (newIndex !== index) {
              index = newIndex;
            } else {
              particle.resetVelocity();
              break;
            }
          }
        }
      }
  
      this.updateCanvasFromGrid();
      this.updateTexture();
      requestAnimationFrame(() => this.updateSand());
    }
  
    updatePixel(i) {
      const particle = this.grid[i];
      if (particle instanceof Empty) return i;
  
      const below = i + this.width;
      const belowLeft = below - 1;
      const belowRight = below + 1;
      const column = i % this.width;
  
      if (this.isEmpty(below)) {
        this.swap(i, below);
        return below;
      } else if (this.isEmpty(belowLeft) && belowLeft % this.width < column) {
        this.swap(i, belowLeft);
        return belowLeft;
      } else if (this.isEmpty(belowRight) && belowRight % this.width > column) {
        this.swap(i, belowRight);
        return belowRight;
      }
  
      return i;
    }
  
    swap(a, b) {
      if (this.grid[a] instanceof Empty && this.grid[b] instanceof Empty) {
        return;
      }
      [this.grid[a], this.grid[b]] = [this.grid[b], this.grid[a]];
      this.modifiedIndices.add(a);
      this.modifiedIndices.add(b);
    }
  
    setParticle(i, particle) {
      this.grid[i] = particle;
      this.modifiedIndices.add(i);
    }
  
    isEmpty(i) {
      return this.grid[i] instanceof Empty;
    }
  
    updateCanvasFromGrid() {
      const imageData = this.context.getImageData(0, 0, this.width, this.height);
      const data = imageData.data;
  
      this.modifiedIndices.forEach((i) => {
        const index = i * 4;
        const particle = this.grid[i];
        if (!(particle instanceof Empty)) {
          data[index] = particle.color.r;
          data[index + 1] = particle.color.g;
          data[index + 2] = particle.color.b;
          data[index + 3] = 255; // Full opacity
        } else {
          data[index + 3] = 0; // Set alpha to 0 for empty spaces
        }
      });
  
      this.context.putImageData(imageData, 0, 0);
    }
  
    clear() {
      super.clear();
      this.grid.fill(new Empty());
      this.tempGrid.fill(new Empty());
      this.colorGrid.fill(0);
      this.cleared = true;
    }
  
    setColor(r, g, b) {
      super.setColor(r, g, b);
    }
  
    needsUpdate() {
      return this.cleared || this.modifiedIndices.size > 0;
    }
  
    useFallbackCanvas() {
      return true;
    }
  }
  
  class FallingSandDrawing extends GI {
    createSurface(width, height, radius) {
      this.surface = new FallingSandSurface({ width, height, radius });
    }
  
    reset() {
      this.clear();
      let last = undefined;
      return new Promise((resolve) => {
        this.setHex("#f9a875");
        getFrame(() => this.draw(last, 0, false, resolve));
      }).then(() => new Promise((resolve) => {
        last = undefined;
        getFrame(() => {
          this.surface.mode = Solid;
          this.setHex("#000000");
          getFrame(() => this.draw(last, 0, true, resolve));
        });
      }))
        .then(() => {
          this.renderPass();
          getFrame(() => this.setHex("#fff6d3"));
          this.surface.mode = Sand;
        });
    }
  }
  
  const fallingSand = new FallingSandDrawing({ id: "falling-sand-canvas", width: 300, height: 300 });