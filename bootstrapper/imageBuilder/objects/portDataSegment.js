import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export const PORT_TYPE = {
  FIFO: 0b00,
  PRIORITY_BASED: 0b01,
  DELAY: 0b11,
};

const PROCESS_QUEUE_SIZE = 8;
const PORT_SEGMENT_HEADER_SIZE = 16;

export class PortDataSegment extends BaseObject {
  #messageQueueSize;
  #portType;

  constructor(ref, params) {
    super(ref, params);
    this.#messageQueueSize = params.messageQueueSize ?? 1;
    this.#portType = params.portType ?? 0;
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.PORT_DATA;
  }

  get size() {
    return PORT_SEGMENT_HEADER_SIZE + PROCESS_QUEUE_SIZE * this.#messageQueueSize;
  }

  serialize(image, baseAddress) {
    // object lock + port type
    write32bit(image, baseAddress, 0x0 | (this.#portType << 16));
    // offset to first free message slot + offset to first message slot overall
    write32bit(image, baseAddress + 4, PORT_SEGMENT_HEADER_SIZE | (0 << 16));
    // offset to last message slot + timestamp when info about deadlines has been updated
    write32bit(image, baseAddress + 8, 0 | (0 << 16));

    return this.size;
  }
}