import { describe, expect, it } from "vitest";
import familyCodeModel from "../../../ios/ShooApp/Features/Pairing/FamilyCodeModel.swift?raw";
import apiRepository from "../../../ios/ShooApp/Data/ApiRepository.swift?raw";
import { CODE_TTL_SECONDS } from "../src/db/repo/codes";
import { REUSE_MIN_SECONDS } from "../src/services/family";

// GD-04: the app clamps the countdown to the code's lifetime (a wrong phone clock never stretches it) and
// reuses a cached code like the server does. Both numbers are copies of the server's: this keeps them equal.

/** `static let <name>: TimeInterval = <a> * <b> ...` in Swift, evaluated (numbers and `*` only). */
function swiftSeconds(source: string, name: string): number {
  const match = source.match(new RegExp(`static let ${name}: TimeInterval = ([0-9 *]+)\\n`));
  if (!match?.[1]) throw new Error(`${name} is not a plain product of numbers any more`);
  return match[1].split("*").reduce((product, n) => product * Number(n.trim()), 1);
}

describe("family code timing: app = server", () => {
  it("FamilyCodeModel.codeLifetime = CODE_TTL_SECONDS", () => {
    expect(swiftSeconds(familyCodeModel, "codeLifetime")).toBe(CODE_TTL_SECONDS);
  });

  it("ApiRepository.codeReuseSeconds = REUSE_MIN_SECONDS", () => {
    expect(swiftSeconds(apiRepository, "codeReuseSeconds")).toBe(REUSE_MIN_SECONDS);
  });
});
