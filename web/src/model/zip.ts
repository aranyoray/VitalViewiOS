/**
 * Minimal store-only (uncompressed) ZIP writer — enough to bundle the CSV export
 * without a third-party dependency. RFC: PKWARE APPNOTE, methods 0 (stored).
 */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** Growable little-endian byte writer. */
class ByteWriter {
  private buf = new Uint8Array(1024);
  private len = 0;
  private ensure(n: number): void {
    if (this.len + n <= this.buf.length) return;
    let cap = this.buf.length * 2;
    while (cap < this.len + n) cap *= 2;
    const next = new Uint8Array(cap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  }
  u16(v: number): void {
    this.ensure(2);
    this.buf[this.len++] = v & 0xff;
    this.buf[this.len++] = (v >>> 8) & 0xff;
  }
  u32(v: number): void {
    this.ensure(4);
    this.buf[this.len++] = v & 0xff;
    this.buf[this.len++] = (v >>> 8) & 0xff;
    this.buf[this.len++] = (v >>> 16) & 0xff;
    this.buf[this.len++] = (v >>> 24) & 0xff;
  }
  bytes(b: Uint8Array): void {
    this.ensure(b.length);
    this.buf.set(b, this.len);
    this.len += b.length;
  }
  get offset(): number {
    return this.len;
  }
  finish(): Uint8Array {
    return this.buf.subarray(0, this.len);
  }
}

export interface ZipEntry {
  name: string;
  data: Uint8Array;
}

export function zipStore(entries: ZipEntry[]): Uint8Array {
  const enc = new TextEncoder();
  const w = new ByteWriter();
  const central: { name: Uint8Array; crc: number; size: number; offset: number }[] = [];

  for (const e of entries) {
    const name = enc.encode(e.name);
    const crc = crc32(e.data);
    const offset = w.offset;
    // Local file header.
    w.u32(0x04034b50);
    w.u16(20); // version needed
    w.u16(0); // flags
    w.u16(0); // method: stored
    w.u16(0); // mod time
    w.u16(0); // mod date
    w.u32(crc);
    w.u32(e.data.length); // compressed size
    w.u32(e.data.length); // uncompressed size
    w.u16(name.length);
    w.u16(0); // extra len
    w.bytes(name);
    w.bytes(e.data);
    central.push({ name, crc, size: e.data.length, offset });
  }

  const cdStart = w.offset;
  for (const c of central) {
    w.u32(0x02014b50);
    w.u16(20); // version made by
    w.u16(20); // version needed
    w.u16(0); // flags
    w.u16(0); // method
    w.u16(0); // time
    w.u16(0); // date
    w.u32(c.crc);
    w.u32(c.size);
    w.u32(c.size);
    w.u16(c.name.length);
    w.u16(0); // extra
    w.u16(0); // comment
    w.u16(0); // disk number start
    w.u16(0); // internal attrs
    w.u32(0); // external attrs
    w.u32(c.offset);
    w.bytes(c.name);
  }
  const cdSize = w.offset - cdStart;

  // End of central directory.
  w.u32(0x06054b50);
  w.u16(0); // disk
  w.u16(0); // disk with cd
  w.u16(central.length);
  w.u16(central.length);
  w.u32(cdSize);
  w.u32(cdStart);
  w.u16(0); // comment len
  return w.finish();
}
