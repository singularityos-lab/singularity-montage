using Singularity.Audio;

namespace Singularity.Apps.Montage {
    public abstract class AudioProcessor : Object {
        public virtual int latency { get { return 0; } }
        public abstract void update (Effect e, int64 key);
        public abstract void process (float[] data, int frames);
    }

    class GainProcessor : AudioProcessor {
        double gain = 1;
        public override void update (Effect e, int64 key) {
            gain = db_to_gain (e.params.get_value ("gain", key, 0));
        }
        public override void process (float[] data, int frames) {
            for (int i = 0; i < frames * 2; i++) data[i] = (float) (data[i] * gain);
        }
    }

    class EqProcessor : AudioProcessor {
        Equalizer eq;
        string signature = "";
        public EqProcessor (int rate) {
            eq = new Equalizer (rate, 2);
        }
        public override void update (Effect e, int64 key) {
            var p = e.params;
            double hp = p.get_value ("highpass", key, 0), lp = p.get_value ("lowpass", key, 0);
            string sig = "%g|%g|%g|%g|%g|%g|%g|%g|%g".printf (hp, p.get_value ("low-gain", key, 0), p.get_value ("low-freq", key, 120),
                p.get_value ("mid-gain", key, 0), p.get_value ("mid-freq", key, 1000), p.get_value ("mid-q", key, 1),
                p.get_value ("high-gain", key, 0), p.get_value ("high-freq", key, 8000), lp);
            if (sig == signature) return;
            signature = sig;
            eq.bands.clear ();
            if (hp > 0) eq.bands.add (new EqBand (FilterType.HIGH_PASS, hp, 0, 0.707));
            eq.bands.add (new EqBand (FilterType.LOW_SHELF, p.get_value ("low-freq", key, 120), p.get_value ("low-gain", key, 0), 0.707));
            eq.bands.add (new EqBand (FilterType.PEAK, p.get_value ("mid-freq", key, 1000), p.get_value ("mid-gain", key, 0), p.get_value ("mid-q", key, 1)));
            eq.bands.add (new EqBand (FilterType.HIGH_SHELF, p.get_value ("high-freq", key, 8000), p.get_value ("high-gain", key, 0), 0.707));
            if (lp > 0) eq.bands.add (new EqBand (FilterType.LOW_PASS, lp, 0, 0.707));
            eq.update ();
        }
        public override void process (float[] data, int frames) {
            eq.process (data, frames);
        }
    }

    class CompressorProcessor : AudioProcessor {
        Compressor c;
        public CompressorProcessor (int rate) {
            c = new Compressor (rate, 2);
        }
        public override void update (Effect e, int64 key) {
            var p = e.params;
            c.threshold_db = p.get_value ("threshold", key, -18);
            c.ratio = p.get_value ("ratio", key, 4);
            c.attack_ms = p.get_value ("attack", key, 10);
            c.release_ms = p.get_value ("release", key, 120);
            c.knee_db = p.get_value ("knee", key, 6);
            c.makeup_db = p.get_value ("makeup", key, 0);
        }
        public override void process (float[] data, int frames) {
            c.process (data, frames);
        }
    }

    class LimiterProcessor : AudioProcessor {
        Limiter l;
        public LimiterProcessor (int rate) {
            l = new Limiter (rate, 2);
        }
        public override int latency { get { return l.latency; } }
        public override void update (Effect e, int64 key) {
            l.ceiling_db = e.params.get_value ("ceiling", key, -1);
            l.release_ms = e.params.get_value ("release", key, 60);
        }
        public override void process (float[] data, int frames) {
            l.process (data, frames);
        }
    }

    class GateProcessor : AudioProcessor {
        NoiseGate g;
        public GateProcessor (int rate) {
            g = new NoiseGate (rate, 2);
        }
        public override void update (Effect e, int64 key) {
            var p = e.params;
            g.threshold_db = p.get_value ("threshold", key, -50);
            g.range_db = p.get_value ("range", key, -40);
            g.attack_ms = p.get_value ("attack", key, 2);
            g.release_ms = p.get_value ("release", key, 150);
        }
        public override void process (float[] data, int frames) {
            g.process (data, frames);
        }
    }

    class DenoiseProcessor : AudioProcessor {
        NoiseReduction n = new NoiseReduction (2);
        string profile = "";
        public override int latency { get { return n.latency; } }
        public override void update (Effect e, int64 key) {
            n.reduction_db = e.params.get_value ("reduction", key, 18);
            n.sensitivity = e.params.get_value ("sensitivity", key, 1.5);
            string p = e.params.text ("profile");
            if (p != profile && p != "") {
                profile = p;
                var parts = p.split (",");
                var values = new double[parts.length];
                for (int i = 0; i < parts.length; i++) values[i] = double.parse (parts[i]);
                n.set_profile (values);
            }
        }
        public override void process (float[] data, int frames) {
            n.process (data, frames);
        }
    }

    public class AudioChain : Object {
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();
        public Gee.ArrayList<AudioProcessor?> processors = new Gee.ArrayList<AudioProcessor?> ();
        public int latency { get; private set; }

        public AudioChain (Gee.List<Effect> list, int rate) {
            foreach (var e in list) {
                if (!e.enabled) continue;
                AudioProcessor? p = null;
                switch (e.type) {
                    case "audio.gain": p = new GainProcessor (); break;
                    case "audio.eq": p = new EqProcessor (rate); break;
                    case "audio.compressor": p = new CompressorProcessor (rate); break;
                    case "audio.limiter": p = new LimiterProcessor (rate); break;
                    case "audio.gate": p = new GateProcessor (rate); break;
                    case "audio.denoise": p = new DenoiseProcessor (); break;
                }
                if (p == null) continue;
                effects.add (e);
                processors.add (p);
                latency += p.latency;
            }
        }

        public bool empty {
            get { return processors.size == 0; }
        }

        public void process (float[] data, int frames, int64 key) {
            for (int i = 0; i < processors.size; i++) {
                processors[i].update (effects[i], key);
                processors[i].process (data, frames);
            }
        }

        public static string signature (Gee.List<Effect> list) {
            var sb = new StringBuilder ();
            foreach (var e in list) if (e.enabled) sb.append (e.id).append (e.type).append (";");
            return sb.str;
        }
    }

    public class SampleBuffer : Object {
        public float[] data;

        public SampleBuffer (int frames) {
            data = new float[frames * 2];
        }
    }

    class Voice : Object {
        public AudioReader? reader;
        public AudioChain? chain;
        public string chain_sig = "";
        public int64 next = int64.MIN;
        public AudioMixer? nested;
    }

    class Stage : Object {
        public AudioChain? chain;
        public string chain_sig = "";
        public int64 next = int64.MIN;
    }

    public class AudioMixer : Object {
        public Project project;
        public Sequence seq;
        public int rate;
        public bool proxies;
        public double master_gain_db;
        public bool apply_master = true;
        public string? only_track;
        Gee.HashMap<string, Voice> voices = new Gee.HashMap<string, Voice> ();
        Gee.HashMap<string, Stage> stages = new Gee.HashMap<string, Stage> ();
        public Gee.HashMap<string, float?> track_peaks = new Gee.HashMap<string, float?> ();
        public float peak_left;
        public float peak_right;
        public LoudnessMeter? meter;

        public AudioMixer (Project project, Sequence seq, int rate = 48000, bool proxies = false) {
            this.project = project;
            this.seq = seq;
            this.rate = rate;
            this.proxies = proxies;
        }

        public int64 to_time (int64 sample) {
            return (int64) ((double) sample * Tc.SECOND / rate);
        }

        public int64 to_sample (int64 t) {
            return (int64) Math.round ((double) t * rate / Tc.SECOND);
        }

        public void close () {
            foreach (var v in voices.values) {
                if (v.reader != null) v.reader.close ();
                if (v.nested != null) v.nested.close ();
            }
            voices.clear ();
        }

        bool audible (Track t) {
            if (t.kind != TrackKind.AUDIO) return false;
            if (only_track != null) return t.id == only_track;
            if (t.muted) return false;
            bool any_solo = false;
            foreach (var o in seq.tracks) if (o.kind == TrackKind.AUDIO && o.solo) any_solo = true;
            return !any_solo || t.solo;
        }

        public void render (int64 start, int frames, float[] output) {
            for (int i = 0; i < frames * 2; i++) output[i] = 0;
            var master_stage = stage ("master", seq.master_effects);
            int lat = apply_master ? master_stage.chain.latency : 0;
            if (master_stage.next != start) {
                master_stage.chain = new AudioChain (seq.master_effects, rate);
                if (lat > 0 && apply_master) {
                    var prime = new float[lat * 2];
                    mix_buses (start, lat, prime);
                    master_stage.chain.process (prime, lat, to_time (start));
                }
            }
            mix_buses (start + lat, frames, output);
            if (apply_master) {
                master_stage.chain.process (output, frames, to_time (start));
                for (int i = 0; i < frames; i += 64) {
                    int n = int.min (64, frames - i);
                    double g = db_to_gain (seq.master_volume.at (to_time (start + i)) + master_gain_db);
                    for (int k = i * 2; k < (i + n) * 2; k++) output[k] = (float) (output[k] * g);
                }
            }
            master_stage.next = start + frames;
            float pl = 0, pr = 0;
            for (int i = 0; i < frames; i++) {
                pl = float.max (pl, output[i * 2].abs ());
                pr = float.max (pr, output[i * 2 + 1].abs ());
            }
            peak_left = pl;
            peak_right = pr;
            if (meter != null) meter.add (output, frames);
        }

        Stage stage (string id, Gee.List<Effect> effects) {
            var s = stages[id];
            string sig = AudioChain.signature (effects);
            if (s == null || s.chain_sig != sig) {
                s = new Stage ();
                s.chain = new AudioChain (effects, rate);
                s.chain_sig = sig;
                stages[id] = s;
            }
            return s;
        }

        void mix_buses (int64 start, int frames, float[] output) {
            var bus_inputs = new Gee.HashMap<string, SampleBuffer> ();
            foreach (var t in seq.tracks) {
                if (!audible (t)) continue;
                var buf = new float[frames * 2];
                render_track (t, start, frames, buf);
                float peak = 0;
                foreach (var v in buf) peak = float.max (peak, v.abs ());
                track_peaks[t.id] = peak;
                string route = seq.bus (t.bus) != null ? t.bus : "master";
                if (route == "master") {
                    for (int i = 0; i < frames * 2; i++) output[i] += buf[i];
                } else {
                    if (!bus_inputs.has_key (route)) bus_inputs[route] = new SampleBuffer (frames);
                    unowned float[] target = bus_inputs[route].data;
                    for (int i = 0; i < frames * 2; i++) target[i] += buf[i];
                }
            }
            foreach (var bus in seq.buses) {
                if (!bus_inputs.has_key (bus.id) || bus.muted) continue;
                unowned float[] buf = bus_inputs[bus.id].data;
                var st = stage ("bus:" + bus.id, bus.effects);
                if (st.next != start) st.chain = new AudioChain (bus.effects, rate);
                st.chain.process (buf, frames, to_time (start));
                st.next = start + frames;
                apply_gain_pan (buf, frames, start, bus.volume, bus.pan);
                for (int i = 0; i < frames * 2; i++) output[i] += buf[i];
            }
        }

        void apply_gain_pan (float[] buf, int frames, int64 start, Singularity.Keyframes.AnimatedValue volume, Singularity.Keyframes.AnimatedValue pan) {
            for (int i = 0; i < frames; i += 64) {
                int n = int.min (64, frames - i);
                int64 t = to_time (start + i);
                double g = db_to_gain (volume.at (t));
                float l, r;
                pan_gains (pan.at (t) / 100.0, out l, out r);
                for (int k = i; k < i + n; k++) {
                    buf[k * 2] = (float) (buf[k * 2] * g * l);
                    buf[k * 2 + 1] = (float) (buf[k * 2 + 1] * g * r);
                }
            }
        }

        public void render_track (Track t, int64 start, int frames, float[] output) {
            var st = stage ("track:" + t.id, t.effects);
            int lat = st.chain.latency;
            if (st.next != start) {
                st.chain = new AudioChain (t.effects, rate);
                if (lat > 0) {
                    var prime = new float[lat * 2];
                    track_input (t, start, lat, prime);
                    st.chain.process (prime, lat, to_time (start));
                }
            }
            track_input (t, start + lat, frames, output);
            st.chain.process (output, frames, to_time (start));
            st.next = start + frames;
            apply_gain_pan (output, frames, start, t.volume, t.pan);
        }

        void track_input (Track t, int64 start, int frames, float[] output) {
            for (int i = 0; i < frames * 2; i++) output[i] = 0;
            int64 t0 = to_time (start), t1 = to_time (start + frames);
            var tmp = new float[frames * 2];
            foreach (var c in seq.clips) {
                if (c.track != t.id || !c.enabled) continue;
                int64 c0 = c.position, c1 = c.end;
                foreach (var tr in seq.transitions) {
                    if (tr.from_clip == c.id && tr.to_clip != "") c1 = int64.max (c1, tr.start_at (c.end) + tr.duration);
                    if (tr.to_clip == c.id && tr.from_clip != "") c0 = int64.min (c0, tr.start_at (c.position));
                }
                if (c1 <= t0 || c0 >= t1) continue;
                clip_output (c, start, frames, tmp, c0, c1);
                for (int i = 0; i < frames * 2; i++) output[i] += tmp[i];
            }
        }

        double fade_gain (Clip c, int64 t) {
            double g = 1;
            foreach (var tr in seq.transitions) {
                if (tr.from_clip != c.id && tr.to_clip != c.id) continue;
                bool out_side = tr.from_clip == c.id;
                int64 cut = out_side ? c.end : c.position;
                int64 s = tr.start_at (cut);
                if (tr.from_clip == "" || tr.to_clip == "") s = out_side ? c.end - tr.duration : c.position;
                int64 e = s + tr.duration;
                if (t < s || t >= e) continue;
                double p = ((double) (t - s) / tr.duration).clamp (0, 1);
                double x = out_side ? 1 - p : p;
                g *= tr.kind == "constant-gain" ? x : Math.sin (x * Math.PI / 2);
            }
            return g;
        }

        void clip_output (Clip c, int64 start, int frames, float[] output, int64 c0, int64 c1) {
            var v = voices[c.id];
            if (v == null) {
                v = new Voice ();
                voices[c.id] = v;
            }
            string sig = AudioChain.signature (c.effects);
            if (v.chain == null || v.chain_sig != sig) {
                v.chain = new AudioChain (c.effects, rate);
                v.chain_sig = sig;
                v.next = int64.MIN;
            }
            int lat = v.chain.latency;
            if (v.next != start) {
                v.chain = new AudioChain (c.effects, rate);
                if (lat > 0) {
                    var prime = new float[lat * 2];
                    clip_source (c, v, start, lat, prime, c0, c1);
                    v.chain.process (prime, lat, c.key_time (to_time (start)));
                }
            }
            clip_source (c, v, start + lat, frames, output, c0, c1);
            if (!v.chain.empty) v.chain.process (output, frames, c.key_time (to_time (start)));
            v.next = start + frames;
            for (int i = 0; i < frames; i += 32) {
                int n = int.min (32, frames - i);
                int64 t = to_time (start + i);
                double g = t < c0 || t >= c1 ? 0 : db_to_gain (c.params.get_value ("volume", c.key_time (t), 0)) * fade_gain (c, t);
                float l, r;
                pan_gains (c.params.get_value ("pan", c.key_time (t), 0) / 100.0, out l, out r);
                for (int k = i; k < i + n; k++) {
                    output[k * 2] = (float) (output[k * 2] * g * l);
                    output[k * 2 + 1] = (float) (output[k * 2 + 1] * g * r);
                }
            }
        }

        string? clip_uri (Clip c, out int64 offset) {
            offset = 0;
            if (c.kind == ClipKind.MEDIA) {
                var m = project.find_media (c.media);
                if (m == null || !m.has_audio) return null;
                return m.playback_uri (proxies);
            }
            if (c.kind == ClipKind.MULTICAM) {
                var m = project.find_media (c.media);
                if (m == null || m.angles.size == 0) return null;
                var a = m.angles[m.audio_angle.clamp (0, m.angles.size - 1)];
                var am = project.find_media (a.media_id);
                if (am == null || !am.has_audio) return null;
                offset = a.offset;
                return am.playback_uri (proxies);
            }
            return null;
        }

        void clip_source (Clip c, Voice v, int64 start, int frames, float[] output, int64 c0, int64 c1) {
            for (int i = 0; i < frames * 2; i++) output[i] = 0;
            int64 t0 = to_time (start);
            int64 t1 = to_time (start + frames);
            if (t1 <= c0 || t0 >= c1) return;
            if (c.kind == ClipKind.SEQUENCE) {
                var n = project.find_sequence (c.sequence);
                if (n == null || n == seq) return;
                if (v.nested == null) v.nested = new AudioMixer (project, n, rate, proxies);
                int64 src = to_sample (c.source_time (int64.max (t0, c.position)));
                int64 lead = to_sample (int64.max (t0, c.position)) - start;
                var tmp = new float[frames * 2];
                v.nested.render (src - lead, frames, tmp);
                Memory.copy (output, tmp, frames * 8);
                return;
            }
            int64 offset;
            string? uri = clip_uri (c, out offset);
            if (uri == null) return;
            if (v.reader == null || v.reader.uri != uri) v.reader = new AudioReader (uri, rate);
            try {
                bool plain = !c.speed_changed;
                if (plain) {
                    int64 src_start = to_sample (c.in_point + (t0 - c.position) - offset);
                    v.reader.read (src_start, frames, output);
                } else {
                    int64 first = int64.MAX, last = int64.MIN;
                    var positions = new double[frames];
                    for (int i = 0; i < frames; i++) {
                        int64 t = to_time (start + i);
                        int64 st = (t < c.position || t >= c.end) ? c.source_time (t.clamp (c.position, c.end - 1)) : c.source_time (t);
                        double sp = (double) (st - offset) * rate / Tc.SECOND;
                        positions[i] = sp;
                        first = int64.min (first, (int64) Math.floor (sp));
                        last = int64.max (last, (int64) Math.floor (sp) + 1);
                    }
                    int span = (int) int64.min (last - first + 1, rate * 60);
                    var src = new float[span * 2];
                    v.reader.read (first, span, src);
                    for (int i = 0; i < frames; i++) {
                        double p = positions[i] - first;
                        int k = (int) Math.floor (p);
                        if (k < 0 || k >= span - 1) continue;
                        float f = (float) (p - k);
                        output[i * 2] = src[k * 2] * (1 - f) + src[(k + 1) * 2] * f;
                        output[i * 2 + 1] = src[k * 2 + 1] * (1 - f) + src[(k + 1) * 2 + 1] * f;
                    }
                }
            } catch (Error e) {
                warning ("audio %s: %s", uri, e.message);
            }
        }
    }
}
