let maxWrittenAddr = 0;

const write32bit = (image, addr, value) => {
  // least significant byte at lowest address
  image[addr + 3] = (value >> 24) & 0xFF;
  image[addr + 2] = (value >> 16) & 0xFF;
  image[addr + 1] = (value >> 8) & 0xFF;
  image[addr + 0] = value & 0xFF;

  maxWrittenAddr = Math.max(maxWrittenAddr, addr + 3);
};

export {
  write32bit,
  maxWrittenAddr,
};
