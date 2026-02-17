import { write16bit, write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

const IPC_MESSAGE = {
  WAKEUP: 0,
  START_PROCESSOR: 14,
};

export class LocalCommunicationSegment extends BaseObject {
    get isAccess() {
      return false;
    }

    get type() {
      return SEGMENT_TYPE.COMMUNICATION_DATA;
    }

    get size() {
      return 10;
    }

    serialize(image, baseAddress) {
      // object lock + IPC message
      write32bit(image, baseAddress, 0x00 | (IPC_MESSAGE.WAKEUP << 16));
      // response count (should be 0x01, receiving processor would set it to 0) + processor count (should be 0x01)
      write32bit(image, baseAddress + 4, 0x01 | (0x01 << 16));
      // processor ID (should be 0x01 in our case)
      write16bit(image, baseAddress + 8, 0x01);
      return this.size;
    }
}