import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export const CARRIER_TYPE = {
  PROCESSOR: 0b00,
  PROCESS: 0b01,
  SURROGATE: 0b10,
};

export class CarrierDataSegment extends BaseObject {
  #carrierType;
  #hasMessage;

  constructor(ref, params) {
    super(ref, params);
    this.#carrierType = params.carrierType ?? 0;
    this.#hasMessage = params.hasMessage ?? false;
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.CARRIER_DATA;
  }

  get size() {
    return 16;
  }

  serialize(image, baseAddress) {
    // object lock + port type + carrier type + carrier status
    write32bit(image, baseAddress, 0x0 | (this.#carrierType << 16) | ((this.#hasMessage ? 0b11 : 0b00) << 18));
    // maintenance request flag
    write32bit(image, baseAddress + 4, 0);
    // blocked queueing value
    write32bit(image, baseAddress + 8, 0);
    // second port queueing value
    write32bit(image, baseAddress + 12, 0);

    return this.size;
  }
}