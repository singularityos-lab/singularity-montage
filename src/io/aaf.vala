namespace Singularity.Apps.Montage {
    namespace Aaf {
        const uint32 FREESECT = 0xFFFFFFFFU;
        const uint32 ENDOFCHAIN = 0xFFFFFFFEU;
        const uint32 FATSECT = 0xFFFFFFFDU;
        const uint32 DIFSECT = 0xFFFFFFFCU;
        const uint32 NOSTREAM = 0xFFFFFFFFU;
        const uint32 MAXREGSECT = 0xFFFFFFFAU;
        const int MINI_CUTOFF = 4096;
        const int SECTOR = 512;

        const uint8 SF_DATA = 0x82;
        const uint8 SF_STRONG = 0x22;
        const uint8 SF_VECTOR = 0x32;
        const uint8 SF_SET = 0x3A;
        const uint8 SF_WEAK = 0x02;

        const string ROOT_CLASS = "b3b398a5-1c90-11d4-8053-080036210804";
        const string FILE_CLASS = "42464141-000d-4d4f-060e-2b34010101ff";
        const string C_META = "0d010101-0225-0000-060e-2b3402060101";
        const string C_HEADER = "0d010101-0101-2f00-060e-2b3402060101";
        const string C_CONTENT = "0d010101-0101-1800-060e-2b3402060101";
        const string C_DICTIONARY = "0d010101-0101-2200-060e-2b3402060101";
        const string C_IDENTIFICATION = "0d010101-0101-3000-060e-2b3402060101";
        const string C_DATADEF = "0d010101-0101-1b00-060e-2b3402060101";
        const string C_OPDEF = "0d010101-0101-1c00-060e-2b3402060101";
        const string C_COMPOSITION = "0d010101-0101-3500-060e-2b3402060101";
        const string C_MASTER = "0d010101-0101-3600-060e-2b3402060101";
        const string C_SOURCE = "0d010101-0101-3700-060e-2b3402060101";
        const string C_TIMELINE_SLOT = "0d010101-0101-3b00-060e-2b3402060101";
        const string C_EVENT_SLOT = "0d010101-0101-3900-060e-2b3402060101";
        const string C_SEQUENCE = "0d010101-0101-0f00-060e-2b3402060101";
        const string C_SOURCE_CLIP = "0d010101-0101-1100-060e-2b3402060101";
        const string C_FILLER = "0d010101-0101-0900-060e-2b3402060101";
        const string C_TRANSITION = "0d010101-0101-1700-060e-2b3402060101";
        const string C_OPERATION_GROUP = "0d010101-0101-0a00-060e-2b3402060101";
        const string C_SELECTOR = "0d010101-0101-0e00-060e-2b3402060101";
        const string C_ESSENCE_GROUP = "0d010101-0101-0500-060e-2b3402060101";
        const string C_COMMENT_MARKER = "0d010101-0101-0800-060e-2b3402060101";
        const string C_DESCRIPTIVE_MARKER = "0d010101-0101-4100-060e-2b3402060101";
        const string C_IMPORT_DESCRIPTOR = "0d010101-0101-4a00-060e-2b3402060101";
        const string C_NETWORK_LOCATOR = "0d010101-0101-3200-060e-2b3402060101";

        const string DD_PICTURE = "01030202-0100-0000-060e-2b3404010101";
        const string DD_SOUND = "01030202-0200-0000-060e-2b3404010101";
        const string DD_DESCRIPTIVE = "01030201-1000-0000-060e-2b3404010101";
        const string DD_LEGACY_PICTURE = "6f3c8ce1-6cef-11d2-807d-006008143e6f";
        const string DD_LEGACY_SOUND = "78e1ebe1-6cef-11d2-807d-006008143e6f";
        const string DD_PICTURE_MATTE = "05cba732-1daa-11d3-80ad-006008143e6f";
        const string OP_VIDEO_DISSOLVE = "0c3bea40-fc05-11d2-8a29-0050040ef7d2";
        const string OP_AUDIO_DISSOLVE = "0c3bea41-fc05-11d2-8a29-0050040ef7d2";
        const string EDIT_PROTOCOL = "0d011201-0100-0000-060e-2b3404010105";
        const string PRODUCT_ID = "7a1e3c52-9b1f-4d0e-a6f2-3f8c5d21b904";

        const uint16 TABLE_DATADEFS = 0;
        const uint16 TABLE_OPDEFS = 1;

        class Out {
            public ByteArray bytes = new ByteArray ();

            public int size {
                get { return (int) bytes.len; }
            }

            public void u8 (uint8 v) {
                uint8[] b = { v };
                bytes.append (b);
            }

            public void u16 (uint v) {
                uint8[] b = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
                bytes.append (b);
            }

            public void u32 (uint32 v) {
                uint8[] b = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
                bytes.append (b);
            }

            public void i64 (int64 v) {
                uint64 u = (uint64) v;
                u32 ((uint32) (u & 0xffffffff));
                u32 ((uint32) (u >> 32));
            }

            public void raw (uint8[] d) {
                bytes.append (d);
            }

            public void fill (int n, uint8 v) {
                if (n <= 0) return;
                var b = new uint8[n];
                if (v != 0) Memory.set (b, v, n);
                bytes.append (b);
            }

            public void pad (int unit, uint8 v = 0) {
                int r = size % unit;
                if (r != 0) fill (unit - r, v);
            }

            public uint8[] take () {
                return bytes.steal ();
            }
        }

        uint16 rd16 (uint8[] d, int64 i) {
            if (i < 0 || i + 2 > d.length) return 0;
            int k = (int) i;
            return (uint16) (d[k] | (d[k + 1] << 8));
        }

        uint32 rd32 (uint8[] d, int64 i, uint32 fallback = 0) {
            if (i < 0 || i + 4 > d.length) return fallback;
            int k = (int) i;
            return (uint32) d[k] | ((uint32) d[k + 1] << 8) | ((uint32) d[k + 2] << 16) | ((uint32) d[k + 3] << 24);
        }

        int64 rd64 (uint8[] d, int64 i) {
            return (int64) ((uint64) rd32 (d, i) | ((uint64) rd32 (d, i + 4) << 32));
        }

        uint8[] utf16z (string s) {
            var o = new Out ();
            int i = 0;
            unichar c;
            while (s.get_next_char (ref i, out c)) {
                if (c >= 0x10000) {
                    uint32 v = c - 0x10000;
                    o.u16 (0xD800 + (v >> 10));
                    o.u16 (0xDC00 + (v & 0x3FF));
                } else {
                    o.u16 (c);
                }
            }
            o.u16 (0);
            return o.take ();
        }

        int utf16_units (string s) {
            int n = 0;
            int i = 0;
            unichar c;
            while (s.get_next_char (ref i, out c)) n += c >= 0x10000 ? 2 : 1;
            return n;
        }

        string utf16_text (uint8[] d, int start, int len) {
            var sb = new StringBuilder ();
            int end = int.min (d.length, start + len);
            for (int i = start; i + 1 < end; i += 2) {
                uint u = d[i] | (d[i + 1] << 8);
                if (u == 0) break;
                if (u >= 0xD800 && u < 0xDC00 && i + 3 < end) {
                    uint lo = d[i + 2] | (d[i + 3] << 8);
                    if (lo >= 0xDC00 && lo < 0xE000) {
                        sb.append_unichar ((unichar) (0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)));
                        i += 2;
                        continue;
                    }
                }
                if (u >= 0xD800 && u < 0xE000) u = 0xFFFD;
                sb.append_unichar ((unichar) u);
            }
            return sb.str;
        }

        uint8[] auid (string text) {
            string hex = text.replace ("-", "");
            var c = new uint8[16];
            for (int i = 0; i < 16 && i * 2 + 1 < hex.length; i++)
                c[i] = (uint8) ((hex[i * 2].xdigit_value () << 4) | hex[i * 2 + 1].xdigit_value ());
            uint8[] le = { c[3], c[2], c[1], c[0], c[5], c[4], c[7], c[6], c[8], c[9], c[10], c[11], c[12], c[13], c[14], c[15] };
            return le;
        }

        string auid_text (uint8[] b, int o) {
            if (o < 0 || o + 16 > b.length) return "";
            return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x".printf (
                b[o + 3], b[o + 2], b[o + 1], b[o], b[o + 5], b[o + 4], b[o + 7], b[o + 6],
                b[o + 8], b[o + 9], b[o + 10], b[o + 11], b[o + 12], b[o + 13], b[o + 14], b[o + 15]);
        }

        string hex_of (uint8[] b) {
            var sb = new StringBuilder ();
            bool any = false;
            foreach (var v in b) {
                sb.append_printf ("%02x", v);
                if (v != 0) any = true;
            }
            return any ? sb.str : "";
        }

        uint8[] new_mob_id () {
            uint8[] label = { 0x06, 0x0a, 0x2b, 0x34, 0x01, 0x01, 0x01, 0x05, 0x01, 0x01, 0x0f, 0x20, 0x13, 0x00, 0x00, 0x00 };
            var o = new Out ();
            o.raw (label);
            o.raw (auid (Uuid.string_random ()));
            return o.take ();
        }

        int64 to_units (int64 t, int n, int d) {
            if (n <= 0 || d <= 0) return 0;
            return (int64) Math.round ((double) t * n / ((double) d * Tc.SECOND));
        }

        int64 from_units (int64 u, int n, int d) {
            if (n <= 0 || d <= 0) return 0;
            return (int64) Math.round ((double) u * d * Tc.SECOND / n);
        }

        int name_order (string a, string b) {
            int la = utf16_units (a), lb = utf16_units (b);
            if (la != lb) return la < lb ? -1 : 1;
            return strcmp (a.up (), b.up ());
        }

        string mangle (string name, uint pid, int size) {
            string h = "%x".printf (pid);
            int max = size - h.length - 2;
            string n = name;
            if (n.length > max) {
                int half = max / 2;
                var sb = new StringBuilder ();
                for (int i = 0; i < max; i++) {
                    if (i < half) sb.append_c (n[i]);
                    else if (i == half) sb.append_c ('-');
                    else sb.append_c (n[n.length - (max - i)]);
                }
                n = sb.str;
            }
            return n + "-" + h;
        }

        class CfbEntry {
            public string name = "";
            public int type;
            public uint32 left = NOSTREAM;
            public uint32 right = NOSTREAM;
            public uint32 child = NOSTREAM;
            public uint8[] clsid = new uint8[16];
            public uint32 start = ENDOFCHAIN;
            public int64 size;
        }

        class CfbReader {
            uint8[] data;
            int sector_size = SECTOR;
            uint32[] fat = {};
            uint32[] minifat = {};
            uint8[] mini = {};
            public Gee.ArrayList<CfbEntry> entries = new Gee.ArrayList<CfbEntry> ();

            public CfbReader (uint8[] bytes) throws Error {
                data = bytes;
                uint8[] magic = { 0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1 };
                if (data.length < 512) throw new IOError.INVALID_DATA (_("The file is not a valid AAF document."));
                for (int i = 0; i < magic.length; i++)
                    if (data[i] != magic[i]) throw new IOError.INVALID_DATA (_("The file is not a valid AAF document."));
                int shift = rd16 (data, 30);
                if ((shift != 9 && shift != 12) || rd16 (data, 32) != 6)
                    throw new IOError.NOT_SUPPORTED (_("The AAF document uses an unsupported storage layout."));
                sector_size = 1 << shift;
                int max_sectors = data.length / sector_size + 1;
                var fat_sectors = new Gee.ArrayList<uint32> ();
                for (int i = 0; i < 109; i++) {
                    uint32 s = rd32 (data, 76 + i * 4, FREESECT);
                    if (s < MAXREGSECT) fat_sectors.add (s);
                }
                uint32 next = rd32 (data, 68, ENDOFCHAIN);
                int guard = 0;
                while (next < MAXREGSECT && guard++ < max_sectors) {
                    int64 off = offset (next);
                    int per = sector_size / 4 - 1;
                    for (int i = 0; i < per; i++) {
                        uint32 s = rd32 (data, off + i * 4, FREESECT);
                        if (s < MAXREGSECT) fat_sectors.add (s);
                    }
                    next = rd32 (data, off + per * 4, ENDOFCHAIN);
                }
                if (fat_sectors.size > max_sectors) throw new IOError.INVALID_DATA (_("The AAF document is damaged."));
                int per_sector = sector_size / 4;
                fat = new uint32[fat_sectors.size * per_sector];
                int k = 0;
                foreach (var s in fat_sectors) {
                    int64 off = offset (s);
                    for (int i = 0; i < per_sector; i++) fat[k++] = rd32 (data, off + i * 4, FREESECT);
                }
                var mf = read_regular (rd32 (data, 60, ENDOFCHAIN), -1);
                minifat = new uint32[mf.length / 4];
                for (int i = 0; i < minifat.length; i++) minifat[i] = rd32 (mf, i * 4, FREESECT);
                var dir = read_regular (rd32 (data, 48, ENDOFCHAIN), -1);
                for (int pos = 0; pos + 128 <= dir.length; pos += 128) {
                    var e = new CfbEntry ();
                    int name_len = rd16 (dir, pos + 64);
                    e.name = utf16_text (dir, pos, int.min (64, name_len));
                    e.type = dir[pos + 66];
                    e.left = rd32 (dir, pos + 68, NOSTREAM);
                    e.right = rd32 (dir, pos + 72, NOSTREAM);
                    e.child = rd32 (dir, pos + 76, NOSTREAM);
                    e.clsid = dir[pos + 80:pos + 96];
                    e.start = rd32 (dir, pos + 116, ENDOFCHAIN);
                    e.size = rd64 (dir, pos + 120);
                    if (sector_size == SECTOR) e.size &= 0xFFFFFFFF;
                    if (e.size < 0 || e.size > data.length) e.size = 0;
                    entries.add (e);
                }
                if (entries.size == 0 || entries[0].type != 5) throw new IOError.INVALID_DATA (_("The AAF document has no root storage."));
                mini = read_regular (entries[0].start, entries[0].size);
            }

            int64 offset (uint32 sector) {
                return ((int64) sector + 1) * sector_size;
            }

            Gee.ArrayList<uint32> chain (uint32[] table, uint32 start) {
                var r = new Gee.ArrayList<uint32> ();
                uint32 s = start;
                while ((int64) s < table.length && r.size < table.length) {
                    r.add (s);
                    s = table[s];
                }
                return r;
            }

            uint8[] read_regular (uint32 start, int64 size) {
                var o = new Out ();
                foreach (var s in chain (fat, start)) {
                    int64 off = offset (s);
                    if (off >= data.length) break;
                    int64 end = int64.min (off + sector_size, data.length);
                    o.raw (data[(int) off:(int) end]);
                    if (end - off < sector_size) o.fill ((int) (sector_size - (end - off)), 0);
                    if (size >= 0 && o.size >= size) break;
                }
                var r = o.take ();
                if (size >= 0 && r.length > size) r.resize ((int) size);
                return r;
            }

            public uint8[] stream (int id) {
                if (id < 0 || id >= entries.size) return {};
                var e = entries[id];
                if (e.type != 2 || e.size <= 0) return {};
                if (e.size >= MINI_CUTOFF) return read_regular (e.start, e.size);
                var o = new Out ();
                foreach (var s in chain (minifat, e.start)) {
                    int64 off = (int64) s * 64;
                    if (off + 64 > mini.length) break;
                    o.raw (mini[(int) off:(int) off + 64]);
                    if (o.size >= e.size) break;
                }
                var r = o.take ();
                if (r.length > e.size) r.resize ((int) e.size);
                return r;
            }

            public Gee.HashMap<string, int> children (int id) {
                var r = new Gee.HashMap<string, int> ();
                if (id < 0 || id >= entries.size) return r;
                var stack = new Gee.ArrayList<int> ();
                var seen = new Gee.HashSet<int> ();
                if (entries[id].child < entries.size) stack.add ((int) entries[id].child);
                while (stack.size > 0) {
                    int cur = stack.remove_at (stack.size - 1);
                    if (!seen.add (cur)) continue;
                    var e = entries[cur];
                    r[e.name] = cur;
                    if (e.left < entries.size) stack.add ((int) e.left);
                    if (e.right < entries.size) stack.add ((int) e.right);
                }
                return r;
            }
        }

        class CfbNode {
            public string name;
            public bool is_storage;
            public uint8[] clsid = new uint8[16];
            public uint8[] data = {};
            public Gee.ArrayList<CfbNode> kids = new Gee.ArrayList<CfbNode> ();
            public int id;
            public int left = -1;
            public int right = -1;
            public int child = -1;
            public int depth;
            public bool red;
            public uint32 start = ENDOFCHAIN;
            public int64 size;

            public CfbNode (string name, bool storage) {
                this.name = name;
                is_storage = storage;
            }

            public CfbNode storage (string name) {
                var n = new CfbNode (name, true);
                kids.add (n);
                return n;
            }

            public void stream (string name, uint8[] d) {
                var n = new CfbNode (name, false);
                n.data = d;
                kids.add (n);
            }
        }

        void gather (CfbNode n, Gee.ArrayList<CfbNode> all) throws Error {
            if (utf16_units (n.name) > 31) throw new IOError.INVALID_ARGUMENT (_("An AAF storage name is too long."));
            n.id = all.size;
            all.add (n);
            foreach (var k in n.kids) gather (k, all);
        }

        int balance (Gee.ArrayList<CfbNode> sorted, int lo, int hi, int depth, ref int deepest) {
            if (lo > hi) return -1;
            int mid = (lo + hi) / 2;
            var n = sorted[mid];
            n.depth = depth;
            if (depth > deepest) deepest = depth;
            n.left = balance (sorted, lo, mid - 1, depth + 1, ref deepest);
            n.right = balance (sorted, mid + 1, hi, depth + 1, ref deepest);
            return n.id;
        }

        uint32 alloc (Out body, Gee.ArrayList<uint32> fat, uint8[] d) {
            uint32 start = (uint32) fat.size;
            int n = int.max (1, (d.length + SECTOR - 1) / SECTOR);
            for (int i = 0; i < n; i++) fat.add (i + 1 < n ? start + i + 1 : ENDOFCHAIN);
            body.raw (d);
            body.fill (n * SECTOR - d.length, 0);
            return start;
        }

        void dir_entry (Out o, CfbNode n) {
            var name = utf16z (n.name);
            var block = new uint8[64];
            Memory.copy (block, name, int.min (64, name.length));
            o.raw (block);
            o.u16 (name.length);
            o.u8 (n.id == 0 ? 5 : (n.is_storage ? 1 : 2));
            o.u8 (n.red ? 0 : 1);
            o.u32 (n.left < 0 ? NOSTREAM : n.left);
            o.u32 (n.right < 0 ? NOSTREAM : n.right);
            o.u32 (n.child < 0 ? NOSTREAM : n.child);
            o.raw (n.is_storage ? n.clsid : new uint8[16]);
            o.u32 (0);
            o.fill (16, 0);
            o.u32 (n.is_storage && n.id != 0 ? 0 : n.start);
            o.u32 ((uint32) n.size);
            o.u32 (0);
        }

        void empty_entry (Out o) {
            o.fill (66, 0);
            o.u8 (0);
            o.u8 (0);
            o.u32 (NOSTREAM);
            o.u32 (NOSTREAM);
            o.u32 (NOSTREAM);
            o.fill (16 + 4 + 16 + 4 + 8, 0);
        }

        uint8[] compound (CfbNode root) throws Error {
            var all = new Gee.ArrayList<CfbNode> ();
            gather (root, all);
            foreach (var n in all) {
                if (!n.is_storage || n.kids.size == 0) continue;
                var sorted = new Gee.ArrayList<CfbNode> ();
                sorted.add_all (n.kids);
                sorted.sort ((a, b) => name_order (a.name, b.name));
                for (int i = 1; i < sorted.size; i++)
                    if (name_order (sorted[i - 1].name, sorted[i].name) == 0) throw new IOError.INVALID_ARGUMENT (_("The AAF document has duplicated entries."));
                int deepest = 0;
                n.child = balance (sorted, 0, sorted.size - 1, 0, ref deepest);
                foreach (var k in sorted) k.red = deepest > 0 && k.depth == deepest;
            }
            var body = new Out ();
            var fat = new Gee.ArrayList<uint32> ();
            foreach (var n in all) {
                if (n.is_storage || n.data.length < MINI_CUTOFF) continue;
                n.size = n.data.length;
                n.start = alloc (body, fat, n.data);
            }
            var mini = new Out ();
            var minifat = new Gee.ArrayList<uint32> ();
            foreach (var n in all) {
                if (n.is_storage || n.data.length == 0 || n.data.length >= MINI_CUTOFF) continue;
                n.size = n.data.length;
                n.start = (uint32) minifat.size;
                int count = (n.data.length + 63) / 64;
                for (int k = 0; k < count; k++) minifat.add (k + 1 < count ? n.start + k + 1 : ENDOFCHAIN);
                mini.raw (n.data);
                mini.pad (64);
            }
            root.size = mini.size;
            root.start = mini.size > 0 ? alloc (body, fat, mini.take ()) : ENDOFCHAIN;
            uint32 minifat_start = ENDOFCHAIN;
            int minifat_count = 0;
            if (minifat.size > 0) {
                var mf = new Out ();
                foreach (var v in minifat) mf.u32 (v);
                mf.pad (SECTOR, 0xff);
                minifat_count = mf.size / SECTOR;
                minifat_start = alloc (body, fat, mf.take ());
            }
            var dir = new Out ();
            foreach (var n in all) dir_entry (dir, n);
            while (dir.size % SECTOR != 0) empty_entry (dir);
            uint32 dir_start = alloc (body, fat, dir.take ());
            int used = fat.size;
            int nfat = 0, ndif = 0;
            while (true) {
                int total = used + nfat + ndif;
                int f2 = (total + 127) / 128;
                int d2 = f2 > 109 ? (f2 - 109 + 126) / 127 : 0;
                if (f2 == nfat && d2 == ndif) break;
                nfat = f2;
                ndif = d2;
            }
            for (int i = 0; i < nfat; i++) fat.add (FATSECT);
            for (int i = 0; i < ndif; i++) fat.add (DIFSECT);
            var fo = new Out ();
            foreach (var v in fat) fo.u32 (v);
            while (fo.size < nfat * SECTOR) fo.u32 (FREESECT);
            var dif = new Out ();
            for (int j = 0; j < ndif; j++) {
                for (int k = 0; k < 127; k++) {
                    int idx = 109 + j * 127 + k;
                    dif.u32 (idx < nfat ? (uint32) (used + idx) : FREESECT);
                }
                dif.u32 (j + 1 < ndif ? (uint32) (used + nfat + j + 1) : ENDOFCHAIN);
            }
            var h = new Out ();
            uint8[] magic = { 0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1 };
            h.raw (magic);
            h.raw (auid (FILE_CLASS));
            h.u16 (0x3e);
            h.u16 (3);
            h.u16 (0xfffe);
            h.u16 (9);
            h.u16 (6);
            h.fill (6, 0);
            h.u32 (0);
            h.u32 (nfat);
            h.u32 (dir_start);
            h.u32 (0);
            h.u32 (MINI_CUTOFF);
            h.u32 (minifat_start);
            h.u32 (minifat_count);
            h.u32 (ndif > 0 ? (uint32) (used + nfat) : ENDOFCHAIN);
            h.u32 (ndif);
            for (int i = 0; i < 109; i++) h.u32 (i < nfat ? (uint32) (used + i) : FREESECT);
            h.raw (body.take ());
            h.raw (fo.take ());
            h.raw (dif.take ());
            return h.take ();
        }

        class RProp {
            public int format;
            public uint8[] data;
        }

        class RObj {
            public CfbReader cfb;
            public int id;
            public string klass;
            Gee.HashMap<string, int> kids;
            Gee.HashMap<int, RProp> props = new Gee.HashMap<int, RProp> ();

            public RObj (CfbReader cfb, int id) {
                this.cfb = cfb;
                this.id = id;
                klass = auid_text (cfb.entries[id].clsid, 0);
                kids = cfb.children (id);
                if (kids.has_key ("properties")) parse (cfb.stream (kids["properties"]));
            }

            void parse (uint8[] d) {
                if (d.length < 4 || d[0] != 0x4c) return;
                int count = rd16 (d, 2);
                int off = 4 + count * 6;
                for (int i = 0; i < count; i++) {
                    int pid = rd16 (d, 4 + i * 6);
                    int format = rd16 (d, 6 + i * 6);
                    int size = rd16 (d, 8 + i * 6);
                    if (off + size > d.length) break;
                    var p = new RProp ();
                    p.format = format;
                    p.data = d[off:off + size];
                    props[pid] = p;
                    off += size;
                }
            }

            public bool has (int pid) {
                return props.has_key (pid);
            }

            public uint8[] raw (int pid) {
                var p = props[pid];
                return p != null ? p.data : new uint8[0];
            }

            public string text (int pid, string fallback = "") {
                var p = props[pid];
                if (p == null || p.format != SF_DATA) return fallback;
                return utf16_text (p.data, 0, p.data.length);
            }

            public int64 number (int pid, int64 fallback = 0) {
                var p = props[pid];
                if (p == null) return fallback;
                if (p.data.length >= 8) return rd64 (p.data, 0);
                if (p.data.length >= 4) return (int32) rd32 (p.data, 0);
                if (p.data.length >= 2) return (int16) rd16 (p.data, 0);
                return fallback;
            }

            public bool rational (int pid, out int n, out int d) {
                var p = props[pid];
                n = 0;
                d = 0;
                if (p == null || p.data.length < 8) return false;
                n = (int32) rd32 (p.data, 0);
                d = (int32) rd32 (p.data, 4);
                return n > 0 && d > 0;
            }

            public string weak_key (int pid) {
                var p = props[pid];
                if (p == null || p.format != SF_WEAK || p.data.length < 5) return "";
                int size = p.data[4];
                if (size == 16) return auid_text (p.data, 5);
                if (5 + size > p.data.length) return "";
                return hex_of (p.data[5:5 + size]);
            }

            public string mob_id (int pid) {
                var p = props[pid];
                if (p == null || p.data.length != 32) return "";
                return hex_of (p.data);
            }

            public RObj? strong (int pid) {
                var p = props[pid];
                if (p == null || p.format != SF_STRONG) return null;
                string name = utf16_text (p.data, 0, p.data.length);
                if (!kids.has_key (name)) return null;
                return new RObj (cfb, kids[name]);
            }

            public Gee.ArrayList<RObj> list (int pid) {
                var r = new Gee.ArrayList<RObj> ();
                var p = props[pid];
                if (p == null || (p.format != SF_VECTOR && p.format != SF_SET)) return r;
                string name = utf16_text (p.data, 0, p.data.length);
                string index = name + " index";
                if (!kids.has_key (index)) return r;
                var d = cfb.stream (kids[index]);
                uint32 count = rd32 (d, 0);
                var keys = new Gee.ArrayList<uint32> ();
                if (p.format == SF_VECTOR) {
                    for (uint32 i = 0; i < count && 12 + (int64) i * 4 + 4 <= d.length; i++) keys.add (rd32 (d, 12 + i * 4));
                } else {
                    int key_size = d.length > 14 ? d[14] : 0;
                    int stride = 8 + key_size;
                    for (uint32 i = 0; i < count && 15 + (int64) i * stride + stride <= d.length; i++) keys.add (rd32 (d, 15 + (int64) i * stride));
                }
                foreach (var k in keys) {
                    string child = "%s{%x}".printf (name, k);
                    if (kids.has_key (child)) r.add (new RObj (cfb, kids[child]));
                }
                return r;
            }
        }

        class Fill {
            public Sequence s;
            public Track t;
            public int n;
            public int d;
            public int64 cursor;
            public Clip? prev;
            public int64 pending = -1;
            public int64 cut;

            public int64 at (int64 units) {
                return from_units (units, n, d);
            }
        }

        class Reader {
            CfbReader cfb;
            File? origin;
            Project p;
            Gee.HashMap<string, RObj> mobs = new Gee.HashMap<string, RObj> ();
            Gee.HashMap<string, Sequence> comp_seqs = new Gee.HashMap<string, Sequence> ();
            Gee.HashMap<string, string> parents = new Gee.HashMap<string, string> ();
            Gee.HashSet<string> known = new Gee.HashSet<string> ();

            public Reader (uint8[] data, File? origin) throws Error {
                cfb = new CfbReader (data);
                this.origin = origin;
                string[] classes = { C_COMPOSITION, C_MASTER, C_SOURCE, C_TIMELINE_SLOT, C_EVENT_SLOT, C_SEQUENCE, C_SOURCE_CLIP,
                    C_FILLER, C_TRANSITION, C_OPERATION_GROUP, C_SELECTOR, C_ESSENCE_GROUP, C_COMMENT_MARKER, C_DESCRIPTIVE_MARKER,
                    C_NETWORK_LOCATOR };
                foreach (var c in classes) known.add (c);
            }

            string kind (string klass) {
                string k = klass;
                for (int i = 0; i < 16; i++) {
                    if (known.contains (k)) return k;
                    if (!parents.has_key (k)) break;
                    k = parents[k];
                }
                return klass;
            }

            void load_metadict (RObj? md) {
                if (md == null) return;
                foreach (var cd in md.list (0x0003)) {
                    string id = auid_text (cd.raw (0x0005), 0);
                    string parent = cd.weak_key (0x0008);
                    if (id != "" && parent != "" && id != parent) parents[id] = parent;
                }
            }

            public Project run () throws Error {
                var root = new RObj (cfb, 0);
                load_metadict (root.strong (0x0001));
                var header = root.strong (0x0002);
                var content = header != null ? header.strong (0x3b03) : null;
                if (content == null) throw new IOError.INVALID_DATA (_("The AAF document has no content."));
                var comps = new Gee.ArrayList<RObj> ();
                foreach (var m in content.list (0x1901)) {
                    string id = m.mob_id (0x4401);
                    if (id == "") continue;
                    mobs[id] = m;
                    if (kind (m.klass) == C_COMPOSITION) comps.add (m);
                }
                if (comps.size == 0) throw new IOError.INVALID_DATA (_("The AAF document has no timeline."));
                var used = new Gee.HashSet<string> ();
                foreach (var c in comps) foreach (var slot in c.list (0x4403)) collect (slot.strong (0x4803), used, 0);
                var order = new Gee.ArrayList<RObj> ();
                foreach (var c in comps) if (!used.contains (c.mob_id (0x4401))) order.add (c);
                foreach (var c in comps) if (!order.contains (c)) order.add (c);
                p = InterchangeFormats.empty_project (_("AAF Timeline"));
                p.sequences.clear ();
                foreach (var c in order) {
                    var s = new Sequence (c.text (0x4402, _("AAF Timeline")));
                    if (s.name == "") s.name = _("AAF Timeline");
                    comp_seqs[c.mob_id (0x4401)] = s;
                    p.sequences.add (s);
                }
                foreach (var c in order) fill (c, comp_seqs[c.mob_id (0x4401)]);
                p.active = p.sequences[0].id;
                return p;
            }

            void collect (RObj? seg, Gee.HashSet<string> used, int depth) {
                if (seg == null || depth > 32) return;
                string k = kind (seg.klass);
                if (k == C_SOURCE_CLIP) {
                    string id = seg.mob_id (0x1101);
                    if (id != "") used.add (id);
                } else if (k == C_SEQUENCE) {
                    foreach (var c in seg.list (0x1001)) collect (c, used, depth + 1);
                } else if (k == C_OPERATION_GROUP) {
                    foreach (var c in seg.list (0x0b02)) collect (c, used, depth + 1);
                } else if (k == C_SELECTOR) {
                    collect (seg.strong (0x0f01), used, depth + 1);
                } else if (k == C_ESSENCE_GROUP) {
                    foreach (var c in seg.list (0x0501)) collect (c, used, depth + 1);
                }
            }

            RObj? inner (RObj seg) {
                string k = kind (seg.klass);
                if (k == C_OPERATION_GROUP) {
                    var inputs = seg.list (0x0b02);
                    return inputs.size > 0 ? inputs[0] : null;
                }
                if (k == C_SELECTOR) return seg.strong (0x0f01);
                if (k == C_ESSENCE_GROUP) {
                    var choices = seg.list (0x0501);
                    return choices.size > 0 ? choices[0] : null;
                }
                return null;
            }

            void slot_rate (RObj slot, out int n, out int d) {
                if (!slot.rational (0x4b01, out n, out d) && !slot.rational (0x4901, out n, out d)) {
                    n = 25;
                    d = 1;
                }
            }

            void apply_rate (Sequence s, int n, int d) {
                double r = (double) n / d;
                if ((r - 29.97).abs () < 0.01) {
                    s.fps_n = 30000;
                    s.fps_d = 1001;
                } else if ((r - 23.976).abs () < 0.01) {
                    s.fps_n = 24000;
                    s.fps_d = 1001;
                } else if ((r - 59.94).abs () < 0.01) {
                    s.fps_n = 60000;
                    s.fps_d = 1001;
                } else if (n % d == 0) {
                    s.fps_n = n / d;
                    s.fps_d = 1;
                } else {
                    s.fps_n = n;
                    s.fps_d = d;
                }
            }

            bool is_picture (string dd) {
                return dd == DD_PICTURE || dd == DD_LEGACY_PICTURE || dd == DD_PICTURE_MATTE;
            }

            bool is_sound (string dd) {
                return dd == DD_SOUND || dd == DD_LEGACY_SOUND;
            }

            void fill (RObj comp, Sequence s) {
                var slots = comp.list (0x4403);
                bool rated = false;
                foreach (var slot in slots) {
                    if (kind (slot.klass) != C_TIMELINE_SLOT) continue;
                    var seg = slot.strong (0x4803);
                    if (seg == null || !is_picture (seg.weak_key (0x0201))) continue;
                    int n, d;
                    slot_rate (slot, out n, out d);
                    apply_rate (s, n, d);
                    rated = true;
                    break;
                }
                var video = new Gee.ArrayList<Track> ();
                var audio = new Gee.ArrayList<Track> ();
                foreach (var slot in slots) {
                    string k = kind (slot.klass);
                    var seg = slot.strong (0x4803);
                    if (seg == null) continue;
                    int n, d;
                    slot_rate (slot, out n, out d);
                    if (k == C_EVENT_SLOT) {
                        read_markers (seg, s, n, d, 0);
                        continue;
                    }
                    if (k != C_TIMELINE_SLOT) continue;
                    string dd = seg.weak_key (0x0201);
                    bool picture = is_picture (dd);
                    if (!picture && !is_sound (dd)) continue;
                    if (!rated && n <= 240 * d) {
                        apply_rate (s, n, d);
                        rated = true;
                    }
                    var list = picture ? video : audio;
                    string name = slot.text (0x4802);
                    if (name == "") name = "%s%d".printf (picture ? "V" : "A", list.size + 1);
                    var t = new Track (name, picture ? TrackKind.VIDEO : TrackKind.AUDIO);
                    list.add (t);
                    var f = new Fill ();
                    f.s = s;
                    f.t = t;
                    f.n = n;
                    f.d = d;
                    emit (seg, f, 0);
                }
                s.tracks.add_all (video);
                s.tracks.add_all (audio);
                InterchangeFormats.tidy (s);
                InterchangeFormats.link_pairs (s);
            }

            void read_markers (RObj seg, Sequence s, int n, int d, int depth) {
                if (depth > 8) return;
                string k = kind (seg.klass);
                if (k == C_SEQUENCE) {
                    foreach (var c in seg.list (0x1001)) read_markers (c, s, n, d, depth + 1);
                    return;
                }
                if (k != C_COMMENT_MARKER && k != C_DESCRIPTIVE_MARKER) return;
                var m = new Marker (from_units (seg.number (0x0601), n, d), seg.text (0x0602));
                m.duration = from_units (int64.max (0, seg.number (0x0202)), n, d);
                s.markers.add (m);
            }

            void emit (RObj? seg, Fill f, int depth) {
                if (seg == null || depth > 32) return;
                string k = kind (seg.klass);
                int64 len = int64.max (0, seg.number (0x0202));
                if (k == C_SEQUENCE) {
                    foreach (var c in seg.list (0x1001)) emit (c, f, depth + 1);
                    return;
                }
                if (k == C_TRANSITION) {
                    f.cursor -= len;
                    int64 cut = seg.number (0x1802, len / 2).clamp (0, len);
                    if (f.prev != null) {
                        int64 x = f.at (f.cursor + cut);
                        if (x > f.prev.position) f.prev.duration = x - f.prev.position;
                        f.pending = len;
                        f.cut = cut;
                    }
                    return;
                }
                if (k == C_OPERATION_GROUP || k == C_SELECTOR || k == C_ESSENCE_GROUP) {
                    int64 before = f.cursor;
                    var child = inner (seg);
                    if (child != null) emit (child, f, depth + 1);
                    if (child == null || seg.has (0x0202)) {
                        f.cursor = before + len;
                        if (f.prev != null && f.prev.position >= f.at (before)) {
                            int64 end = f.at (before + len);
                            if (end > f.prev.position) f.prev.duration = end - f.prev.position;
                        }
                    }
                    return;
                }
                if (k == C_SOURCE_CLIP) {
                    var c = make_clip (seg, depth);
                    if (c != null) {
                        place (c, f, len);
                        return;
                    }
                }
                f.cursor += len;
                f.prev = null;
                f.pending = -1;
            }

            void place (Clip c, Fill f, int64 len) {
                c.track = f.t.id;
                c.position = f.at (f.cursor);
                c.duration = f.at (f.cursor + len) - c.position;
                if (f.pending >= 0 && f.prev != null) {
                    int64 x = f.at (f.cursor + f.cut);
                    int64 delta = x - c.position;
                    if (delta < c.duration) {
                        c.position = x;
                        c.in_point += delta;
                        c.duration -= delta;
                        var tr = new Transition ();
                        tr.track = f.t.id;
                        tr.from_clip = f.prev.id;
                        tr.to_clip = c.id;
                        tr.kind = "dissolve";
                        tr.duration = f.at (f.cursor + f.pending) - f.at (f.cursor);
                        tr.align = f.cut == 0 ? 1 : (f.cut == f.pending ? -1 : 0);
                        if (tr.duration > 0) f.s.transitions.add (tr);
                    }
                }
                if (c.duration <= 0) {
                    f.cursor += len;
                    f.prev = null;
                    f.pending = -1;
                    return;
                }
                f.s.clips.add (c);
                f.prev = c;
                f.pending = -1;
                f.cursor += len;
            }

            RObj? slot_of (RObj mob, uint32 id) {
                foreach (var slot in mob.list (0x4403)) if ((uint32) slot.number (0x4801, -1) == id) return slot;
                return null;
            }

            RObj? clip_at (RObj? seg, int64 at, int n, int d, out int64 into, int depth) {
                into = 0;
                if (seg == null || depth > 32) return null;
                string k = kind (seg.klass);
                if (k == C_SOURCE_CLIP) {
                    into = at;
                    return seg;
                }
                if (k == C_SEQUENCE) {
                    int64 pos = 0;
                    foreach (var c in seg.list (0x1001)) {
                        int64 l = int64.max (0, c.number (0x0202));
                        if (kind (c.klass) == C_TRANSITION) {
                            pos -= l;
                            continue;
                        }
                        int64 b = from_units (pos, n, d), e = from_units (pos + l, n, d);
                        if (at >= b && at < e) return clip_at (c, at - b, n, d, out into, depth + 1);
                        pos += l;
                    }
                    return null;
                }
                return clip_at (inner (seg), at, n, d, out into, depth + 1);
            }

            string locator (RObj mob) {
                var desc = mob.strong (0x4701);
                if (desc == null) return "";
                foreach (var loc in desc.list (0x2f01)) {
                    if (kind (loc.klass) != C_NETWORK_LOCATOR) continue;
                    string url = loc.text (0x4001).strip ();
                    if (url != "") return url;
                }
                return "";
            }

            Clip? make_clip (RObj sc, int depth) {
                string id = sc.mob_id (0x1101);
                if (id == "" || !mobs.has_key (id)) return null;
                uint32 slot_id = (uint32) sc.number (0x1102);
                int64 start = sc.number (0x1201);
                var first = mobs[id];
                if (comp_seqs.has_key (id)) {
                    var slot = slot_of (first, slot_id);
                    int n = 25, d = 1;
                    if (slot != null) slot_rate (slot, out n, out d);
                    var c = new Clip ();
                    c.kind = ClipKind.SEQUENCE;
                    c.sequence = comp_seqs[id].id;
                    c.in_point = int64.max (0, from_units (start, n, d));
                    return c;
                }
                string url = "", name = "";
                int64 offset = 0, length = 0, extra = 0;
                RObj? cur = first;
                uint32 sid = slot_id;
                for (int hop = 0; hop < 12 && cur != null; hop++) {
                    string mob_name = cur.text (0x4402);
                    if (name == "" && mob_name != "") name = mob_name;
                    var slot = slot_of (cur, sid);
                    if (slot == null) break;
                    int n, d;
                    slot_rate (slot, out n, out d);
                    int64 at = from_units (start, n, d) + extra;
                    offset = at;
                    var seg = slot.strong (0x4803);
                    if (seg != null) length = from_units (int64.max (0, seg.number (0x0202)), n, d);
                    string loc = locator (cur);
                    if (loc != "") {
                        url = loc;
                        break;
                    }
                    int64 into;
                    var next = clip_at (seg, at, n, d, out into, depth + 1);
                    if (next == null) break;
                    string next_id = next.mob_id (0x1101);
                    if (next_id == "" || !mobs.has_key (next_id)) break;
                    cur = mobs[next_id];
                    sid = (uint32) next.number (0x1102);
                    start = next.number (0x1201);
                    extra = into;
                }
                if (url == "" && name == "") name = _("Media");
                var m = InterchangeFormats.find_or_add (p, url, name, length, origin);
                var c = new Clip ();
                c.media = m.id;
                c.in_point = int64.max (0, offset);
                return c;
            }
        }

        class WProp {
            public uint16 pid;
            public uint8 format;
            public uint8[] data = {};
            public string name = "";
            public WObj? child;
            public Gee.ArrayList<WObj>? items;
            public uint16 key_pid;
        }

        class WObj {
            public string klass;
            public uint8[] key = {};
            public Gee.ArrayList<WProp> props = new Gee.ArrayList<WProp> ();

            public WObj (string klass) {
                this.klass = klass;
            }

            WProp add (uint16 pid, uint8 format) {
                var p = new WProp ();
                p.pid = pid;
                p.format = format;
                props.add (p);
                return p;
            }

            public WProp put (uint16 pid, uint8[] data) {
                var p = add (pid, SF_DATA);
                p.data = data;
                return p;
            }

            public void text (uint16 pid, string value) {
                put (pid, utf16z (value));
            }

            public WProp length (uint16 pid, int64 value) {
                var o = new Out ();
                o.i64 (value);
                return put (pid, o.take ());
            }

            public void word (uint16 pid, uint32 value) {
                var o = new Out ();
                o.u32 (value);
                put (pid, o.take ());
            }

            public void rate (uint16 pid, int n, int d) {
                var o = new Out ();
                o.u32 ((uint32) n);
                o.u32 ((uint32) d);
                put (pid, o.take ());
            }

            public void stamp (uint16 pid, DateTime t) {
                var o = new Out ();
                o.u16 (t.get_year ());
                o.u8 ((uint8) t.get_month ());
                o.u8 ((uint8) t.get_day_of_month ());
                o.u8 ((uint8) t.get_hour ());
                o.u8 ((uint8) t.get_minute ());
                o.u8 ((uint8) t.get_second ());
                o.u8 (0);
                put (pid, o.take ());
            }

            public void link (uint16 pid, uint16 table, uint16 key_pid, uint8[] key) {
                var o = new Out ();
                o.u16 (table);
                o.u16 (key_pid);
                o.u8 ((uint8) key.length);
                o.raw (key);
                add (pid, SF_WEAK).data = o.take ();
            }

            public void strong (uint16 pid, string name, WObj child) {
                var p = add (pid, SF_STRONG);
                p.name = name;
                p.child = child;
            }

            public void vector (uint16 pid, string name, Gee.ArrayList<WObj> items) {
                var p = add (pid, SF_VECTOR);
                p.name = name;
                p.items = items;
            }

            public void keyed (uint16 pid, string name, uint16 key_pid, Gee.ArrayList<WObj> items) {
                var p = add (pid, SF_SET);
                p.name = name;
                p.items = items;
                p.key_pid = key_pid;
            }
        }

        void store (WObj o, CfbNode dir) throws Error {
            dir.clsid = auid (o.klass);
            var head = new Out ();
            var body = new Out ();
            head.u8 (0x4c);
            head.u8 (32);
            head.u16 (o.props.size);
            foreach (var p in o.props) {
                uint8[] data = p.data;
                if (p.format == SF_STRONG) {
                    string n = mangle (p.name, p.pid, 32);
                    data = utf16z (n);
                    store (p.child, dir.storage (n));
                } else if (p.format == SF_VECTOR || p.format == SF_SET) {
                    string n = mangle (p.name, p.pid, 22);
                    data = utf16z (n);
                    var idx = new Out ();
                    idx.u32 (p.items.size);
                    idx.u32 (p.items.size);
                    idx.u32 (FREESECT);
                    if (p.format == SF_SET) {
                        idx.u16 (p.key_pid);
                        idx.u8 ((uint8) (p.items.size > 0 ? p.items[0].key.length : 16));
                    }
                    for (int i = 0; i < p.items.size; i++) {
                        idx.u32 (i);
                        if (p.format == SF_SET) {
                            idx.u32 (1);
                            idx.raw (p.items[i].key);
                        }
                        store (p.items[i], dir.storage ("%s{%x}".printf (n, i)));
                    }
                    dir.stream (n + " index", idx.take ());
                }
                if (data.length > 0xFFFF) throw new IOError.INVALID_ARGUMENT (_("An AAF property is too large."));
                head.u16 (p.pid);
                head.u16 (p.format);
                head.u16 (data.length);
                body.raw (data);
            }
            head.raw (body.take ());
            dir.stream ("properties", head.take ());
        }

        Gee.ArrayList<WObj> items_of (WObj first, WObj? second = null) {
            var r = new Gee.ArrayList<WObj> ();
            r.add (first);
            if (second != null) r.add (second);
            return r;
        }

        class MobRef {
            public uint8[] id;
            public uint32 vslot;
            public uint32 aslot;
            public int n;
            public int d;
            public int64 base_length;
            public int64 extent;
            public Gee.ArrayList<WProp> lengths = new Gee.ArrayList<WProp> ();
        }

        class Piece {
            public Clip clip;
            public MobRef r;
            public uint32 slot;
            public int64 pos;
            public int64 end;
            public int64 src;
            public int64 room = -1;
            public int64 lead;
            public int64 tail;
            public int64 trans;
            public int64 busy;
        }

        class Writer {
            Project p;
            int mn;
            int md;
            DateTime now = new DateTime.now_utc ();
            Gee.ArrayList<WObj> mobs = new Gee.ArrayList<WObj> ();
            Gee.HashMap<string, MobRef> masters = new Gee.HashMap<string, MobRef> ();
            Gee.HashMap<string, MobRef> comps = new Gee.HashMap<string, MobRef> ();
            Gee.HashSet<string> busy = new Gee.HashSet<string> ();
            Gee.HashMap<string, int> usage = new Gee.HashMap<string, int> ();
            Gee.HashSet<string> scanned = new Gee.HashSet<string> ();

            public Writer (Project p, Sequence s) {
                this.p = p;
                mn = s.fps_n;
                md = s.fps_d;
            }

            void scan (Sequence s) {
                if (!scanned.add (s.id)) return;
                foreach (var c in s.clips) {
                    var t = s.track (c.track);
                    if (t == null) continue;
                    if (c.kind == ClipKind.MEDIA) {
                        int bit = t.kind == TrackKind.AUDIO ? 2 : (t.kind == TrackKind.VIDEO ? 1 : 0);
                        usage[c.media] = (usage.has_key (c.media) ? usage[c.media] : 0) | bit;
                    } else if (c.kind == ClipKind.SEQUENCE) {
                        var inner = p.find_sequence (c.sequence);
                        if (inner != null) scan (inner);
                    }
                }
            }

            WObj mob (string klass, uint8[] id, string name) {
                var m = new WObj (klass);
                m.key = id;
                m.put (0x4401, id);
                m.text (0x4402, name);
                m.stamp (0x4404, now);
                m.stamp (0x4405, now);
                return m;
            }

            WObj slot (uint32 id, string name, int n, int d, WObj segment, uint32 track = 0) {
                var s = new WObj (C_TIMELINE_SLOT);
                s.word (0x4801, id);
                if (name != "") s.text (0x4802, name);
                s.strong (0x4803, "Segment", segment);
                if (track > 0) s.word (0x4804, track);
                s.rate (0x4b01, n, d);
                s.length (0x4b02, 0);
                return s;
            }

            WObj component (string klass, string dd, int64 len) {
                var c = new WObj (klass);
                c.link (0x0201, TABLE_DATADEFS, 0x1b01, auid (dd));
                c.length (0x0202, len);
                return c;
            }

            WObj source_clip (string dd, int64 len, uint8[] id, uint32 slot_id, int64 start) {
                var c = component (C_SOURCE_CLIP, dd, len);
                c.put (0x1101, id);
                c.word (0x1102, slot_id);
                c.length (0x1201, start);
                return c;
            }

            WObj transition (string dd, bool video, int64 len, int64 cut) {
                var og = component (C_OPERATION_GROUP, dd, len);
                og.link (0x0b01, TABLE_OPDEFS, 0x1b01, auid (video ? OP_VIDEO_DISSOLVE : OP_AUDIO_DISSOLVE));
                var t = component (C_TRANSITION, dd, len);
                t.strong (0x1801, "OperationGroup", og);
                t.length (0x1802, cut);
                return t;
            }

            WObj sequence (string dd, int64 len, Gee.ArrayList<WObj> items) {
                var s = component (C_SEQUENCE, dd, len);
                s.vector (0x1001, "Components", items);
                return s;
            }

            MobRef master_for (MediaItem m) {
                if (masters.has_key (m.id)) return masters[m.id];
                var r = new MobRef ();
                r.n = mn;
                r.d = md;
                int use = usage.has_key (m.id) ? usage[m.id] : 0;
                bool vid = m.has_video || (use & 1) != 0;
                bool aud = m.has_audio || (use & 2) != 0;
                if (!vid && !aud) vid = true;
                r.base_length = m.still || m.duration <= 0 ? 0 : to_units (m.duration, mn, md);
                var src_id = new_mob_id ();
                r.id = new_mob_id ();
                var src = mob (C_SOURCE, src_id, m.name);
                var master = mob (C_MASTER, r.id, m.name);
                var desc = new WObj (C_IMPORT_DESCRIPTOR);
                var loc = new WObj (C_NETWORK_LOCATOR);
                loc.text (0x4001, m.uri);
                desc.vector (0x2f01, "Locator", items_of (loc));
                src.strong (0x4701, "EssenceDescription", desc);
                var src_slots = new Gee.ArrayList<WObj> ();
                var master_slots = new Gee.ArrayList<WObj> ();
                uint32 sid = 1;
                uint8[] none = new uint8[32];
                foreach (var dd in new string[] { DD_PICTURE, DD_SOUND }) {
                    if (dd == DD_PICTURE ? !vid : !aud) continue;
                    var own = source_clip (dd, r.base_length, none, 0, 0);
                    r.lengths.add (own.props[1]);
                    src_slots.add (slot (sid, "", mn, md, own));
                    var link = source_clip (dd, r.base_length, src_id, sid, 0);
                    r.lengths.add (link.props[1]);
                    master_slots.add (slot (sid, "", mn, md, link));
                    if (dd == DD_PICTURE) r.vslot = sid;
                    else r.aslot = sid;
                    sid++;
                }
                src.vector (0x4403, "Slots", src_slots);
                master.vector (0x4403, "Slots", master_slots);
                mobs.add (src);
                mobs.add (master);
                masters[m.id] = r;
                return r;
            }

            public MobRef? comp_for (Sequence s) {
                if (comps.has_key (s.id)) return comps[s.id];
                if (!busy.add (s.id)) return null;
                var r = new MobRef ();
                r.id = new_mob_id ();
                r.n = s.fps_n;
                r.d = s.fps_d;
                var c = mob (C_COMPOSITION, r.id, s.name);
                var slots = new Gee.ArrayList<WObj> ();
                uint32 sid = 1;
                int vn = 0, an = 0;
                foreach (var kind in new TrackKind[] { TrackKind.VIDEO, TrackKind.AUDIO }) {
                    foreach (var t in s.tracks_of (kind)) {
                        bool video = kind == TrackKind.VIDEO;
                        var seq = track_sequence (s, t, video);
                        slots.add (slot (sid, t.name, s.fps_n, s.fps_d, seq, video ? ++vn : ++an));
                        if (video && r.vslot == 0) r.vslot = sid;
                        if (!video && r.aslot == 0) r.aslot = sid;
                        sid++;
                    }
                }
                if (s.markers.size > 0) {
                    var marks = new Gee.ArrayList<WObj> ();
                    int64 last = 0;
                    var sorted = new Gee.ArrayList<Marker> ();
                    sorted.add_all (s.markers);
                    sorted.sort ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
                    foreach (var m in sorted) {
                        int64 pos = to_units (m.time, s.fps_n, s.fps_d);
                        int64 len = to_units (m.duration, s.fps_n, s.fps_d);
                        var e = component (C_COMMENT_MARKER, DD_DESCRIPTIVE, len);
                        e.length (0x0601, pos);
                        e.text (0x0602, m.name);
                        marks.add (e);
                        last = int64.max (last, pos + len);
                    }
                    var ev = new WObj (C_EVENT_SLOT);
                    ev.word (0x4801, sid);
                    ev.text (0x4802, _("Markers"));
                    ev.strong (0x4803, "Segment", sequence (DD_DESCRIPTIVE, last, marks));
                    ev.rate (0x4901, s.fps_n, s.fps_d);
                    slots.add (ev);
                }
                c.vector (0x4403, "Slots", slots);
                mobs.add (c);
                busy.remove (s.id);
                comps[s.id] = r;
                return r;
            }

            WObj track_sequence (Sequence s, Track t, bool video) {
                string dd = video ? DD_PICTURE : DD_SOUND;
                int n = s.fps_n, d = s.fps_d;
                var pieces = new Gee.ArrayList<Piece> ();
                int64 last = 0;
                foreach (var c in s.on_track (t.id)) {
                    MobRef? r = null;
                    int64 avail = -1;
                    if (c.kind == ClipKind.MEDIA) {
                        var m = p.find_media (c.media);
                        if (m != null && m.kind == "file") {
                            r = master_for (m);
                            if (!m.still && m.duration > 0) avail = m.duration;
                        }
                    } else if (c.kind == ClipKind.SEQUENCE) {
                        var inner = p.find_sequence (c.sequence);
                        if (inner != null) {
                            r = comp_for (inner);
                            avail = inner.duration;
                        }
                    }
                    if (r == null) continue;
                    uint32 slot_id = video ? r.vslot : r.aslot;
                    if (slot_id == 0) continue;
                    var pc = new Piece ();
                    pc.clip = c;
                    pc.r = r;
                    pc.slot = slot_id;
                    pc.pos = int64.max (to_units (c.position, n, d), last);
                    pc.end = to_units (c.end, n, d);
                    if (pc.end <= pc.pos) continue;
                    pc.src = int64.max (0, c.in_point + from_units (pc.pos, n, d) - c.position);
                    if (avail >= 0) pc.room = int64.max (0, to_units (avail - pc.src - from_units (pc.end, n, d) + from_units (pc.pos, n, d), n, d));
                    pc.busy = pc.pos;
                    pieces.add (pc);
                    last = pc.end;
                }
                for (int i = 1; i < pieces.size; i++) {
                    var a = pieces[i - 1];
                    var b = pieces[i];
                    if (a.end != b.pos) continue;
                    var tr = s.transition_between (a.clip.id, b.clip.id);
                    if (tr == null) continue;
                    int64 start = to_units (tr.start_at (b.clip.position), n, d);
                    int64 len = to_units (tr.duration, n, d);
                    int64 lead = b.pos - start, tail = len - lead;
                    if (len <= 0 || lead < 0 || tail < 0 || start < a.busy || tail > b.end - b.pos) continue;
                    if (from_units (lead, n, d) > b.src + Tc.SECOND / 1000) continue;
                    if (a.room >= 0 && tail > a.room) continue;
                    b.lead = lead;
                    b.trans = len;
                    b.busy = b.pos + tail;
                    a.tail = tail;
                }
                var items = new Gee.ArrayList<WObj> ();
                int64 cursor = 0;
                foreach (var pc in pieces) {
                    if (pc.trans > 0) {
                        items.add (transition (dd, video, pc.trans, pc.lead));
                        cursor -= pc.trans;
                    } else if (pc.pos > cursor) {
                        items.add (component (C_FILLER, dd, pc.pos - cursor));
                        cursor = pc.pos;
                    }
                    int64 begin = pc.pos - pc.lead;
                    int64 len = pc.end + pc.tail - begin;
                    int64 start = int64.max (0, to_units (pc.src - from_units (pc.lead, n, d), pc.r.n, pc.r.d));
                    items.add (source_clip (dd, len, pc.r.id, pc.slot, start));
                    pc.r.extent = int64.max (pc.r.extent, start + to_units (from_units (len, n, d), pc.r.n, pc.r.d));
                    cursor = begin + len;
                }
                return sequence (dd, cursor, items);
            }

            WObj definition (string klass, string id, string name, string description) {
                var o = new WObj (klass);
                o.key = auid (id);
                o.put (0x1b01, auid (id));
                o.text (0x1b02, name);
                o.text (0x1b03, description);
                return o;
            }

            WObj dictionary () {
                var dict = new WObj (C_DICTIONARY);
                var datadefs = new Gee.ArrayList<WObj> ();
                datadefs.add (definition (C_DATADEF, DD_PICTURE, "DataDef_Picture", "Picture data"));
                datadefs.add (definition (C_DATADEF, DD_SOUND, "DataDef_Sound", "Sound data"));
                datadefs.add (definition (C_DATADEF, DD_DESCRIPTIVE, "DataDef_DescriptiveMetadata", "Descriptive metadata"));
                dict.keyed (0x2605, "DataDefinitions", 0x1b01, datadefs);
                var opdefs = new Gee.ArrayList<WObj> ();
                var vd = definition (C_OPDEF, OP_VIDEO_DISSOLVE, "VideoDissolve_2", "Video Dissolve");
                vd.link (0x1e01, TABLE_DATADEFS, 0x1b01, auid (DD_PICTURE));
                vd.word (0x1e07, 2);
                opdefs.add (vd);
                var ad = definition (C_OPDEF, OP_AUDIO_DISSOLVE, "MonoAudioDissolve", "Mono Audio Dissolve");
                ad.link (0x1e01, TABLE_DATADEFS, 0x1b01, auid (DD_SOUND));
                ad.word (0x1e07, 2);
                opdefs.add (ad);
                dict.keyed (0x2603, "OperationDefinitions", 0x1b01, opdefs);
                return dict;
            }

            public uint8[] build (Sequence s) throws Error {
                scan (s);
                comp_for (s);
                foreach (var r in masters.values) {
                    int64 len = int64.max (r.base_length, r.extent);
                    var o = new Out ();
                    o.i64 (len);
                    var data = o.take ();
                    foreach (var prop in r.lengths) prop.data = data;
                }
                var content = new WObj (C_CONTENT);
                content.keyed (0x1901, "Mobs", 0x4401, mobs);
                var ident = new WObj (C_IDENTIFICATION);
                ident.text (0x3c01, "Singularity");
                ident.text (0x3c02, "Montage");
                ident.text (0x3c04, "1.0");
                ident.put (0x3c05, auid (PRODUCT_ID));
                ident.stamp (0x3c06, now);
                ident.text (0x3c08, "Linux");
                ident.put (0x3c09, auid (Uuid.string_random ()));
                var header = new WObj (C_HEADER);
                var bo = new Out ();
                bo.u16 (0x4949);
                header.put (0x3b01, bo.take ());
                header.stamp (0x3b02, now);
                header.strong (0x3b03, "Content", content);
                header.strong (0x3b04, "Dictionary", dictionary ());
                uint8[] version = { 1, 2 };
                header.put (0x3b05, version);
                header.vector (0x3b06, "IdentificationList", items_of (ident));
                header.word (0x3b07, 1);
                header.put (0x3b09, auid (EDIT_PROTOCOL));
                var root = new WObj (ROOT_CLASS);
                var meta = new WObj (C_META);
                meta.keyed (0x0003, "ClassDefinitions", 0x0005, new Gee.ArrayList<WObj> ());
                meta.keyed (0x0004, "TypeDefinitions", 0x0005, new Gee.ArrayList<WObj> ());
                root.strong (0x0001, "MetaDictionary", meta);
                root.strong (0x0002, "Header", header);
                var tree = new CfbNode ("Root Entry", true);
                store (root, tree);
                var refs = new Out ();
                uint16[] datadefs = { 0x0002, 0x3b04, 0x2605, 0 };
                uint16[] opdefs = { 0x0002, 0x3b04, 0x2603, 0 };
                refs.u8 (0x4c);
                refs.u16 (2);
                refs.u32 (datadefs.length + opdefs.length);
                foreach (var v in datadefs) refs.u16 (v);
                foreach (var v in opdefs) refs.u16 (v);
                tree.stream ("referenced properties", refs.take ());
                return compound (tree);
            }
        }

        public Project read (uint8[] data, File? origin) throws Error {
            return new Reader (data, origin).run ();
        }

        public void write (Project p, Sequence s, File file) throws Error {
            var bytes = new Writer (p, s).build (s);
            file.replace_contents (bytes, null, false, FileCreateFlags.REPLACE_DESTINATION, null);
        }
    }
}
