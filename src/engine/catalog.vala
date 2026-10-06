namespace Singularity.Apps.Montage {
    public class ParamSpec : Object {
        public string name;
        public string label;
        public double min;
        public double max;
        public double fallback;
        public double step;
        public string unit;

        public ParamSpec (string name, string label, double min, double max, double fallback, double step = 1, string unit = "") {
            this.name = name;
            this.label = label;
            this.min = min;
            this.max = max;
            this.fallback = fallback;
            this.step = step;
            this.unit = unit;
        }
    }

    public class TextSpec : Object {
        public string name;
        public string label;
        public string kind;
        public string fallback;
        public string[] choices;

        public TextSpec (string name, string label, string kind, string fallback = "", string[] choices = {}) {
            this.name = name;
            this.label = label;
            this.kind = kind;
            this.fallback = fallback;
            this.choices = choices;
        }
    }

    public class EffectInfo : Object {
        public string type;
        public string label;
        public string category;
        public bool audio;
        public Gee.ArrayList<ParamSpec> params = new Gee.ArrayList<ParamSpec> ();
        public Gee.ArrayList<TextSpec> texts = new Gee.ArrayList<TextSpec> ();

        public EffectInfo (string type, string label, string category, bool audio = false) {
            this.type = type;
            this.label = label;
            this.category = category;
            this.audio = audio;
        }

        public EffectInfo p (string name, string label, double min, double max, double fallback, double step = 1, string unit = "") {
            params.add (new ParamSpec (name, label, min, max, fallback, step, unit));
            return this;
        }

        public EffectInfo t (string name, string label, string kind, string fallback = "", string[] choices = {}) {
            texts.add (new TextSpec (name, label, kind, fallback, choices));
            return this;
        }

        public ParamSpec? spec (string name) {
            foreach (var s in params) if (s.name == name) return s;
            return null;
        }

        public Effect create () {
            var e = new Effect (type);
            foreach (var s in params) e.params.values[s.name] = new Singularity.Keyframes.AnimatedValue (s.fallback);
            foreach (var s in texts) e.params.texts[s.name] = s.fallback;
            return e;
        }
    }

    public class Catalog : Object {
        static Gee.ArrayList<EffectInfo>? list;
        static Gee.ArrayList<ParamSpec>? clip_specs;

        public static Gee.ArrayList<EffectInfo> all () {
            if (list == null) build ();
            return list;
        }

        public static EffectInfo? find (string type) {
            foreach (var e in all ()) if (e.type == type) return e;
            if (type.has_prefix ("gst:")) {
                var info = new EffectInfo (type, type.substring (4), _("Installed Filters"));
                info.t ("props", _("Properties"), "text", "");
                return info;
            }
            return null;
        }

        public static double default_of (Effect e, string name) {
            var info = find (e.type);
            var s = info != null ? info.spec (name) : null;
            return s != null ? s.fallback : 0;
        }

        static void build () {
            list = new Gee.ArrayList<EffectInfo> ();
            string color = _("Colour"), keying = _("Keying"), stylize = _("Blur and Stylize"), shape = _("Masks and Motion"), audio = _("Audio");
            list.add (new EffectInfo ("color.primary", _("Primary Correction"), color)
                .p ("exposure", _("Exposure"), -5, 5, 0, 0.05, _("stops"))
                .p ("contrast", _("Contrast"), 0, 3, 1, 0.01)
                .p ("temperature", _("Temperature"), -100, 100, 0, 1)
                .p ("tint", _("Tint"), -100, 100, 0, 1)
                .p ("saturation", _("Saturation"), 0, 300, 100, 1, "%")
                .p ("vibrance", _("Vibrance"), -100, 100, 0, 1)
                .p ("highlights", _("Highlights"), -100, 100, 0, 1)
                .p ("shadows", _("Shadows"), -100, 100, 0, 1)
                .p ("whites", _("Whites"), -100, 100, 0, 1)
                .p ("blacks", _("Blacks"), -100, 100, 0, 1));
            var wheels = new EffectInfo ("color.wheels", _("Colour Wheels"), color);
            foreach (var w in new string[] { "lift", "gamma", "gain", "offset" }) {
                string name = w == "lift" ? _("Shadows") : (w == "gamma" ? _("Midtones") : (w == "gain" ? _("Highlights") : _("Offset")));
                wheels.p (w + "-r", name + " " + _("Red"), -1, 1, 0, 0.005);
                wheels.p (w + "-g", name + " " + _("Green"), -1, 1, 0, 0.005);
                wheels.p (w + "-b", name + " " + _("Blue"), -1, 1, 0, 0.005);
                wheels.p (w + "-l", name + " " + _("Level"), -1, 1, 0, 0.005);
            }
            list.add (wheels);
            list.add (new EffectInfo ("color.curves", _("Curves"), color)
                .t ("master", _("Master"), "curve", "0,0;1,1")
                .t ("red", _("Red"), "curve", "0,0;1,1")
                .t ("green", _("Green"), "curve", "0,0;1,1")
                .t ("blue", _("Blue"), "curve", "0,0;1,1")
                .t ("hue-sat", _("Hue vs Saturation"), "hue-curve", "")
                .t ("hue-hue", _("Hue vs Hue"), "hue-curve", "")
                .t ("luma-sat", _("Luma vs Saturation"), "curve", ""));
            list.add (new EffectInfo ("color.lut", _("LUT"), color)
                .t ("file", _("LUT File"), "file", "")
                .p ("intensity", _("Intensity"), 0, 100, 100, 1, "%"));
            list.add (new EffectInfo ("color.match", _("Colour Match"), color)
                .p ("gain-r", _("Red Gain"), 0, 4, 1, 0.01).p ("gain-g", _("Green Gain"), 0, 4, 1, 0.01).p ("gain-b", _("Blue Gain"), 0, 4, 1, 0.01)
                .p ("offset-r", _("Red Offset"), -1, 1, 0, 0.005).p ("offset-g", _("Green Offset"), -1, 1, 0, 0.005).p ("offset-b", _("Blue Offset"), -1, 1, 0, 0.005)
                .t ("reference", _("Reference"), "label", ""));
            list.add (new EffectInfo ("color.bw", _("Black and White"), color)
                .p ("amount", _("Amount"), 0, 100, 100, 1, "%"));
            list.add (new EffectInfo ("key.chroma", _("Chroma Key"), keying)
                .t ("color", _("Key Colour"), "color", "#00ff00ff")
                .p ("tolerance", _("Tolerance"), 0, 100, 30, 1)
                .p ("softness", _("Edge Softness"), 0, 100, 10, 1)
                .p ("spill", _("Spill Suppression"), 0, 100, 60, 1)
                .p ("choke", _("Choke"), -10, 10, 0, 0.5, "px")
                .p ("feather", _("Edge Feather"), 0, 20, 1, 0.5, "px")
                .p ("matte", _("Show Matte"), 0, 1, 0, 1));
            list.add (new EffectInfo ("key.luma", _("Luma Key"), keying)
                .p ("low", _("Low"), 0, 100, 0, 1).p ("high", _("High"), 0, 100, 20, 1)
                .p ("softness", _("Softness"), 0, 100, 5, 1).p ("invert", _("Invert"), 0, 1, 0, 1));
            list.add (new EffectInfo ("mask", _("Mask"), shape)
                .t ("path", _("Shape"), "path", "25,25;75,25;75,75;25,75")
                .t ("mode", _("Mode"), "choice", "add", { "add", "subtract", "intersect" })
                .p ("feather", _("Feather"), 0, 200, 10, 1, "px")
                .p ("expansion", _("Expansion"), -100, 100, 0, 1, "px")
                .p ("opacity", _("Mask Opacity"), 0, 100, 100, 1, "%")
                .p ("invert", _("Inverted"), 0, 1, 0, 1)
                .p ("track-x", _("Tracked X"), -10000, 10000, 0, 0.1, "px")
                .p ("track-y", _("Tracked Y"), -10000, 10000, 0, 0.1, "px"));
            list.add (new EffectInfo ("stabilize", _("Stabilizer"), shape)
                .p ("smoothness", _("Smoothness"), 0, 100, 50, 1, "%")
                .p ("crop", _("Crop to Hide Edges"), 0, 1, 1, 1)
                .t ("data", _("Analysis"), "hidden", ""));
            list.add (new EffectInfo ("blur", _("Gaussian Blur"), stylize).p ("radius", _("Blurriness"), 0, 100, 8, 0.5, "px"));
            list.add (new EffectInfo ("sharpen", _("Sharpen"), stylize).p ("amount", _("Amount"), 0, 300, 60, 1, "%").p ("radius", _("Radius"), 0.5, 10, 1.5, 0.1, "px"));
            list.add (new EffectInfo ("vignette", _("Vignette"), stylize).p ("amount", _("Amount"), -100, 100, 40, 1).p ("size", _("Size"), 10, 150, 80, 1, "%").p ("softness", _("Softness"), 1, 100, 50, 1));
            list.add (new EffectInfo ("mosaic", _("Mosaic"), stylize).p ("size", _("Cell Size"), 2, 200, 16, 1, "px"));
            list.add (new EffectInfo ("invert", _("Invert"), stylize).p ("amount", _("Amount"), 0, 100, 100, 1, "%"));
            list.add (new EffectInfo ("glow", _("Glow"), stylize).p ("threshold", _("Threshold"), 0, 100, 70, 1).p ("radius", _("Radius"), 1, 100, 20, 1, "px").p ("intensity", _("Intensity"), 0, 300, 80, 1, "%"));
            list.add (new EffectInfo ("audio.gain", _("Gain"), audio, true).p ("gain", _("Gain"), -60, 24, 0, 0.1, "dB"));
            list.add (new EffectInfo ("audio.eq", _("Equalizer"), audio, true)
                .p ("highpass", _("Low Cut"), 0, 500, 0, 1, "Hz")
                .p ("low-gain", _("Low"), -18, 18, 0, 0.5, "dB")
                .p ("low-freq", _("Low Frequency"), 40, 500, 120, 1, "Hz")
                .p ("mid-gain", _("Mid"), -18, 18, 0, 0.5, "dB")
                .p ("mid-freq", _("Mid Frequency"), 200, 8000, 1000, 1, "Hz")
                .p ("mid-q", _("Mid Width"), 0.2, 8, 1, 0.05)
                .p ("high-gain", _("High"), -18, 18, 0, 0.5, "dB")
                .p ("high-freq", _("High Frequency"), 2000, 16000, 8000, 10, "Hz")
                .p ("lowpass", _("High Cut"), 0, 22000, 0, 10, "Hz"));
            list.add (new EffectInfo ("audio.compressor", _("Compressor"), audio, true)
                .p ("threshold", _("Threshold"), -60, 0, -18, 0.5, "dB").p ("ratio", _("Ratio"), 1, 20, 4, 0.1)
                .p ("attack", _("Attack"), 0.1, 200, 10, 0.1, "ms").p ("release", _("Release"), 5, 2000, 120, 1, "ms")
                .p ("knee", _("Knee"), 0, 24, 6, 0.5, "dB").p ("makeup", _("Makeup"), 0, 24, 0, 0.5, "dB"));
            list.add (new EffectInfo ("audio.limiter", _("Limiter"), audio, true)
                .p ("ceiling", _("Ceiling"), -24, 0, -1, 0.1, "dB").p ("release", _("Release"), 5, 1000, 60, 1, "ms"));
            list.add (new EffectInfo ("audio.gate", _("Noise Gate"), audio, true)
                .p ("threshold", _("Threshold"), -90, 0, -50, 0.5, "dB").p ("range", _("Range"), -90, 0, -40, 0.5, "dB")
                .p ("attack", _("Attack"), 0.1, 100, 2, 0.1, "ms").p ("release", _("Release"), 5, 2000, 150, 1, "ms"));
            list.add (new EffectInfo ("audio.denoise", _("Noise Reduction"), audio, true)
                .p ("reduction", _("Reduction"), 0, 40, 18, 0.5, "dB").p ("sensitivity", _("Sensitivity"), 0.5, 4, 1.5, 0.05)
                .t ("profile", _("Noise Profile"), "hidden", ""));
        }

        public static Gee.ArrayList<EffectInfo> installed_filters () {
            var r = new Gee.ArrayList<EffectInfo> ();
            var registry = Gst.Registry.get ();
            var features = registry.get_feature_list (typeof (Gst.ElementFactory));
            foreach (var feature in features) {
                var f = (Gst.ElementFactory) feature;
                string klass = f.get_metadata (Gst.ELEMENT_METADATA_KLASS) ?? "";
                if (!klass.contains ("Filter") || !klass.contains ("Video") || klass.contains ("Converter") || klass.contains ("Scaler")) continue;
                if (klass.contains ("Decoder") || klass.contains ("Encoder") || klass.contains ("Parser") || klass.contains ("Hardware")) continue;
                string name = f.get_name ();
                if (name.has_prefix ("gl") || name.has_prefix ("vulkan") || name.has_prefix ("va") || name.has_prefix ("cuda")) continue;
                if (!sink_accepts_raw (f)) continue;
                var info = new EffectInfo ("gst:" + name, f.get_metadata (Gst.ELEMENT_METADATA_LONGNAME) ?? name,
                    name.has_prefix ("frei0r") ? _("frei0r Plugins") : _("Installed Filters"));
                info.t ("props", _("Properties"), "text", "");
                r.add (info);
            }
            r.sort ((a, b) => strcmp (a.label, b.label));
            return r;
        }

        static bool sink_accepts_raw (Gst.ElementFactory f) {
            foreach (var tpl in f.get_static_pad_templates ()) {
                if (tpl.direction != Gst.PadDirection.SINK) continue;
                var caps = tpl.get_caps ();
                if (caps.is_any ()) return true;
                for (uint i = 0; i < caps.get_size (); i++) {
                    if (caps.get_structure (i).get_name () == "video/x-raw" && caps.get_features (i).contains ("memory:SystemMemory")) return true;
                }
            }
            return false;
        }

        public static Gee.ArrayList<ParamSpec> clip_params () {
            if (clip_specs != null) return clip_specs;
            clip_specs = new Gee.ArrayList<ParamSpec> ();
            clip_specs.add (new ParamSpec ("x", _("Position X"), -20000, 20000, 0, 1, "px"));
            clip_specs.add (new ParamSpec ("y", _("Position Y"), -20000, 20000, 0, 1, "px"));
            clip_specs.add (new ParamSpec ("scale", _("Scale"), 0, 2000, 100, 0.5, "%"));
            clip_specs.add (new ParamSpec ("scale-x", _("Width"), 0, 2000, 100, 0.5, "%"));
            clip_specs.add (new ParamSpec ("scale-y", _("Height"), 0, 2000, 100, 0.5, "%"));
            clip_specs.add (new ParamSpec ("rotation", _("Rotation"), -3600, 3600, 0, 0.5, "°"));
            clip_specs.add (new ParamSpec ("anchor-x", _("Anchor X"), -20000, 20000, 0, 1, "px"));
            clip_specs.add (new ParamSpec ("anchor-y", _("Anchor Y"), -20000, 20000, 0, 1, "px"));
            clip_specs.add (new ParamSpec ("opacity", _("Opacity"), 0, 100, 100, 1, "%"));
            clip_specs.add (new ParamSpec ("crop-left", _("Crop Left"), 0, 100, 0, 0.5, "%"));
            clip_specs.add (new ParamSpec ("crop-right", _("Crop Right"), 0, 100, 0, 0.5, "%"));
            clip_specs.add (new ParamSpec ("crop-top", _("Crop Top"), 0, 100, 0, 0.5, "%"));
            clip_specs.add (new ParamSpec ("crop-bottom", _("Crop Bottom"), 0, 100, 0, 0.5, "%"));
            clip_specs.add (new ParamSpec ("volume", _("Volume"), -60, 24, 0, 0.1, "dB"));
            clip_specs.add (new ParamSpec ("pan", _("Pan"), -100, 100, 0, 1));
            clip_specs.add (new ParamSpec ("speed", _("Speed"), 1, 10000, 100, 1, "%"));
            return clip_specs;
        }

        public static double clip_default (string name) {
            foreach (var s in clip_params ()) if (s.name == name) return s.fallback;
            return 0;
        }
    }
}
