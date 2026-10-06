using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    namespace ImageWriters {
        void be32 (ByteArray b, uint32 v) {
            uint8[] d = { (uint8) (v >> 24), (uint8) (v >> 16), (uint8) (v >> 8), (uint8) v };
            b.append (d);
        }

        void le16 (ByteArray b, uint v) {
            uint8[] d = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
            b.append (d);
        }

        void le32 (ByteArray b, uint32 v) {
            uint8[] d = { (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) };
            b.append (d);
        }

        uint8[] deflate (uint8[] raw, ZlibCompressorFormat format, int level) throws Error {
            var conv = new ZlibCompressor (format, level);
            var mem = new MemoryOutputStream.resizable ();
            var stream = new ConverterOutputStream (mem, conv);
            size_t done;
            stream.write_all (raw, out done);
            stream.close ();
            var data = mem.steal_data ();
            data.length = (int) mem.get_data_size ();
            return data;
        }

        void chunk (ByteArray b, string type, uint8[] data) {
            be32 (b, data.length);
            var body = new ByteArray ();
            body.append (type.data);
            body.append (data);
            b.append (body.data);
            be32 (b, (uint32) ZLib.Utility.crc32 (0, body.data));
        }

        public void png (FloatImage img, string path, bool sixteen, string transfer = "sdr") throws Error {
            int w = img.width, h = img.height;
            int bpp = sixteen ? 8 : 4;
            var raw = new uint8[(w * bpp + 1) * h];
            uint16[]? words = sixteen ? ColorPipeline.encode_rgba16 (img, transfer) : null;
            uint8[]? bytes = sixteen ? null : ColorPipeline.encode_rgba8 (img, false);
            for (int y = 0; y < h; y++) {
                int row = y * (w * bpp + 1);
                raw[row] = 0;
                for (int x = 0; x < w * 4; x++) {
                    if (sixteen) {
                        uint16 v = words[y * w * 4 + x];
                        if ((x & 3) == 3) v = (uint16) (img.data[(y * w) * 4 + x].clamp (0, 1) * 65535 + 0.5f);
                        raw[row + 1 + x * 2] = (uint8) (v >> 8);
                        raw[row + 2 + x * 2] = (uint8) (v & 0xff);
                    } else {
                        raw[row + 1 + x] = bytes[y * w * 4 + x];
                    }
                }
            }
            var b = new ByteArray ();
            uint8[] sig = { 137, 80, 78, 71, 13, 10, 26, 10 };
            b.append (sig);
            var ihdr = new ByteArray ();
            be32 (ihdr, w);
            be32 (ihdr, h);
            uint8[] rest = { (uint8) (sixteen ? 16 : 8), 6, 0, 0, 0 };
            ihdr.append (rest);
            chunk (b, "IHDR", ihdr.data);
            if (transfer == "sdr") {
                uint8[] srgb = { 0 };
                chunk (b, "sRGB", srgb);
            }
            chunk (b, "IDAT", deflate (raw, ZlibCompressorFormat.ZLIB, 6));
            chunk (b, "IEND", new uint8[0]);
            FileUtils.set_data (path, b.data);
        }

        public void tiff (FloatImage img, string path, string transfer = "sdr") throws Error {
            int w = img.width, h = img.height;
            var words = ColorPipeline.encode_rgba16 (img, transfer);
            var b = new ByteArray ();
            uint8[] header = { 'I', 'I', 42, 0 };
            b.append (header);
            uint32 data_offset = 8;
            uint32 data_size = (uint32) (w * h * 8);
            le32 (b, data_offset + data_size);
            var pixels = new uint8[data_size];
            for (int i = 0; i < w * h * 4; i++) {
                uint16 v = words[i];
                if ((i & 3) == 3) v = (uint16) (img.data[i].clamp (0, 1) * 65535 + 0.5f);
                pixels[i * 2] = (uint8) (v & 0xff);
                pixels[i * 2 + 1] = (uint8) (v >> 8);
            }
            b.append (pixels);
            uint32 ifd = b.len;
            uint32 bits_offset = ifd + 2 + 12 * 11 + 4;
            uint32 extra_offset = bits_offset + 8;
            le16 (b, 11);
            tag (b, 256, 4, 1, w);
            tag (b, 257, 4, 1, h);
            tag (b, 258, 3, 4, bits_offset);
            tag (b, 259, 3, 1, 1);
            tag (b, 262, 3, 1, 2);
            tag (b, 273, 4, 1, data_offset);
            tag (b, 277, 3, 1, 4);
            tag (b, 278, 4, 1, h);
            tag (b, 279, 4, 1, data_size);
            tag (b, 284, 3, 1, 1);
            tag (b, 338, 3, 1, 2);
            le32 (b, 0);
            for (int i = 0; i < 4; i++) le16 (b, 16);
            if (b.len != extra_offset) warning ("tiff layout mismatch");
            FileUtils.set_data (path, b.data);
        }

        void tag (ByteArray b, uint id, uint type, uint32 count, uint32 value) {
            le16 (b, id);
            le16 (b, type);
            le32 (b, count);
            if (type == 3 && count == 1) {
                le16 (b, value);
                le16 (b, 0);
            } else {
                le32 (b, value);
            }
        }

        public uint16 half (float value) {
            uint32 f = *((uint32*) (&value));
            uint32 sign = (f >> 16) & 0x8000;
            int32 exponent = (int32) ((f >> 23) & 0xFF) - 127 + 15;
            uint32 mantissa = f & 0x7FFFFF;
            if (((f >> 23) & 0xFF) == 0xFF) return (uint16) (sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0));
            if (exponent >= 31) return (uint16) (sign | 0x7C00);
            if (exponent <= 0) {
                if (exponent < -10) return (uint16) sign;
                mantissa |= 0x800000;
                uint32 shift = (uint32) (14 - exponent);
                uint32 half_m = mantissa >> shift;
                if (((mantissa >> (shift - 1)) & 1) != 0) half_m++;
                return (uint16) (sign | half_m);
            }
            uint32 hv = sign | ((uint32) exponent << 10) | (mantissa >> 13);
            if ((mantissa & 0x1000) != 0) hv++;
            return (uint16) hv;
        }

        void cstr (ByteArray b, string s) {
            b.append (s.data);
            uint8[] z = { 0 };
            b.append (z);
        }

        void attribute (ByteArray b, string name, string type, uint8[] value) {
            cstr (b, name);
            cstr (b, type);
            le32 (b, value.length);
            b.append (value);
        }

        public void exr (FloatImage img, string path, string primaries = "rec709") throws Error {
            int w = img.width, h = img.height;
            string[] names = { "A", "B", "G", "R" };
            int[] source = { 3, 2, 1, 0 };
            var header = new ByteArray ();
            le32 (header, 20000630);
            le32 (header, 2);
            var ch = new ByteArray ();
            foreach (var n in names) {
                cstr (ch, n);
                le32 (ch, 1);
                le32 (ch, 0);
                le32 (ch, 1);
                le32 (ch, 1);
            }
            uint8[] z = { 0 };
            ch.append (z);
            attribute (header, "channels", "chlist", ch.data);
            attribute (header, "compression", "compression", new uint8[] { 0 });
            var box = new ByteArray ();
            le32 (box, 0);
            le32 (box, 0);
            le32 (box, w - 1);
            le32 (box, h - 1);
            attribute (header, "dataWindow", "box2i", box.data);
            attribute (header, "displayWindow", "box2i", box.data);
            attribute (header, "lineOrder", "lineOrder", new uint8[] { 0 });
            var one = new ByteArray ();
            float f1 = 1.0f;
            le32 (one, *((uint32*) (&f1)));
            attribute (header, "pixelAspectRatio", "float", one.data);
            var center = new ByteArray ();
            le32 (center, 0);
            le32 (center, 0);
            attribute (header, "screenWindowCenter", "v2f", center.data);
            attribute (header, "screenWindowWidth", "float", one.data);
            var p = primaries == "rec2020" ? Primaries.rec2020 () : Primaries.rec709 ();
            var chroma = new ByteArray ();
            double[] cv = { p.rx, p.ry, p.gx, p.gy, p.bx, p.by, p.wx, p.wy };
            foreach (double d in cv) {
                float fv = (float) d;
                le32 (chroma, *((uint32*) (&fv)));
            }
            attribute (header, "chromaticities", "chromaticities", chroma.data);
            header.append (z);
            var out_data = new ByteArray ();
            out_data.append (header.data);
            uint64 row_size = 8 + (uint64) w * 4 * 2;
            uint64 at = header.len + (uint64) h * 8;
            for (int y = 0; y < h; y++) {
                le32 (out_data, (uint32) (at & 0xffffffff));
                le32 (out_data, (uint32) (at >> 32));
                at += row_size;
            }
            for (int y = 0; y < h; y++) {
                le32 (out_data, y);
                le32 (out_data, w * 4 * 2);
                var row = new uint8[w * 4 * 2];
                int k = 0;
                for (int c = 0; c < 4; c++) {
                    for (int x = 0; x < w; x++) {
                        uint16 hv = half (img.data[img.offset (x, y) + source[c]]);
                        row[k++] = (uint8) (hv & 0xff);
                        row[k++] = (uint8) (hv >> 8);
                    }
                }
                out_data.append (row);
            }
            FileUtils.set_data (path, out_data.data);
        }
    }
}
