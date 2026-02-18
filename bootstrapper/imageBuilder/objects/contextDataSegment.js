import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";
import { INSTRUCTION_HEADER_SIZE } from "./instructionSegment.js";

export class ContextDataSegment extends BaseObject {
  constructor(ref, params) {
    super(ref, params);
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.CONTEXT_DATA;
  }

  get size() {
    return 7 * 2;
  }

  serialize(image, baseAddress) {
    // status + SP
    write32bit(image, baseAddress, 0);
    // current instruction object index + instruction pointer (in bits)
    write32bit(image, baseAddress + 4, 0 | ((INSTRUCTION_HEADER_SIZE * 8) << 16));

    return this.size;
  }
}