export const ACCESS_DESCRIPTOR_SIZE = 4;

export const createAccessDescriptor = (directoryIndex, objectTableIndex) => {
  const descriptor =
    0b1            // valid, always 1
    | (0b111 << 1) // system rights (permissions to perform operations, dependant on object type), we allow everything!
    | (objectTableIndex << 4) // index of descriptor for object segment in object table
    | (0b1 << 16)  // delete rights, always allow
    | (0b1 << 17)  // heap flag, 1 means that we don't need to perform level compatibility check
    | (0b1 << 18)  // read rights, always allow
    | (0b1 << 19)  // write rights, always allow
    | (directoryIndex << 20) // index of descriptor for object table in global Object Table Directory
  ;

  return descriptor;
};
