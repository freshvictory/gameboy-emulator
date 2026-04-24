/**
 * @typedef {{
 *   memory: WebAssembly.Memory;
 *   getDebugStatePointer(): number;
 *   getCartridgeBufferPointer(): number;
 *   getFramePointer(): number;
 *   getBackgroundPixelsPointer(): number;
 *   start(length: number): void;
 *   step(): number;
 *   frame(): void;
 *   scanline(): void;
 *   updateDebugState(): void;
 *   updateGpuDebug(): void;
 * }} Library
 */

export class Gameboy {
  /**
   * @param {WebAssembly.Exports & Library} library
   * @param {HTMLCanvasElement | OffscreenCanvas} canvas
   * @param {(debugInfo: DebugInfo["cpu"]) => void} debugCpuCallback
   * @param {(debugInfo: DebugInfo["gpu"]) => void} debugGpuCallback
   * @param {HTMLCanvasElement | OffscreenCanvas | null} backgroundCanvas
   */
  constructor(
    library,
    canvas,
    debugCpuCallback,
    debugGpuCallback,
    backgroundCanvas = null,
  ) {
    this.context = canvas.getContext("2d");
    if (!this.context) throw new Error("Could not get canvas 2d context");

    this.context.imageSmoothingEnabled = false;

    this.debugCpuCallback = debugCpuCallback;
    this.debugGpuCallback = debugGpuCallback;

    this.library = library;
    this.memory = library.memory;
    const debugPointer = library.getDebugStatePointer();
    this.debugView = new DataView(this.memory.buffer, debugPointer);

    const cartridgePointer = library.getCartridgeBufferPointer();
    this.cartridgeBuffer = new Uint8Array(
      this.memory.buffer,
      cartridgePointer,
      8 * 1024 * 1024,
    );

    const framePointer = library.getFramePointer();
    this.frameBuffer = new Uint8ClampedArray(
      this.memory.buffer,
      framePointer,
      160 * 144 * 4,
    );

    const backgroundPixelsPointer = library.getBackgroundPixelsPointer();
    this.backgroundPixels = new Uint8ClampedArray(
      this.memory.buffer,
      backgroundPixelsPointer,
      256 * 256 * 4,
    );
    this.backgroundContext = backgroundCanvas?.getContext("2d");

    this.animationId = -1;
  }

  /** @param {File | ArrayBuffer} file */
  async boot(file) {
    const data = file instanceof File ? await file.arrayBuffer() : file;
    const length = await this.#loadCartridge(data);
    this.context.clearRect(
      0,
      0,
      this.context.canvas.width,
      this.context.canvas.height,
    );
    this.library.start(length);
  }

  play() {
    cancelAnimationFrame(this.animationId);
    const frame = () => {
      this.frame();
      this.animationId = requestAnimationFrame(frame);
    };
    this.animationId = requestAnimationFrame(frame);
  }

  pause() {
    cancelAnimationFrame(this.animationId);
  }

  step() {
    this.library.step();
    this.debugAll();
  }

  frame() {
    this.library.frame();
    this.drawFrame();
    this.debugGpu();
  }

  scanline() {
    this.library.scanline();
    this.drawFrame();
    this.debugGpu();
  }

  drawFrame() {
    const imageData = new ImageData(this.frameBuffer, 160);
    this.context.putImageData(imageData, 0, 0);
  }

  /** @param {ArrayBuffer} data */
  async #loadCartridge(data) {
    this.cartridgeBuffer.set(new Uint8Array(data));

    return data.byteLength;
  }

  debugAll() {
    const info = this.debugInfo();
    this.debugCpuCallback(info.cpu);
    this.debugGpuCallback(info.gpu);
    this.debugBackground(info.gpu.background);
  }

  debugGpu() {
    this.library.updateGpuDebug();
    const info = this.gpuDebugInfo();
    this.debugGpuCallback(info);
    this.debugBackground(info.background);
  }

  /**
   * @param {DebugInfo["gpu"]["background"]} background
   */
  debugBackground(background) {
    if (!this.backgroundContext) return;

    this.backgroundContext.clearRect(0, 0, 255, 255);

    const imageData = new ImageData(this.backgroundPixels, 256);
    this.backgroundContext.putImageData(imageData, 0, 0);
    this.backgroundContext.strokeStyle = `rgb(255 0 0)`;
    this.backgroundContext.strokeRect(
      background.scrollX,
      background.scrollY,
      160,
      144,
    );
  }

  debugInfo() {
    this.library.updateDebugState();

    const stackPointer = this.debugView.getUint16(0, true);
    const programCounter = this.debugView.getUint16(2, true);
    const flags = this.debugView.getUint8(11);
    const enabledInterrupts = this.debugView.getUint8(17);
    const activeInterrupts = this.debugView.getUint8(18);
    return {
      cpu: {
        registers: {
          a: this.debugView.getUint8(4),
          b: this.debugView.getUint8(5),
          c: this.debugView.getUint8(6),
          d: this.debugView.getUint8(7),
          e: this.debugView.getUint8(8),
          h: this.debugView.getUint8(9),
          l: this.debugView.getUint8(10),
          stackPointer,
        },
        programCounter,
        flags: {
          carried: (flags & 0x10) !== 0,
          halfCarried: (flags & 0x20) !== 0,
          subtracted: (flags & 0x40) !== 0,
          wasZero: (flags & 0x80) !== 0,
        },
      },
      interrupts: {
        active: {
          vBlank: (activeInterrupts & 0b1) !== 0,
          lcd: (activeInterrupts & 0b10) !== 0,
          timer: (activeInterrupts & 0b100) !== 0,
          serial: (activeInterrupts & 0b1000) !== 0,
          joypad: (activeInterrupts & 0b10000) !== 0,
        },
        enabled: {
          vBlank: (enabledInterrupts & 0b1) !== 0,
          lcd: (enabledInterrupts & 0b10) !== 0,
          timer: (enabledInterrupts & 0b100) !== 0,
          serial: (enabledInterrupts & 0b1000) !== 0,
          joypad: (enabledInterrupts & 0b10000) !== 0,
        },
      },
      gpu: this.gpuDebugInfo(),
    };
  }

  gpuDebugInfo() {
    const gpuMode = this.debugView.getUint8(19);
    return {
      mode:
        gpuMode === 0
          ? "horizontal-blank"
          : gpuMode === 1
            ? "vertical-blank"
            : gpuMode === 2
              ? "drawing"
              : "finding-objects",
      scanline: this.debugView.getUint8(20),
      dots: this.debugView.getUint32(21),
      background: {
        scrollX: this.debugView.getUint8(25),
        scrollY: this.debugView.getUint8(26),
      },
    };
  }
}

/** @typedef {ReturnType<Gameboy["debugInfo"]>} DebugInfo */
