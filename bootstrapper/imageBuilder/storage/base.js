const write32bit = (image, addr, value) => {
  // least significant byte at lowest address
  image[addr + 3] = (value >> 24) & 0xFF;
  image[addr + 2] = (value >> 16) & 0xFF;
  image[addr + 1] = (value >> 8) & 0xFF;
  image[addr + 0] = value & 0xFF;
};

const write16bit = (image, addr, value) => {
  image[addr + 1] = (value >> 8) & 0xFF;
  image[addr + 0] = value & 0xFF;
};

const read32bit = (image, addr) => {
  return (image[addr + 3] << 24) | (image[addr + 2] << 16) | (image[addr + 1] << 8) | image[addr + 0];
};

export {
  write32bit,
  write16bit,
  read32bit,
};
