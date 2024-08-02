// @run
const raymarchSlider = document.querySelector("#raymarch-steps-slider");
const showNoiseCheckbox = document.querySelector("#noise-raymarch");
const accumRadianceCheckbox = document.querySelector("#accumulate-radiance");

class NaiveRaymarchGi extends Drawing {
  innerInitialize() {
    const {plane: giPlane, render: giRender, renderTargets: giRenderTargets} = this.initThreeJS({
      uniforms: {
        sceneTexture: {value: this.surface.texture},
        rayCount: {value: 8},
        maxSteps: {value: raymarchSlider.value},
        showNoise: { value: showNoiseCheckbox.checked },
        accumRadiance: { value: accumRadianceCheckbox.checked },
        size: {value: new THREE.Vector2(this.width, this.height)},
      },
      fragmentShader: `
uniform sampler2D sceneTexture;
uniform int rayCount;
uniform int maxSteps;
uniform bool showNoise;
uniform bool accumRadiance;
uniform vec2 size;
    
in vec2 vUv;

const float PI = 3.14159265;
const float TAU = 2.0 * PI;

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec4 raymarch() {
  vec4 light = texture(sceneTexture, vUv);

  if (light.a > 0.1) {
    return light;
  }
  
  float oneOverRayCount = 1.0 / float(rayCount);
  float tauOverRayCount = TAU * oneOverRayCount;
  
  // Different noise every pixel
  float noise = showNoise ? rand(vUv) : 0.1;
  
  vec4 radiance = vec4(0.0);
  
  // Shoot rays in "rayCount" directions, equally spaced, with some randomness.
  for(int i = 0; i < rayCount; i++) {
      float angle = tauOverRayCount + (float(i) + noise);
      vec2 rayDirectionUv = vec2(cos(angle), -sin(angle)) / size;
      vec2 traveled = vec2(0.0);
      
      int initialStep = accumRadiance ? 0 : max(0, maxSteps - 1);
      for (int step = initialStep; step < maxSteps; step++) {
          // Go the direction we're traveling (with noise)
          vec2 sampleUv = vUv + rayDirectionUv * float(step);
      
          if (sampleUv.x < 0.0 || sampleUv.x > 1.0 || sampleUv.y < 0.0 || sampleUv.y > 1.0) {
            break;
          }
          
          vec4 sampleLight = texture(sceneTexture, sampleUv);
          if (sampleLight.a > 0.5) {
            radiance += sampleLight;
            break;
          }
      }      
  }
  
  // Average radiance
  return radiance * oneOverRayCount;
}

void main() {
    // Bring up all the values to have an alpha of 1.0.
    gl_FragColor = vec4(raymarch().rgb, 1.0);
}`,
});

    this.giPlane = giPlane;
    this.giRender = giRender;
    this.giRenderTargets = giRenderTargets;
  }

  raymarchPass(inputTexture) {
    this.giPlane.material.uniforms.sceneTexture.value = inputTexture;
    this.renderer.setRenderTarget(null);
    this.giRender();
  }

  clear() {
    if (this.initialized) {
      this.giRenderTargets.forEach((target) => {
        this.renderer.setRenderTarget(target);
        this.renderer.clearColor();
      });
    }
    super.clear();
  }

  renderPass() {
    let out = this.drawPass();
    this.raymarchPass(out);
  }

  load() {
    super.load();
    raymarchSlider.addEventListener("input", () => {
      this.giPlane.material.uniforms.maxSteps.value = raymarchSlider.value;
      this.renderPass();
    });
    showNoiseCheckbox.addEventListener("input", () => {
      this.giPlane.material.uniforms.showNoise.value = showNoiseCheckbox.checked;
      this.renderPass();
    });
    accumRadianceCheckbox.addEventListener("input", () => {
      this.giPlane.material.uniforms.accumRadiance.value = accumRadianceCheckbox.checked;
      this.renderPass();
    });
    getFrame(() => this.reset());
  }

  draw(last, t, isShadow, resolve) {
    if (t >= 10.0) {
      resolve();
      return;
    }

    const angle = (t * 0.05) * Math.PI * 2;

    const {x, y} = isShadow
      ? {
        x: 90 + 12 * t,
        y: 200 + 1 * t,
      }
      : {
        x: 100 + 100 * Math.sin(angle + 0.25) * Math.cos(angle * 0.15),
        y: 50 + 100 * Math.sin(angle * 0.7)
      };

    last ??= {x, y};

    this.surface.drawSmoothLine(last, {x, y});
    last = {x, y};

    const step = instantMode ? 5.0 : (isShadow ? 0.5 : 0.3);
    getFrame(() => this.draw(last, t + step, isShadow, resolve));
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
        this.setHex("#000000");
        getFrame(() => this.draw(last, 0, true, resolve));
      });
    }))
      .then(() => {
        this.renderPass();
        getFrame(() => this.setHex("#fff6d3"));
      });
  }
}

const raymarchSurface = new NaiveRaymarchGi({ id: "naive-raymarch", width: 300, height: 300 });