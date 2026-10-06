namespace Singularity.Apps.Montage {
    public class ZipArchive : Object {
        uint8[] data;
        Gee.HashMap<string, ZipEntry> entries = new Gee.HashMap<string, ZipEntry> ();
        ByteArray output = new ByteArray ();
        ByteArray central = new ByteArray ();
        int written;

        class ZipEntry : Object {
            public uint16 method;
            public uint32 compressed;
            public uint32 size;
            public uint32 offset;
        }

        public static ZipArchive read (File file) throws Error {
            uint8[] contents;
            file.load_contents (null, out contents, null);
            return from_data (contents);
        }

        public static ZipArchive from_data (owned uint8[] bytes) throws Error {
            var z = new ZipArchive ();
            z.data = (owned) bytes;
            z.index ();
            return z;
        }

        uint16 u16 (int i) {
            return (uint16) (data[i] | (data[i + 1] << 8));
        }

        uint32 u32 (int i) {
            return (uint32) data[i] | ((uint32) data[i + 1] << 8) | ((uint32) data[i + 2] << 16) | ((uint32) data[i + 3] << 24);
        }

        void index () throws Error {
            int eocd = -1;
            for (int i = data.length - 22; i >= 0 && i >= data.length - 65557; i--) {
                if (u32 (i) == 0x06054b50) {
                    eocd = i;
                    break;
                }
            }
            if (eocd < 0) throw new IOError.INVALID_DATA (_("The file is not a valid archive."));
            int count = u16 (eocd + 10);
            int pos = (int) u32 (eocd + 16);
            for (int n = 0; n < count; n++) {
                if (pos < 0 || pos + 46 > data.length || u32 (pos) != 0x02014b50) throw new IOError.INVALID_DATA (_("The archive directory is damaged."));
                var e = new ZipEntry ();
                e.method = u16 (pos + 10);
                e.compressed = u32 (pos + 20);
                e.size = u32 (pos + 24);
                int name_len = u16 (pos + 28);
                int extra_len = u16 (pos + 30);
                int comment_len = u16 (pos + 32);
                e.offset = u32 (pos + 42);
                if (pos + 46 + name_len > data.length) throw new IOError.INVALID_DATA (_("The archive directory is damaged."));
                var nb = new StringBuilder ();
                nb.append_len ((string) ((uint8*) data + pos + 46), name_len);
                entries[nb.str] = e;
                pos += 46 + name_len + extra_len + comment_len;
            }
        }

        public Gee.Set<string> names () {
            return entries.keys;
        }

        public new uint8[]? get (string name) throws Error {
            var e = entries[name];
            if (e == null) return null;
            int p = (int) e.offset;
            if (p < 0 || p + 30 > data.length || u32 (p) != 0x04034b50) throw new IOError.INVALID_DATA (_("The archive entry is damaged."));
            int start = p + 30 + u16 (p + 26) + u16 (p + 28);
            int end = start + (int) e.compressed;
            if (end > data.length || e.size > 1024 * 1024 * 1024) throw new IOError.INVALID_DATA (_("The archive entry is truncated."));
            uint8[] raw = data[start:end];
            if (e.method == 0) return raw;
            if (e.method != 8) throw new IOError.NOT_SUPPORTED (_("The archive uses an unsupported compression."));
            var conv = new ZlibDecompressor (ZlibCompressorFormat.RAW);
            var stream = new ConverterInputStream (new MemoryInputStream.from_data (raw), conv);
            var out_buf = new ByteArray.sized (e.size > 0 ? e.size : 4096);
            uint8[] chunk = new uint8[65536];
            ssize_t n;
            while ((n = stream.read (chunk)) > 0) out_buf.append (chunk[0:n]);
            return out_buf.steal ();
        }

        public string? text (string name) throws Error {
            var b = get (name);
            if (b == null) return null;
            var sb = new StringBuilder.sized (b.length + 1);
            sb.append_len ((string) b, b.length);
            return sb.str;
        }

        static void put16 (ByteArray b, uint v) {
            uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
            b.append (x);
        }

        static void put32 (ByteArray b, uint32 v) {
            uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
            b.append (x);
        }

        public void add (string name, uint8[] content, bool compress = true) throws Error {
            uint32 crc = (uint32) ZLib.Utility.crc32 (0, content);
            uint8[] payload = content;
            uint16 method = 0;
            if (compress && content.length > 0) {
                var conv = new ZlibCompressor (ZlibCompressorFormat.RAW, 6);
                var mem = new MemoryOutputStream.resizable ();
                var stream = new ConverterOutputStream (mem, conv);
                size_t done;
                stream.write_all (content, out done);
                stream.close ();
                payload = mem.steal_data ();
                payload.length = (int) mem.get_data_size ();
                method = 8;
            }
            uint32 offset = output.len;
            put32 (output, 0x04034b50);
            put16 (output, 20);
            put16 (output, 0x0800);
            put16 (output, method);
            put16 (output, 0);
            put16 (output, 0x21);
            put32 (output, crc);
            put32 (output, payload.length);
            put32 (output, content.length);
            put16 (output, name.length);
            put16 (output, 0);
            output.append (name.data);
            output.append (payload);
            put32 (central, 0x02014b50);
            put16 (central, 20);
            put16 (central, 20);
            put16 (central, 0x0800);
            put16 (central, method);
            put16 (central, 0);
            put16 (central, 0x21);
            put32 (central, crc);
            put32 (central, payload.length);
            put32 (central, content.length);
            put16 (central, name.length);
            put16 (central, 0);
            put16 (central, 0);
            put16 (central, 0);
            put16 (central, 0);
            put32 (central, 0);
            put32 (central, offset);
            central.append (name.data);
            written++;
        }

        public void add_text (string name, string content, bool compress = true) throws Error {
            add (name, content.data, compress);
        }

        public uint8[] finish () {
            uint32 cd_offset = output.len;
            uint32 cd_size = central.len;
            output.append (central.data);
            put32 (output, 0x06054b50);
            put16 (output, 0);
            put16 (output, 0);
            put16 (output, written);
            put16 (output, written);
            put32 (output, cd_size);
            put32 (output, cd_offset);
            put16 (output, 0);
            return output.steal ();
        }

        public void save (File file) throws Error {
            var bytes = finish ();
            file.replace_contents (bytes, null, false, FileCreateFlags.NONE, null);
        }
    }
}
