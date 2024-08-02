// @run
class BaseSurface {
    constructor({ id, width, height, radius = 5 }) {
      // Create PaintableCanvas instances
      this.createSurface(width, height, radius);
      this.width = width;
      this.height = height;
      this.id = id;
      this.initialized = false;
      this.initialize();
    }
    
    createSurface(width, height, radius) {
      this.surface = new PaintableCanvas({ width, height, radius });
    }
  
    initialize() {
      // Child class should fill this out
    }
  
    load() {
      // Child class should fill this out
    }
  
    clear() {
      // Child class should fill this out
    }
  
    renderPass() {
      // Child class should fill this out
    }
  
    reset() {
      this.clear();
      this.setHex("#fff6d3");
      new Promise((resolve) => {
        getFrame(() => this.draw(0.0, null, resolve));
      });
    }
  
    draw(t, last, resolve) {
      if (t >= 10.0) {
        resolve();
        return;
      }
  
      const angle = (t * 0.05) * Math.PI * 2;
  
      const {x, y} = {
        x: 100 + 100 * Math.sin(angle + 0.25) * Math.cos(angle * 0.15),
        y: 50 + 100 * Math.sin(angle * 0.7)
      };
  
      last ??= {x, y};
  
      this.surface.drawSmoothLine(last, {x, y});
      last = {x, y};
  
      const step = instantMode ? 5.0 : 0.2;
      getFrame(() => this.draw(t + step, last, resolve));
    }
  
    buildCanvas() {
      return intializeCanvas({
        id: this.id,
        canvas: this.canvas,
        onSetColor: ({r, g, b}) => {
          this.surface.currentColor = {r, g, b};
          this.plane.material.uniforms.color.value = new THREE.Color(
            this.surface.currentColor.r / 255.0,
            this.surface.currentColor.g / 255.0,
            this.surface.currentColor.b / 255.0
          );
        },
        startDrawing: (e) => this.surface.startDrawing(e),
        onMouseMove: (e) => this.surface.onMouseMove(e),
        stopDrawing: (e) => this.surface.stopDrawing(e),
        clear: () => this.clear(),
        reset: () => this.reset(),
        ...this.canvasModifications()
      });
    }
  
    canvasModifications() {
      return {}
    }
  
    observe() {
      const observer = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting === true) {
          this.load();
          observer.disconnect(this.container);
        }
      });
  
      observer.observe(this.container);
    }
  
    initThreeJS({ uniforms, fragmentShader, renderTargetOverrides }) {
      return threeJSInit(this.width, this.height, {
        uniforms,
        fragmentShader,
        vertexShader,
        transparent: !this.surface.useFallbackCanvas(),
      }, this.renderer, renderTargetOverrides ?? {}, this.surface)
    }
  }
  
  class Drawing extends BaseSurface {
    initializeSmoothSurface() {
      const props = this.initThreeJS({
        uniforms: {
          inputTexture: { value: this.surface.texture },
          color: {value: new THREE.Color(1, 1, 1)},
          from: {value: new THREE.Vector2(0, 0)},
          to: {value: new THREE.Vector2(0, 0)},
          radiusSquared: {value: Math.pow(this.surface.RADIUS, 2.0)},
          resolution: {value: new THREE.Vector2(this.width, this.height)},
          drawing: { value: false },
        },
        fragmentShader: `
  uniform sampler2D inputTexture;
  uniform vec3 color;
  uniform vec2 from;
  uniform vec2 to;
  uniform float radiusSquared;
  uniform vec2 resolution;
  uniform bool drawing;
  varying vec2 vUv;
  
  float sdfLineSquared(vec2 p, vec2 from, vec2 to) {
  vec2 toStart = p - from;
  vec2 line = to - from;
  float lineLengthSquared = dot(line, line);
  float t = clamp(dot(toStart, line) / lineLengthSquared, 0.0, 1.0);
  vec2 closestVector = toStart - line * t;
  return dot(closestVector, closestVector);
  }
  
  void main() {
  vec4 current = texture(inputTexture, vUv);
  if (drawing) {
    vec2 coord = vUv * resolution;
    if (sdfLineSquared(coord, from, to) <= radiusSquared) {
      current = vec4(color, 1.0);
    }
  }
  gl_FragColor = current;
  }`,
      });
  
      if (this.surface.useFallbackCanvas()) {
        this.surface.drawSmoothLine = (from, to) => {
          this.surface.drawSmoothLineFallback(from, to);
        }
        this.surface.onUpdateTextures = () => {
          this.renderPass();
        }
      } else {
        this.surface.drawSmoothLine = (from, to) => {
          props.plane.material.uniforms.drawing.value = true;
          props.plane.material.uniforms.from.value = { 
            ...from, y: this.height - from.y 
          };
          props.plane.material.uniforms.to.value = {
            ...to, y: this.height - to.y
          };
          this.renderPass();
          props.plane.material.uniforms.drawing.value = false;
        }
      }
  
      return props;
    }
  
    clear() {
      if (this.surface.useFallbackCanvas()) {
        this.surface.clear();
        return;
      }
      if (this.initialized) {
        this.renderTargets.forEach((target) => {
          this.renderer.setRenderTarget(target);
          this.renderer.clearColor();
        });
      }
      this.renderer.setRenderTarget(null);
      this.renderer.clearColor();
    }
  
    initialize() {
      const {
        plane, canvas, render, renderer, renderTargets
      } = this.initializeSmoothSurface();
      this.canvas = canvas;
      this.plane = plane;
      this.render = render;
      this.renderer = renderer;
      this.renderTargets = renderTargets;
      const { container, setHex } = this.buildCanvas();
      this.container = container;
      this.setHex = setHex;
      this.renderIndex = 0;
  
      this.innerInitialize();
      
      this.observe();
    }
  
    innerInitialize() {
  
    }
  
    load() {
      this.reset();
      this.initialized = true;
    }
  
    drawPass() {
      if (this.surface.useFallbackCanvas()) {
        return this.surface.texture;
      } else {
        this.plane.material.uniforms.inputTexture.value = this.renderTargets[this.renderIndex].texture;
        this.renderIndex = 1 - this.renderIndex;
        this.renderer.setRenderTarget(this.renderTargets[this.renderIndex]);
        this.render();
        return this.renderTargets[this.renderIndex].texture;
      }
    }
  
    renderPass() {
      this.drawPass()
      this.renderer.setRenderTarget(null);
      this.render();
    }
  }
  
  const simpleSurface = new Drawing({ id: "simpleSurface", width: 300, height: 300 });