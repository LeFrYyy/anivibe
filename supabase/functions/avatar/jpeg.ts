import jpeg from 'npm:jpeg-js@0.4.4';
export function dimensions(data: Uint8Array): [number, number] {
  if (data.length < 4 || data[0] !== 255 || data[1] !== 216) throw new Error('jpeg');
  let pos = 2;
  while (pos < data.length) {
    if (data[pos++] !== 255) throw new Error('marker');
    while (data[pos] === 255) pos++;
    const marker = data[pos++];
    if (marker === 218 || marker === 217) break;
    if (marker === 1 || (marker >= 208 && marker <= 215)) continue;
    if (pos + 2 > data.length) throw new Error('length');
    const length = (data[pos] << 8) | data[pos+1];
    if (length < 2 || pos + length > data.length) throw new Error('length');
    if (marker === 192 || marker === 194) {
      if (length < 8 || data[pos+2] !== 8) throw new Error('sof');
      const h = (data[pos+3] << 8) | data[pos+4], w = (data[pos+5] << 8) | data[pos+6];
      if (w < 1 || h < 1 || w > 1024 || h > 1024 || w*h > 1048576) throw new Error('pixels');
      return [w,h];
    }
    pos += length;
  }
  throw new Error('sof');
}
export function canonicalJPEG(data: Uint8Array): Uint8Array {
  if (data.length > 1048576) throw new Error('size');
  const [w,h] = dimensions(data);
  const image = jpeg.decode(data, {useTArray:true,tolerantDecoding:false,maxResolutionInMP:1.1,maxMemoryUsageInMB:32});
  if (image.width !== w || image.height !== h) throw new Error('dimensions');
  // Encoder must not inherit EXIF/comments from decoder.
  const out = jpeg.encode({width:w,height:h,data:image.data},80).data;
  if (out.length > 1048576) throw new Error('size');
  return new Uint8Array(out);
}
