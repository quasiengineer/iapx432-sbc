let maxAddr = 0;

const write32bit = (image, addr, value) => {
  // least significant byte at lowest address
  image[addr + 3] = (value >> 24) & 0xFF;
  image[addr + 2] = (value >> 16) & 0xFF;
  image[addr + 1] = (value >> 8) & 0xFF;
  image[addr + 0] = value & 0xFF;

  maxAddr = Math.max(maxAddr, addr + 3);
};

const buildImage = () => {
  const image = new Uint8Array(65536);

  write32bit(image, 0x18, 0x12345678);

  return image.slice(0, maxAddr + 1);
};

export {
  buildImage,
};