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

  serialize(objects) {
    const image = new Uint8Array(65536);
    this.#directory.address = OBJECT_TABLE_DIRECTORY_STARTING_ADDRESS;
    const fullSize = this.#directory.serialize(image, OBJECT_TABLE_DIRECTORY_STARTING_ADDRESS, objects);
    objects.push(this.#directory);
    return image.slice(0, this.#directory.address + fullSize);
  }
}