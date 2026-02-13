const OBJECT_TABLE_DIRECTORY_STARTING_ADDRESS = 0x08;

export class ObjectTableDirectory {
  #directory;

  constructor(directoryObjectTable) {
    // object table directory is regular object table just with predefined first descriptors
    this.#directory = directoryObjectTable;
  }

  addObjectTable(objectTable) {
    this.#directory.addObject(objectTable);
  }

  serialize() {
    const image = new Uint8Array(65536);
    const fullSize = this.#directory.serialize(image, OBJECT_TABLE_DIRECTORY_STARTING_ADDRESS);
    return image.slice(0, this.#directory.address + fullSize);
  }
}