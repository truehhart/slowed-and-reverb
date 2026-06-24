import { describe, it, expect } from "vitest";
import {
  clamp,
  fmt,
  fmtCounter,
  angleFromValue,
  valueFromAngle,
  pctToUnit,
} from "../../src/ui-math";

describe("clamp", () => {
  it("bounds to range", () => {
    expect(clamp(5, 0, 10)).toBe(5);
    expect(clamp(-1, 0, 10)).toBe(0);
    expect(clamp(11, 0, 10)).toBe(10);
  });
});

describe("fmt", () => {
  it("formats mm:ss", () => {
    expect(fmt(0)).toBe("0:00");
    expect(fmt(5)).toBe("0:05");
    expect(fmt(65)).toBe("1:05");
    expect(fmt(3725)).toBe("62:05");
  });
  it("clamps negatives and NaN to 0:00", () => {
    expect(fmt(-3)).toBe("0:00");
    expect(fmt(NaN)).toBe("0:00");
    expect(fmt(Infinity)).toBe("0:00");
  });
});

describe("fmtCounter", () => {
  it("formats hh:mm:ss", () => {
    expect(fmtCounter(0)).toBe("00:00:00");
    expect(fmtCounter(9)).toBe("00:00:09");
    expect(fmtCounter(2529)).toBe("00:42:09");
    expect(fmtCounter(3661)).toBe("01:01:01");
  });
  it("clamps negatives and NaN", () => {
    expect(fmtCounter(-5)).toBe("00:00:00");
    expect(fmtCounter(NaN)).toBe("00:00:00");
  });
});

describe("angleFromValue / valueFromAngle", () => {
  it("maps min→0deg, max→270deg over the speed range", () => {
    expect(angleFromValue(50, 50, 100)).toBe(0);
    expect(angleFromValue(100, 50, 100)).toBe(270);
    expect(angleFromValue(75, 50, 100)).toBe(135);
  });
  it("maps min→0deg, max→270deg over the reverb range", () => {
    expect(angleFromValue(0, 0, 100)).toBe(0);
    expect(angleFromValue(100, 0, 100)).toBe(270);
    expect(angleFromValue(50, 0, 100)).toBe(135);
  });
  it("clamps out-of-range values", () => {
    expect(angleFromValue(40, 50, 100)).toBe(0);
    expect(angleFromValue(120, 50, 100)).toBe(270);
  });
  it("round-trips through the inverse", () => {
    for (const v of [50, 60, 75, 90, 100]) {
      expect(valueFromAngle(angleFromValue(v, 50, 100), 50, 100)).toBe(v);
    }
    for (const v of [0, 25, 50, 75, 100]) {
      expect(valueFromAngle(angleFromValue(v, 0, 100), 0, 100)).toBe(v);
    }
  });
});

describe("pctToUnit", () => {
  it("scales 0–100 to 0–1", () => {
    expect(pctToUnit(0)).toBe(0);
    expect(pctToUnit(80)).toBeCloseTo(0.8);
    expect(pctToUnit(100)).toBe(1);
  });
});
