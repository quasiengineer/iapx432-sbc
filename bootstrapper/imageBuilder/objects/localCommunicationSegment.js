import { write16bit, write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";
import { toHex } from "../../format.js";

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
      write32bit(image, baseAddress, 0x00 | (IPC_MESSAGE.WAKEUP << 16)); // object lock + IPC message
      write32bit(image, baseAddress + 4, 0x00 | (0x01 << 16)); // response count + processor count (should be 0x01)
      write16bit(image, baseAddress + 8, 0x01); // processor ID (should be 0x01)
      return this.size;
    }
}