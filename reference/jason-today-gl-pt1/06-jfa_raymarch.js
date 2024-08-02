// @run

class GI extends DistanceField {
    innerInitialize() {
      super.innerInitialize();
      this.toggle = document.querySelector("#noise-toggle");
      this.grainToggle = document.querySelector("#grain-toggle");
      this.temporalToggle = document.querySelector("#temporal-toggle");
      this.sunToggle = document.querySelector("#sun-toggle");
      this.sunAngleSlider = document.querySelector("#sun-angle-slider");
      this.maxStepsSlider = document.querySelector("#max-steps-slider");
  
      this.showNoise = true;
      this.showGrain = true;
      this.useTemporalAccum = false;
      this.enableSun = true;
      this.activelyDrawing = false;
      this.accumAmt = 10.0;
      this.maxSteps = this.maxStepsSlider.value;
  
      const {plane: giPlane, render: giRender, renderTargets: giRenderTargets} = this.initThreeJS({
        uniforms: {
          sceneTexture: {value: this.surface.texture},
          distanceTexture: {value: null},
          lastFrameTexture: {value: null},
          oneOverSize: {value: new THREE.Vector2(1.0 / this.width, 1.0 / this.height)},
          rayCount: {value: rayCount},
          showNoise: { value: this.showNoise },
          showGrain: { value: this.showGrain },
          useTemporalAccum: { value: this.useTemporalAccum },
          enableSun: { value: this.enableSun },
          time: { value: 0.0 },
          // We're using TAU - 2.0 (radians) here b/c it feels like a reasonable spot in the sky
          sunAngle: { value: this.sunAngleSlider.value },
          maxSteps: { value: this.maxSteps }
        },
        fragmentShader: `
  uniform int rayCount;
  uniform float time;
  uniform float sunAngle;
  uniform bool showNoise;
  uniform bool showGrain;
  uniform bool useTemporalAccum;
  uniform bool enableSun;
  uniform vec2 oneOverSize;
  uniform int maxSteps;
  
  uniform sampler2D sceneTexture;
  uniform sampler2D lastFrameTexture;
  uniform sampler2D distanceTexture;
  
  in vec2 vUv;
  
  const float PI = 3.14159265;
  const float TAU = 2.0 * PI;
  const float ONE_OVER_TAU = 1.0 / TAU;
  const float PAD_ANGLE = 0.01;
  const float EPS = 0.001f;
  
  const vec3 skyColor = vec3(0.02, 0.08, 0.2);
  const vec3 sunColor = vec3(0.95, 0.95, 0.9);
  const float goldenAngle = PI * 0.7639320225;
  
  // Popular rand function
  float rand(vec2 co) {
      return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
  }
  
  vec3 sunAndSky(float rayAngle) {
      // Get the sun / ray relative angle
      float angleToSun = mod(rayAngle - sunAngle, TAU);
      
      // Sun falloff based on the angle
      float sunIntensity = smoothstep(1.0, 0.0, angleToSun);
      
      // And that's our sky radiance
      return sunColor * sunIntensity + skyColor;
  }
  
  bool outOfBounds(vec2 uv) {
    return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
  }
  
  void main() {
      vec2 uv = vUv;
      
      vec4 light = texture(sceneTexture, uv);
  
      vec4 radiance = vec4(0.0);
  
      float oneOverRayCount = 1.0 / float(rayCount);
      float angleStepSize = TAU * oneOverRayCount;
      
      float coef = useTemporalAccum ? time : 0.0;
      float offset = showNoise ? rand(uv + coef) : 0.0;
      float rayAngleStepSize = showGrain ? angleStepSize + offset * TAU : angleStepSize;
      
      // Not light source or occluder
      if (light.a < 0.1) {    
          // Shoot rays in "rayCount" directions, equally spaced, with some randomness.
          for(int i = 0; i < rayCount; i++) {
              float angle = rayAngleStepSize * (float(i) + offset) + sunAngle;
              vec2 rayDirection = vec2(cos(angle), -sin(angle));
              
              vec2 sampleUv = uv;
              vec4 radDelta = vec4(0.0);
              bool hitSurface = false;
              
              // We tested uv already (we know we aren't an object), so skip step 0.
              for (int step = 1; step < maxSteps; step++) {
                  // How far away is the nearest object?
                  float dist = texture(distanceTexture, sampleUv).r;
                  
                  // Go the direction we're traveling (with noise)
                  sampleUv += rayDirection * dist;
                  
                  if (outOfBounds(sampleUv)) break;
                  
                  if (dist < EPS) {
                    vec4 sampleColor = texture(sceneTexture, sampleUv);
                    radDelta += sampleColor;
                    hitSurface = true;
                    break;
                  }
              }
  
              // If we didn't find an object, add some sky + sun color
              if (!hitSurface && enableSun) {
                radDelta += vec4(sunAndSky(angle), 1.0);
              }
  
              // Accumulate total radiance
              radiance += radDelta;
          }
      } else if (length(light.rgb) >= 0.1) {
          radiance = light;
      }
  
  
      // Bring up all the values to have an alpha of 1.0.
      vec4 finalRadiance = vec4(max(light, radiance * oneOverRayCount).rgb, 1.0);
      if (useTemporalAccum && time > 0.0) {
        vec4 prevRadiance = texture(lastFrameTexture, vUv);
        gl_FragColor = mix(finalRadiance, prevRadiance, 0.9);
      } else {
        gl_FragColor = finalRadiance;
      }
  }`,
      });
  
      this.lastFrame = null;
      this.prev = 0;
      this.drawingExample = false;
  
      this.giPlane = giPlane;
      this.giRender = giRender;
      this.giRenderTargets = giRenderTargets;
    }
  
    giPass(distanceFieldTexture) {
      this.giPlane.material.uniforms.distanceTexture.value = distanceFieldTexture;
      this.giPlane.material.uniforms.sceneTexture.value = this.surface.texture;
      if (this.useTemporalAccum && !this.surface.isDrawing && !this.drawingExample) {
        this.giPlane.material.uniforms.lastFrameTexture.value = this.lastFrame ?? this.surface.texture;
        const target = this.prev ? this.giRenderTargets[0] : this.giRenderTargets[1];
        this.prev = (this.prev + 1) % 2;
        this.renderer.setRenderTarget(target);
        this.giRender();
        this.lastFrame = target.texture;
        this.giPlane.material.uniforms.time.value += 1.0;
      } else {
        this.giPlane.material.uniforms.time.value = 0.0;
        this.lastFrame = null;
      }
      this.renderer.setRenderTarget(null);
      this.giRender();
      return this.lastFrame;
    }
  
    renderPass() {
      const isDone = this.giPlane.material.uniforms.time.value >= this.accumAmt;
      if (isDone || this.surface.isDrawing || this.drawingExample) {
        this.giPlane.material.uniforms.time.value = 0;
      }
  
      let drawPassTexture = this.drawPass();
      let out = this.seedPass(drawPassTexture);
      out = this.jfaPass(out);
      out = this.dfPass(out);
      this.renderer.setRenderTarget(null);
      this.surface.texture = drawPassTexture;
      out = this.giPass(out);
    }
  
    animate() {
      const isDone = this.giPlane.material.uniforms.time.value >= this.accumAmt;
      this.renderPass();
      if (isDone || this.surface.isDrawing || this.drawingExample || !this.useTemporalAccum) {
        return;
      }
      getFrame(() => this.animate());
    }
  
    toggleSun() {
      this.sunToggle.checked = !this.sunToggle.checked
      this.enableSun = !this.enableSun;
      this.giPlane.material.uniforms.enableSun.value = this.enableSun;
      this.animate();
    }
  
    clear() {
      this.lastFrame = null;
      if (this.initialized) {
        this.giRenderTargets.forEach((target) => {
          this.renderer.setRenderTarget(target);
          this.renderer.clearColor();
        });
      }
      super.clear();
    }
  
    reset() {
      this.drawingExample = true;
      return super.reset().then(() => {
        this.drawingExample = false;
        this.animate();
      })
    }
  
    canvasModifications() {
      return {
        startDrawing: (e) => {
          if (this.drawingExample) {
            return;
          }
          this.lastFrame = null;
          this.giPlane.material.uniforms.time.value = 0.0;
          this.surface.startDrawing(e)
        },
        onMouseMove: (e) => {
          if (this.surface.onMouseMove(e)) {
            this.giPlane.material.uniforms.time.value = 0.0;
          }
        },
        stopDrawing: (e) => {
          if (this.surface.stopDrawing(e)) {
            this.giPlane.material.uniforms.time.value = 0;
            this.animate();
          }
        },
        ...(
          this.id === "final" ? {
            toggleSun: () => this.toggleSun()
          } : {}
        )
      }
    }
  
    stopSliding() {
      this.drawingExample = false;
      this.animate();
    }
  
    loadAfterReset() {
      this.initialized = true;
  
      this.toggle.addEventListener("input", () => {
        this.showNoise = this.toggle.checked;
        this.giPlane.material.uniforms.showNoise.value = this.showNoise;
        this.animate();
      });
  
      this.grainToggle.addEventListener("input", () => {
        this.showGrain = this.grainToggle.checked;
        this.giPlane.material.uniforms.showGrain.value = this.showGrain;
        this.animate();
      });
  
      this.temporalToggle.addEventListener("input", () => {
        this.useTemporalAccum = this.temporalToggle.checked;
        this.giPlane.material.uniforms.useTemporalAccum.value = this.useTemporalAccum;
        this.animate();
      });
  
      this.sunToggle.addEventListener("input", () => {
        this.giPlane.material.uniforms.time.value = 0;
        this.enableSun = this.sunToggle.checked;
        this.giPlane.material.uniforms.enableSun.value = this.enableSun;
        this.animate();
      });
  
      Object.entries({
        "mousedown": () => { this.drawingExample = true; },
        "touchstart": () => { this.drawingExample = true; },
        "touchend": () => { this.stopSliding() },
        "touchcancel": () => { this.stopSliding() },
        "mouseup": () => { this.stopSliding() },
      }).forEach(([event, fn]) => {
        this.sunAngleSlider.addEventListener(event, fn);
        this.maxStepsSlider.addEventListener(event, fn);
      });
  
      this.sunAngleSlider.addEventListener("input", () => {
        this.giPlane.material.uniforms.sunAngle.value = this.sunAngleSlider.value;
        this.renderPass();
        window.mdxishState.sunAngleSlider = this.sunAngleSlider.value;
      });
  
      this.maxStepsSlider.addEventListener("input", () => {
        this.giPlane.material.uniforms.maxSteps.value = this.maxStepsSlider.value;
        this.renderPass();
        window.mdxishState.maxSteps = this.maxSteps.value;
      });
    }
  
    load() {
      this.reset().then(() => {
        this.loadAfterReset();
      });
    }
  }
  
  const gi = new GI({ id: "gi", width: 300, height: 400 });
  
  let finalWidth = 300;
  let giFinal = new GI({ id: "final", width: finalWidth, height: 400 });
  
  if (!isMobile) {
    let performanceMode = true;
    let perfDiv = document.querySelector("#performance-issues");
    perfDiv.textContent = "Want a bigger canvas?";
    perfDiv.addEventListener("click", () => {
      document.querySelector("#final").innerHtml = "";
      performanceMode = !performanceMode;
      finalWidth = performanceMode ? 300 : document.querySelector("#content").clientWidth - 64;
      perfDiv.textContent = performanceMode ? "Want a bigger canvas?" : "Performance issues?";
      giFinal = new GI({id: "final", width: finalWidth, height: 400});
    });
  }