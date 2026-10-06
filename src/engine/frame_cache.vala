using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class CachedFrame : Object {
        public int width;
        public int height;
        public uint8[] pixels;
        public int64 used;
    }

    public class FrameCache : Object {
        Gee.HashMap<string, CachedFrame> memory = new Gee.HashMap<string, CachedFrame> ();
        int64 memory_bytes;
        public int64 memory_limit = 512 * 1024 * 1024;
        public int64 disk_limit = 4L * 1024 * 1024 * 1024;
        public File? disk;
        int64 clock;
        Mutex mutex;
        public int hits { get; private set; }
        public int disk_hits { get; private set; }
        public int misses { get; private set; }

        public FrameCache (File? disk) {
            this.disk = disk;
        }

        public static File default_dir () {
            return File.new_for_path (Path.build_filename (Environment.get_user_cache_dir (), "singularity-montage", "frames"));
        }

        File entry (string key) {
            return disk.get_child (key.substring (0, 2)).get_child (key + ".frame");
        }

        public bool contains (string key) {
            mutex.lock ();
            bool r = memory.has_key (key);
            mutex.unlock ();
            if (r) return true;
            return disk != null && entry (key).query_exists ();
        }

        public FloatImage? lookup (string key, int width, int height) {
            mutex.lock ();
            var f = memory[key];
            if (f != null) {
                f.used = ++clock;
                hits++;
            }
            mutex.unlock ();
            if (f == null && disk != null) {
                f = read_disk (key);
                if (f != null) {
                    disk_hits++;
                    remember (key, f);
                }
            }
            if (f == null || f.width != width || f.height != height) {
                if (f == null) misses++;
                return null;
            }
            var img = new FloatImage (f.width, f.height);
            unowned float[] lut = Tone.table8 ();
            int n = f.width * f.height * 4;
            for (int i = 0; i < n; i++) img.data[i] = (i & 3) == 3 ? f.pixels[i] / 255.0f : lut[f.pixels[i]];
            return img;
        }

        public void store (string key, FloatImage img, bool to_disk = false) {
            var f = new CachedFrame ();
            f.width = img.width;
            f.height = img.height;
            f.pixels = ColorPipeline.encode_rgba8 (img, false);
            remember (key, f);
            if (to_disk && disk != null) write_disk (key, f);
        }

        void remember (string key, CachedFrame f) {
            mutex.lock ();
            f.used = ++clock;
            if (!memory.has_key (key)) memory_bytes += f.pixels.length;
            memory[key] = f;
            if (memory_bytes > memory_limit) {
                var entries = new Gee.ArrayList<string> ();
                entries.add_all (memory.keys);
                entries.sort ((a, b) => memory[a].used < memory[b].used ? -1 : 1);
                foreach (var k in entries) {
                    if (memory_bytes <= memory_limit * 3 / 4) break;
                    memory_bytes -= memory[k].pixels.length;
                    memory.unset (k);
                }
            }
            mutex.unlock ();
        }

        void write_disk (string key, CachedFrame f) {
            try {
                var file = entry (key);
                var parent = file.get_parent ();
                if (!parent.query_exists ()) parent.make_directory_with_parents ();
                var conv = new ZlibCompressor (ZlibCompressorFormat.RAW, 1);
                var mem = new MemoryOutputStream.resizable ();
                var stream = new ConverterOutputStream (mem, conv);
                size_t done;
                stream.write_all (f.pixels, out done);
                stream.close ();
                var header = new uint8[8];
                header[0] = (uint8) (f.width & 0xff); header[1] = (uint8) (f.width >> 8); header[2] = (uint8) (f.width >> 16);
                header[4] = (uint8) (f.height & 0xff); header[5] = (uint8) (f.height >> 8); header[6] = (uint8) (f.height >> 16);
                var body = mem.steal_data ();
                body.length = (int) mem.get_data_size ();
                var all = new ByteArray ();
                all.append (header);
                all.append (body);
                file.replace_contents (all.data, null, false, FileCreateFlags.PRIVATE, null);
            } catch (Error e) {
                debug ("frame cache write: %s", e.message);
            }
        }

        CachedFrame? read_disk (string key) {
            try {
                var file = entry (key);
                if (!file.query_exists ()) return null;
                uint8[] data;
                file.load_contents (null, out data, null);
                if (data.length < 8) return null;
                var f = new CachedFrame ();
                f.width = data[0] | (data[1] << 8) | (data[2] << 16);
                f.height = data[4] | (data[5] << 8) | (data[6] << 16);
                if (f.width <= 0 || f.height <= 0 || f.width > 16384 || f.height > 16384) return null;
                var conv = new ZlibDecompressor (ZlibCompressorFormat.RAW);
                var stream = new ConverterInputStream (new MemoryInputStream.from_data (data[8:data.length]), conv);
                f.pixels = new uint8[f.width * f.height * 4];
                size_t read;
                stream.read_all (f.pixels, out read);
                if (read != f.pixels.length) return null;
                return f;
            } catch (Error e) {
                return null;
            }
        }

        public void clear_memory () {
            mutex.lock ();
            memory.clear ();
            memory_bytes = 0;
            mutex.unlock ();
        }

        public int64 disk_usage () {
            if (disk == null) return 0;
            int64 total = 0;
            try {
                var e = disk.enumerate_children ("standard::name,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                FileInfo? info;
                while ((info = e.next_file ()) != null) {
                    if (info.get_file_type () != FileType.DIRECTORY) continue;
                    var sub = disk.get_child (info.get_name ()).enumerate_children ("standard::size", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                    FileInfo? item;
                    while ((item = sub.next_file ()) != null) total += item.get_size ();
                }
            } catch (Error e) {
            }
            return total;
        }

        public void trim_disk () {
            if (disk == null || disk_usage () <= disk_limit) return;
            var files = new Gee.ArrayList<File> ();
            var times = new Gee.HashMap<File, uint64?> ();
            try {
                var e = disk.enumerate_children ("standard::name,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                FileInfo? info;
                while ((info = e.next_file ()) != null) {
                    if (info.get_file_type () != FileType.DIRECTORY) continue;
                    var dir = disk.get_child (info.get_name ());
                    var sub = dir.enumerate_children ("standard::name,time::access,time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                    FileInfo? item;
                    while ((item = sub.next_file ()) != null) {
                        var f = dir.get_child (item.get_name ());
                        files.add (f);
                        times[f] = item.get_attribute_uint64 ("time::modified");
                    }
                }
                files.sort ((a, b) => times[a] < times[b] ? -1 : 1);
                int64 usage = disk_usage ();
                foreach (var f in files) {
                    if (usage <= disk_limit * 3 / 4) break;
                    var info2 = f.query_info ("standard::size", FileQueryInfoFlags.NONE);
                    usage -= info2.get_size ();
                    f.delete ();
                }
            } catch (Error e) {
                debug ("frame cache trim: %s", e.message);
            }
        }
    }
}
