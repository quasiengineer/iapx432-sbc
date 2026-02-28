import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class OperandStackSegment extends BaseObject {
  #size;
  #data;

  constructor(ref, params) {
    super(ref, params);

    this.#size = params.size;
    this.#data = params.data;
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

  serialize(image, baseAddress) {
    for (let i = 0, address = baseAddress; i < this.#data.length; i++, address++) {
      image[address] = this.#data[i];
    }

    return this.size;
  }
}