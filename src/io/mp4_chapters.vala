namespace Singularity.Apps.Montage {
    namespace Mp4Chapters {
        uint32 be32 (uint8[] d, int64 at) {
            return ((uint32) d[at] << 24) | ((uint32) d[at + 1] << 16) | ((uint32) d[at + 2] << 8) | d[at + 3];
        }

        void put32 (ByteArray b, uint32 v) {
            uint8[] x = { (uint8) (v >> 24), (uint8) (v >> 16), (uint8) (v >> 8), (uint8) v };
            b.append (x);
        }

        void put64 (ByteArray b, uint64 v) {
            put32 (b, (uint32) (v >> 32));
            put32 (b, (uint32) v);
        }

        string fourcc (uint8[] d, int64 at) {
            var sb = new StringBuilder ();
            for (int i = 0; i < 4; i++) sb.append_c ((char) d[at + i]);
            return sb.str;
        }

        uint8[] chpl (Gee.List<Marker> chapters) {
            var b = new ByteArray ();
            put32 (b, 0);
            b.append ("chpl".data);
            put32 (b, 0x01000000);
            put32 (b, 0);
            uint8[] count = { (uint8) int.min (255, chapters.size) };
            b.append (count);
            for (int i = 0; i < int.min (255, chapters.size); i++) {
                var m = chapters[i];
                put64 (b, (uint64) (m.time / 100));
                string title = m.name != "" ? m.name : "Chapter %d".printf (i + 1);
                var bytes = title.data;
                int len = int.min (255, bytes.length);
                uint8[] l = { (uint8) len };
                b.append (l);
                b.append (bytes[0:len]);
            }
            var data = b.steal ();
            data[0] = (uint8) (data.length >> 24);
            data[1] = (uint8) (data.length >> 16);
            data[2] = (uint8) (data.length >> 8);
            data[3] = (uint8) data.length;
            return data;
        }

        public void inject (File file, Gee.List<Marker> chapters) throws Error {
            if (chapters.size == 0) return;
            uint8[] d;
            file.load_contents (null, out d, null);
            int64 pos = 0, moov = -1, moov_size = 0, mdat = -1;
            while (pos + 8 <= d.length) {
                int64 size = be32 (d, pos);
                string type = fourcc (d, pos + 4);
                if (size == 1) size = (int64) (((uint64) be32 (d, pos + 8) << 32) | be32 (d, pos + 12));
                else if (size == 0) size = d.length - pos;
                if (size < 8) throw new IOError.INVALID_DATA (_("The MP4 file is damaged."));
                if (type == "moov") {
                    moov = pos;
                    moov_size = size;
                }
                if (type == "mdat") mdat = pos;
                pos += size;
            }
            if (moov < 0) throw new IOError.INVALID_DATA (_("The MP4 file has no movie header."));
            if (mdat > moov) throw new IOError.NOT_SUPPORTED (_("Chapters need the movie header after the media data."));
            var children = new ByteArray ();
            int64 p = moov + 8;
            int64 udta = -1, udta_size = 0;
            while (p + 8 <= moov + moov_size) {
                int64 size = be32 (d, p);
                if (size < 8) break;
                if (fourcc (d, p + 4) == "udta") {
                    udta = p;
                    udta_size = size;
                } else {
                    children.append (d[p:p + size]);
                }
                p += size;
            }
            var chapter_box = chpl (chapters);
            var new_udta = new ByteArray ();
            put32 (new_udta, 0);
            new_udta.append ("udta".data);
            if (udta >= 0) {
                int64 q = udta + 8;
                while (q + 8 <= udta + udta_size) {
                    int64 size = be32 (d, q);
                    if (size < 8) break;
                    if (fourcc (d, q + 4) != "chpl") new_udta.append (d[q:q + size]);
                    q += size;
                }
            }
            new_udta.append (chapter_box);
            var udta_bytes = new_udta.steal ();
            udta_bytes[0] = (uint8) (udta_bytes.length >> 24);
            udta_bytes[1] = (uint8) (udta_bytes.length >> 16);
            udta_bytes[2] = (uint8) (udta_bytes.length >> 8);
            udta_bytes[3] = (uint8) udta_bytes.length;
            children.append (udta_bytes);
            var result = new ByteArray ();
            result.append (d[0:moov]);
            put32 (result, (uint32) (children.len + 8));
            result.append ("moov".data);
            result.append (children.data);
            if (moov + moov_size < d.length) result.append (d[moov + moov_size:d.length]);
            file.replace_contents (result.data, null, false, FileCreateFlags.NONE, null);
        }
    }
}
