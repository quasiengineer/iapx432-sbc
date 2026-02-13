import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";
import { toHex } from "../../format.js";

export class ProcessorDataSegment extends BaseObject {
    get isAccess() {
      return false;
    }

    get type() {
      return SEGMENT_TYPE.PROCESSOR_DATA;
    }

    get size() {
      return 4;
    }

    serialize(image, baseAddress) {
      console.log(`  placing Processor data segment at address ${toHex(baseAddress)}`);
      const word0 =
        0x0               // not locked
        | (0b0000 << 16)  // processor state, 0000 = Initialization
        | (0b00 << 20)    // dispatching mode, 00 = normal mode
        | (0b1 << 22)     // stopped by IPC, 0 = non-stopped, should execute a process
        | (0b1 << 23)     // broadcast acceptance mode, 0 = no broadcast message in progress
        | (0x1 << 24)     // processor ID
      ;

      write32bit(image, baseAddress, word0);
      return this.size;
    }
}