import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class GenericDataSegment extends BaseObject {
  #size;
  #data;
  #type;

  constructor(ref, params) {
    super(ref, params);

    this.#data = params.data || [];
    this.#size = params.size || this.#data.length;
    this.#type = params.type || SEGMENT_TYPE.GENERIC_DATA;
  }

  get isAccess() {
    return false;
  }

  get type() {
    return this.#type;
  }

  get size() {
    return this.#size;
  }

  serialize(image, baseAddress) {
    for (let i = 0, address = baseAddress; i < this.#data.length; i++, address++) {
      if (this.#data[i] > 0xFF) {
        throw new Error(`Data value ${this.#data[i]} is too large for a byte`);
      }

      image[address] = this.#data[i];
    }

    return this.size;
  }
}