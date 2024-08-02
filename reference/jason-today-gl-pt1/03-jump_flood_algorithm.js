// @run
const jfaSlider = document.querySelector("#jfa-slider");
jfaSlider.value = window.mdxishState.jfaSlider ?? 5;

class JFA extends Drawing {
  innerInitialize() {
    this.passes = Math.ceil(Math.log2(Math.max(this.width, this.height)));

    const {plane: seedPlane, render: seedRender, renderTargets: seedRenderTargets} = this.initThreeJS({
      uniforms: {
        surfaceTexture: {value: this.surface.texture},
      },
      fragmentShader: `
        uniform sampler2D surfaceTexture;
        
        in vec2 vUv;
        
        void main() {
          float alpha = texture(surfaceTexture, vUv).a;
          gl_FragColor = vec4(vUv * alpha, 0.0, 1.0);
        }`,
    });
    
    const {plane: jfaPlane, render: jfaRender, renderTargets: jfaRenderTargets} = this.initThreeJS({
      uniforms: {
        inputTexture: {value: this.surface.texture},
        oneOverSize: {value: new THREE.Vector2(1.0 / this.width, 1.0 / this.height)},
        uOffset: {value: Math.pow(2, this.passes - 1)},
        skip: {value: true},
      },
      fragmentShader: `
uniform vec2 oneOverSize;
uniform sampler2D inputTexture;
uniform float uOffset;
uniform bool skip;

in vec2 vUv;

void main() {
  if (skip) {
    gl_FragColor = vec4(vUv, 0.0, 1.0);
  } else {
    vec4 nearestSeed = vec4(-2.0);
    float nearestDist = 999999.9;
    
    for (float y = -1.0; y <= 1.0; y += 1.0) {
      for (float x = -1.0; x <= 1.0; x += 1.0) {
        vec2 sampleUV = vUv + vec2(x, y) * uOffset * oneOverSize;
        
        // Check if the sample is within bounds
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) { continue; }
        
          vec4 sampleValue = texture(inputTexture, sampleUV);
          vec2 sampleSeed = sampleValue.xy;
          
          if (sampleSeed.x != 0.0 || sampleSeed.y != 0.0) {
            vec2 diff = sampleSeed - vUv;
            float dist = dot(diff, diff);
            if (dist < nearestDist) {
              nearestDist = dist;
              nearestSeed = sampleValue;
            }
          }
      }
    }
    
    gl_FragColor = nearestSeed;
  }
}`
    });

    this.seedPlane = seedPlane;
    this.seedRender = seedRender;
    this.seedRenderTargets = seedRenderTargets;

    this.jfaPlane = jfaPlane;
    this.jfaRender = jfaRender;
    this.jfaRenderTargets = jfaRenderTargets;
  }

  seedPass(inputTexture) {
    this.seedPlane.material.uniforms.surfaceTexture.value = inputTexture;
    this.renderer.setRenderTarget(this.seedRenderTargets[0]);
    this.seedRender();
    return this.seedRenderTargets[0].texture;
  }

  jfaPassesCount() {
    return parseInt(jfaSlider.value);
  }

  jfaPass(inputTexture) {
    let currentInput = inputTexture;
    let [renderA, renderB] = this.jfaRenderTargets;
    let currentOutput = renderA;
    this.jfaPlane.material.uniforms.skip.value = true;
    let passes = this.jfaPassesCount();

    for (let i = 0; i < passes || (passes === 0 && i === 0); i++) {

      this.jfaPlane.material.uniforms.skip.value = passes === 0;
      this.jfaPlane.material.uniforms.inputTexture.value = currentInput;
      // This intentionally uses `this.passes` which is the true value
      // In order to properly show stages using the JFA slider.
      this.jfaPlane.material.uniforms.uOffset.value = Math.pow(2, this.passes - i - 1);

      this.renderer.setRenderTarget(currentOutput);
      this.jfaRender();

      currentInput = currentOutput.texture;
      currentOutput = (currentOutput === renderA) ? renderB : renderA;
    }

    return currentInput;
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

  clear() {
    if (this.initialized) {
      this.seedRenderTargets.concat(this.jfaRenderTargets).forEach((target) => {
        this.renderer.setRenderTarget(target);
        this.renderer.clearColor();
      });
    }
    super.clear();
  }

  load() {
    super.load();
    jfaSlider.addEventListener("input", () => {
      this.renderPass();
      // Save the value
      window.mdxishState.jfaSlider = jfaSlider.value;
    });
    getFrame(() => this.reset());
  }

  renderPass() {
    let out = this.drawPass();
    out = this.seedPass(out);
    out = this.jfaPass(out);
    this.renderer.setRenderTarget(null);
    this.jfaRender();
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

const jfa = new JFA({ id: "jfa", width: 300, height: 300 });