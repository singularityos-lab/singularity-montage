namespace Singularity.Apps.Montage {
    public class Word : Object {
        public string text;
        public int64 start;
        public int64 end;

        public Word (string text, int64 start, int64 end) {
            this.text = text;
            this.start = start;
            this.end = end;
        }
    }

    namespace Transcript {
        public string serialize (Gee.List<Word> words) {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var w in words) {
                b.begin_object ();
                Js.s (b, "w", w.text);
                Js.i (b, "s", w.start);
                Js.i (b, "e", w.end);
                b.end_object ();
            }
            b.end_array ();
            return Js.write (b.get_root ());
        }

        public Gee.ArrayList<Word> parse (string text) {
            var r = new Gee.ArrayList<Word> ();
            if (text == "") return r;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (text);
                foreach (var n in parser.get_root ().get_array ().get_elements ()) {
                    var o = n.get_object ();
                    r.add (new Word (Js.str (o, "w"), Js.integer (o, "s"), Js.integer (o, "e")));
                }
            } catch (Error e) {
            }
            return r;
        }

        public Gee.ArrayList<Cue> to_cues (Gee.List<Word> words, int max_chars = 42, int64 max_duration = 6000000000) {
            var cues = new Gee.ArrayList<Cue> ();
            var line = new StringBuilder ();
            int64 start = -1, end = 0;
            int lines = 0;
            foreach (var w in words) {
                bool sentence_end = line.len > 0 && (line.str.has_suffix (".") || line.str.has_suffix ("?") || line.str.has_suffix ("!"));
                bool gap = start >= 0 && w.start - end > 800000000;
                string current_line = line.str.contains ("\n") ? line.str.substring (line.str.last_index_of ("\n") + 1) : line.str;
                bool full = current_line.length + w.text.length + 1 > max_chars;
                if (start >= 0 && (gap || (full && lines >= 1) || w.end - start > max_duration || (sentence_end && line.len > max_chars / 2))) {
                    cues.add (new Cue (start, end, line.str));
                    line.truncate ();
                    start = -1;
                    lines = 0;
                    full = false;
                }
                if (start < 0) start = w.start;
                if (line.len > 0) {
                    if (full) {
                        line.append ("\n");
                        lines++;
                    } else {
                        line.append (" ");
                    }
                }
                line.append (w.text);
                end = w.end;
            }
            if (start >= 0) cues.add (new Cue (start, end, line.str));
            return cues;
        }
    }

    public abstract class SpeechBackend : Object {
        public abstract string name { get; }
        public abstract string recognize (string wav_path, string language) throws Error;
    }

    public class DictationBackend : SpeechBackend {
        public const string BUS_NAME = "dev.sinty.Dictation";
        DBusConnection bus;

        public DictationBackend (DBusConnection bus) {
            this.bus = bus;
        }

        public override string name { get { return _("Desktop dictation"); } }

        public static bool present (DBusConnection bus) {
            try {
                var reply = bus.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                    new Variant ("(s)", BUS_NAME), new VariantType ("(b)"), DBusCallFlags.NONE, 2000, null);
                bool owned;
                reply.get ("(b)", out owned);
                if (owned) return true;
                reply = bus.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListActivatableNames",
                    null, new VariantType ("(as)"), DBusCallFlags.NONE, 2000, null);
                var names = reply.get_child_value (0);
                for (size_t i = 0; i < names.n_children (); i++) if (names.get_child_value (i).get_string () == BUS_NAME) return true;
            } catch (Error e) {
            }
            return false;
        }

        public override string recognize (string wav_path, string language) throws Error {
            var reply = bus.call_sync (BUS_NAME, "/dev/sinty/Dictation", "dev.sinty.Dictation", "TranscribeFile",
                new Variant ("(ss)", wav_path, language), new VariantType ("(s)"), DBusCallFlags.NONE, 30 * 60 * 1000, null);
            string text;
            reply.get ("(s)", out text);
            return text.strip ();
        }
    }

    public class CommandSpeechBackend : SpeechBackend {
        string template;

        public CommandSpeechBackend (string template) {
            this.template = template;
        }

        public override string name { get { return _("Command"); } }

        public override string recognize (string wav_path, string language) throws Error {
            string[] argv;
            GLib.Shell.parse_argv (template, out argv);
            for (int i = 0; i < argv.length; i++) argv[i] = argv[i].replace ("{file}", wav_path).replace ("{language}", language);
            string out_text, err_text;
            int status;
            Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out out_text, out err_text, out status);
            if (status != 0) throw new IOError.FAILED (_("The speech command failed: %s").printf (err_text.strip ()));
            return out_text.strip ();
        }
    }

    namespace Speech {
        public SpeechBackend? find (string command) {
            if (command != "") return new CommandSpeechBackend (command);
            try {
                var bus = GLib.Bus.get_sync (BusType.SESSION);
                if (DictationBackend.present (bus)) return new DictationBackend (bus);
            } catch (Error e) {
            }
            return null;
        }

        void write_wav (string path, int16[] samples, int rate) throws Error {
            var b = new ByteArray ();
            uint32 data_len = samples.length * 2;
            b.append ("RIFF".data);
            put32 (b, 36 + data_len);
            b.append ("WAVEfmt ".data);
            put32 (b, 16);
            put16 (b, 1);
            put16 (b, 1);
            put32 (b, rate);
            put32 (b, rate * 2);
            put16 (b, 2);
            put16 (b, 16);
            b.append ("data".data);
            put32 (b, data_len);
            uint8[] bytes = new uint8[data_len];
            Memory.copy (bytes, samples, data_len);
            b.append (bytes);
            FileUtils.set_data (path, b.data);
        }

        void put16 (ByteArray b, uint v) {
            uint8[] x = { (uint8) v, (uint8) (v >> 8) };
            b.append (x);
        }

        void put32 (ByteArray b, uint32 v) {
            uint8[] x = { (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) };
            b.append (x);
        }

        public Gee.ArrayList<Word> transcribe (string uri, int64 start, int64 end, string language, SpeechBackend backend, string tmp_dir, Progress? progress = null) throws Error {
            int rate = 16000;
            var reader = new AudioReader (uri, 48000);
            int64 s0 = start * 48000 / Tc.SECOND, s1 = end * 48000 / Tc.SECOND;
            int frame = 480;
            var energy = new Gee.ArrayList<float?> ();
            int16[] mono = {};
            var buf = new float[frame * 2 * 100];
            for (int64 s = s0; s < s1; s += frame * 100) {
                int n = (int) int64.min (frame * 100, s1 - s);
                reader.read (s, n, buf);
                for (int i = 0; i + 3 <= n; i += 3) {
                    float v = (buf[i * 2] + buf[i * 2 + 1] + buf[(i + 1) * 2] + buf[(i + 1) * 2 + 1] + buf[(i + 2) * 2] + buf[(i + 2) * 2 + 1]) / 6;
                    mono += (int16) (v.clamp (-1, 1) * 32767);
                }
                for (int k = 0; k * frame < n; k++) {
                    double sum = 0;
                    for (int i = k * frame; i < int.min (n, (k + 1) * frame); i++) sum += buf[i * 2] * buf[i * 2];
                    energy.add ((float) Math.sqrt (sum / frame));
                }
            }
            reader.close ();
            float noise = 1;
            var sorted = new Gee.ArrayList<float?> ();
            sorted.add_all (energy);
            sorted.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            if (sorted.size > 0) noise = sorted[sorted.size / 10];
            float threshold = float.max (0.004f, noise * 3);
            var segments = new Gee.ArrayList<int> ();
            int seg_start = -1, silent = 0;
            for (int i = 0; i < energy.size; i++) {
                bool voice = energy[i] > threshold;
                if (voice) {
                    if (seg_start < 0) seg_start = int.max (0, i - 10);
                    silent = 0;
                } else if (seg_start >= 0) {
                    silent++;
                    if (silent > 35 || i - seg_start > 2500) {
                        segments.add (seg_start);
                        segments.add (i - silent + 10);
                        seg_start = -1;
                        silent = 0;
                    }
                }
            }
            if (seg_start >= 0) {
                segments.add (seg_start);
                segments.add (energy.size);
            }
            var words = new Gee.ArrayList<Word> ();
            DirUtils.create_with_parents (tmp_dir, 0700);
            for (int k = 0; k < segments.size; k += 2) {
                int a = segments[k], b = segments[k + 1];
                if (b - a < 15) continue;
                int from = a * frame / 3, to = int.min (mono.length, b * frame / 3);
                var chunk = new int16[to - from];
                for (int i = from; i < to; i++) chunk[i - from] = mono[i];
                string path = Path.build_filename (tmp_dir, "segment-%d.wav".printf (k / 2));
                write_wav (path, chunk, rate);
                string text = backend.recognize (path, language);
                FileUtils.remove (path);
                int64 t0 = start + (int64) a * frame * Tc.SECOND / 48000;
                int64 t1 = start + (int64) b * frame * Tc.SECOND / 48000;
                var parts = new Gee.ArrayList<string> ();
                foreach (var p in text.split_set (" \n\t")) if (p.strip () != "") parts.add (p.strip ());
                int total_chars = 0;
                foreach (var p in parts) total_chars += p.char_count () + 1;
                int64 cursor = t0;
                foreach (var p in parts) {
                    int64 len = (int64) ((double) (t1 - t0) * (p.char_count () + 1) / int.max (1, total_chars));
                    words.add (new Word (p, cursor, cursor + len));
                    cursor += len;
                }
                if (progress != null) progress ((double) (k + 2) / segments.size);
            }
            return words;
        }
    }
}
