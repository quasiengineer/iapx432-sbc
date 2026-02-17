import { write16bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export const CARRIER_TYPE = {
  PROCESSOR: 0b00,
  PROCESS: 0b01,
  SURROGATE: 0b10,
};

export class ProcessDataSegment extends BaseObject {
  constructor(ref, params) {
    super(ref, params);
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.PROCESS_DATA;
  }

  get size() {
    return 72 * 2;
  }

  serialize(image, baseAddress) {
    // object lock
    write16bit(image, baseAddress, 0x0);

    return this.size;
  }
}