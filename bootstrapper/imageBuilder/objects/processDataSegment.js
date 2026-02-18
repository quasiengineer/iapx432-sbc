import { write16bit, write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

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

    // period count (don't send process to scheduling port) + service period
    write32bit(image, baseAddress + 0x20, 0xFFFFFFFF);

    return this.size;
  }
}