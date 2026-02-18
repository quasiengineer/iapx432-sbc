import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class OperandStackSegment extends BaseObject {
  #size;

  constructor(ref, params) {
    super(ref, params);
    this.#size = params.size;
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.OPERAND_STACK_DATA;
  }

  get size() {
    return this.#size;
  }

  serialize() {
    return this.size;
  }
}