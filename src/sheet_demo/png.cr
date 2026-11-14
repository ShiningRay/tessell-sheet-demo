# Minimal PNG writer for screenshots (stored-zlib, colour type 6).
#
# Tessell v0.2.0 ships tools/lib/png.cr, but `tools/` is not reachable through
# the shard require path (only `src/` is), so a consumer cannot require it.
# This is a trimmed copy for the demo host; see docs/friction-log.md.
module SheetDemo
  module Png
    CRC_TABLE = begin
      table = Array(UInt32).new(256, 0_u32)
      256.times do |n|
        c = n.to_u32
        8.times do
          c = (c & 1_u32) != 0 ? (0xedb88320_u32 ^ (c >> 1)) : (c >> 1)
        end
        table[n] = c
      end
      table
    end

    def self.crc32(data : Bytes) : UInt32
      c = 0xffffffff_u32
      data.each do |byte|
        c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >> 8)
      end
      c ^ 0xffffffff_u32
    end

    private def self.adler32(data : Bytes) : UInt32
      a = 1_u32
      b = 0_u32
      data.each do |byte|
        a = (a + byte) % 65521
        b = (b + a) % 65521
      end
      (b << 16) | a
    end

    private def self.chunk(io : IO, type : String, payload : Bytes) : Nil
      io.write_bytes(payload.size.to_u32, IO::ByteFormat::BigEndian)
      type_bytes = type.to_slice
      io.write(type_bytes)
      io.write(payload)
      crc_input = Bytes.new(type_bytes.size + payload.size)
      crc_input.copy_from(type_bytes)
      (crc_input.to_unsafe + type_bytes.size).copy_from(payload.to_unsafe, payload.size)
      io.write_bytes(crc32(crc_input), IO::ByteFormat::BigEndian)
    end

    # zlib stream with stored (uncompressed) deflate blocks.
    private def self.zlib_stored(raw : Bytes) : Bytes
      out = IO::Memory.new
      out.write_byte(0x78_u8)
      out.write_byte(0x01_u8)
      pos = 0
      size = raw.size
      while pos < size
        n = Math.min(65535, size - pos)
        final = pos + n >= size ? 1_u8 : 0_u8
        out.write_byte(final)
        out.write_bytes(n.to_u16, IO::ByteFormat::LittleEndian)
        out.write_bytes((~n.to_u16).to_u16, IO::ByteFormat::LittleEndian)
        out.write(raw[pos, n])
        pos += n
      end
      out.write_bytes(adler32(raw), IO::ByteFormat::BigEndian)
      out.to_slice
    end

    # rgba is top-down; each row gets filter type 0.
    def self.write(path : String, width : Int32, height : Int32, rgba : Bytes) : Nil
      raise ArgumentError.new("rgba size mismatch") if rgba.size != width * height * 4
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless dir.empty? || Dir.exists?(dir)
      row_bytes = width * 4
      raw = Bytes.new(height * (1 + row_bytes))
      y = 0
      while y < height
        raw[y * (1 + row_bytes)] = 0_u8
        (raw.to_unsafe + y * (1 + row_bytes) + 1).copy_from(
          rgba.to_unsafe + y * row_bytes, row_bytes)
        y += 1
      end
      File.open(path, "wb") do |io|
        io.write(Bytes[0x89_u8, 0x50_u8, 0x4E_u8, 0x47_u8, 0x0D_u8, 0x0A_u8, 0x1A_u8, 0x0A_u8])
        ihdr = IO::Memory.new(13)
        ihdr.write_bytes(width.to_u32, IO::ByteFormat::BigEndian)
        ihdr.write_bytes(height.to_u32, IO::ByteFormat::BigEndian)
        ihdr.write_byte(8_u8)
        ihdr.write_byte(6_u8)
        ihdr.write_byte(0_u8)
        ihdr.write_byte(0_u8)
        ihdr.write_byte(0_u8)
        chunk(io, "IHDR", ihdr.to_slice)
        chunk(io, "IDAT", zlib_stored(raw))
        chunk(io, "IEND", Bytes.new(0))
      end
    end
  end
end
