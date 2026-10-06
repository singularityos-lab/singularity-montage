using Singularity.Apps.Montage;
using Singularity.Apps.Montage.TestKit;
using Singularity.Imaging;

const int64 S = 1000000000;

double red_at (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return Tone.encode (r) * 255;
}

double alpha_at (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return a;
}

Project project_with (string uri, out MediaItem media) throws Error {
    var p = new Project ();
    var s = p.sequence;
    s.width = 320;
    s.height = 180;
    s.fps_n = 25;
    media = Probe.probe (uri);
    p.media.add (media);
    return p;
}

void test_probe_and_decoder () throws Error {
    string uri = File.new_for_path (make_video ("count.webm", 75, 25, 160, 90, true)).get_uri ();
    var m = Probe.probe (uri);
    check (m.has_video && m.has_audio && m.width == 160 && m.height == 90, "probe reads streams");
    close_to ((double) m.duration / S, 3.0, 0.05, "probe reads duration");
    check (m.fps_n == 25 && m.fps_d == 1, "probe reads frame rate");
    var reader = new VideoReader (uri, 160, 90);
    int[] order = { 0, 1, 2, 40, 41, 10, 74, 3, 60, 59 };
    foreach (int i in order) {
        var f = reader.frame_at ((int64) i * 40000000 + 5000000);
        check (f != null, "frame %d decoded".printf (i));
        if (f == null) continue;
        int r = f.bytes[(45 * 160 + 80) * 4];
        check ((r - (int) frame_red (i)).abs () <= 6 && ((int) f.bytes[(45 * 160 + 80) * 4 + 1] - (int) frame_green (i)).abs () <= 6,
            "frame %d is exact after seeking (red %d expected %d)".printf (i, r, frame_red (i)));
    }
    reader.close ();
    var audio = new AudioReader (uri, 48000);
    var buf = new float[48000 * 2];
    audio.read (24000, 48000, buf);
    double rms = 0;
    for (int i = 0; i < 48000; i++) rms += buf[i * 2] * buf[i * 2];
    rms = Math.sqrt (rms / 48000);
    close_to (rms, 0.25 / Math.SQRT2, 0.02, "audio reader returns the tone");
    audio.close ();
}

void test_render () throws Error {
    string uri = File.new_for_path (make_video ("count.webm", 75, 25, 160, 90, true)).get_uri ();
    MediaItem m;
    var p = project_with (uri, out m);
    var e = new Edits (p);
    var v1 = p.sequence.tracks_of (TrackKind.VIDEO)[0].id;
    var v2 = p.sequence.tracks_of (TrackKind.VIDEO)[1].id;
    var a = e.make_media_clips (m, 500000000, 2500000000, v1, null);
    e.place (a, S, false);
    var r = new Renderer (p, p.sequence, 1);
    var img = r.render (1500000000);
    check (img.width == 320 && img.height == 180, "canvas size");
    close_to (red_at (img, 160, 90), frame_red (25), 6, "timeline maps to the right source frame");
    check (alpha_at (img, 160, 90) > 0.99, "media is opaque");
    var empty = r.render (200000000);
    check (alpha_at (empty, 160, 90) == 0, "gap renders transparent");
    var b = e.make_media_clips (m, 0, S, v2, null);
    e.place (b, S, false);
    b[0].params.ensure ("scale", 100).value = 50;
    b[0].params.ensure ("x", 0).value = 80;
    b[0].params.ensure ("opacity", 100).value = 100;
    r = new Renderer (p, p.sequence, 1);
    img = r.render (1200000000);
    close_to (red_at (img, 240, 90), frame_red (5), 6, "scaled picture in picture shows its own frame");
    close_to (red_at (img, 20, 20), frame_red (17), 6, "background stays outside the inset");
    save_png (img, "engine-pip.png");
    b[0].params.ensure ("opacity", 100).value = 50;
    r = new Renderer (p, p.sequence, 1);
    img = r.render (1200000000);
    double lin_mix = (Tone.decode ((float) (frame_red (5) / 255.0)) + Tone.decode ((float) (frame_red (17) / 255.0))) / 2;
    close_to (red_at (img, 240, 90), Tone.encode ((float) lin_mix) * 255, 8, "opacity mixes in linear light");
    b[0].params.ensure ("opacity", 100).value = 100;
    b[0].params.ensure ("rotation", 0).value = 45;
    r = new Renderer (p, p.sequence, 1);
    img = r.render (1200000000);
    save_png (img, "engine-rotation.png");
    check (alpha_at (img, 240, 90) > 0.99, "rotated inset still covers its centre");
    r.close ();
}

void test_transition_and_title () throws Error {
    var p = new Project ();
    var s = p.sequence;
    s.width = 320;
    s.height = 180;
    var e = new Edits (p);
    var v1 = s.tracks_of (TrackKind.VIDEO)[0].id;
    var red = new Clip ();
    red.kind = ClipKind.COLOR;
    red.color = "#ff0000ff";
    red.track = v1;
    red.duration = 2 * S;
    var blue = new Clip ();
    blue.kind = ClipKind.COLOR;
    blue.color = "#0000ffff";
    blue.track = v1;
    blue.position = 2 * S;
    blue.duration = 2 * S;
    blue.in_point = 0;
    var list = new Gee.ArrayList<Clip> ();
    list.add (red);
    list.add (blue);
    e.place (list, 0, false);
    e.add_transition (red.id, true, "dissolve", S, 0);
    var r = new Renderer (p, s, 1);
    var img = r.render (2 * S);
    float rr, gg, bb, aa;
    img.get_pixel (160, 90, out rr, out gg, out bb, out aa);
    close_to (rr, 0.5, 0.03, "dissolve midpoint has half red in linear light");
    close_to (bb, 0.5, 0.03, "dissolve midpoint has half blue");
    s.transitions[0].kind = "wipe";
    s.transitions[0].softness = 0;
    r = new Renderer (p, s, 1);
    img = r.render (2 * S);
    img.get_pixel (40, 90, out rr, out gg, out bb, out aa);
    check (bb > 0.9, "wipe reveals the next clip on the left");
    img.get_pixel (280, 90, out rr, out gg, out bb, out aa);
    check (rr > 0.9, "wipe keeps the old clip on the right");
    save_png (img, "engine-wipe.png");
    var title = new Clip ();
    title.kind = ClipKind.TITLE;
    title.track = s.tracks_of (TrackKind.VIDEO)[1].id;
    title.duration = 4 * S;
    var tpl = Titles.builtin ()[2];
    title.title = tpl.data.copy ();
    title.title.fields["title"] = "Montage";
    title.title.fields["subtitle"] = "Engine check";
    var tl = new Gee.ArrayList<Clip> ();
    tl.add (title);
    e.place (tl, 0, false);
    r = new Renderer (p, s, 1);
    img = r.render (S);
    save_png (img, "engine-title.png");
    int white = 0;
    for (int x = 0; x < 320; x++) {
        float r2, g2, b2, a2;
        img.get_pixel (x, 81, out r2, out g2, out b2, out a2);
        if (r2 > 0.9 && g2 > 0.9 && b2 > 0.9) white++;
    }
    check (white > 10, "title text is drawn over the picture (%d white pixels)".printf (white));
    var credits = new TitleData ();
    var layer = new TitleLayer ();
    layer.text = "A\nB\nC";
    credits.layers.add (layer);
    credits.mode = "roll";
    var early = Titles.render (credits, 320, 180, 0.3, 0, 10 * S);
    var late = Titles.render (credits, 320, 180, 0.3, 5 * S, 10 * S);
    double ea = 0, la = 0;
    for (int y = 0; y < 180; y++) for (int x = 0; x < 320; x++) {
        ea += alpha_at (early, x, y);
        la += alpha_at (late, x, y);
    }
    check (ea < 1 && la > 50, "rolling credits start below the frame and scroll in");
}

void test_color_and_keying () throws Error {
    var img = new FloatImage.filled (8, 8, 0.2f, 0.2f, 0.2f, 1);
    var state = new FxState ();
    var ctx = new FxContext (state);
    var primary = Catalog.find ("color.primary").create ();
    primary.params.values["exposure"].value = 1;
    VideoFx.apply (primary, img, ctx);
    float r, g, b, a;
    img.get_pixel (0, 0, out r, out g, out b, out a);
    close_to (r, 0.4, 0.001, "exposure +1 doubles linear light");
    primary.params.values["exposure"].value = 0;
    primary.params.values["saturation"].value = 0;
    var colored = new FloatImage.filled (4, 4, 0.8f, 0.1f, 0.1f, 1);
    VideoFx.apply (primary, colored, ctx);
    colored.get_pixel (0, 0, out r, out g, out b, out a);
    check ((r - g).abs () < 1e-4 && (g - b).abs () < 1e-4, "saturation 0 gives grey");
    string cube = TestKit.path ("invert.cube");
    var sb = new StringBuilder ("TITLE \"invert\"\nLUT_3D_SIZE 2\n");
    for (int bi = 0; bi < 2; bi++) for (int gi = 0; gi < 2; gi++) for (int ri = 0; ri < 2; ri++) sb.append ("%d %d %d\n".printf (1 - ri, 1 - gi, 1 - bi));
    FileUtils.set_contents (cube, sb.str);
    var lut = Catalog.find ("color.lut").create ();
    lut.params.texts["file"] = cube;
    var grey = new FloatImage.filled (4, 4, Tone.decode (0.25f), Tone.decode (0.5f), Tone.decode (1), 1);
    VideoFx.apply (lut, grey, ctx);
    grey.get_pixel (0, 0, out r, out g, out b, out a);
    close_to (Tone.encode (r), 0.75, 0.01, "cube LUT inverts red");
    close_to (Tone.encode (b), 0.0, 0.01, "cube LUT inverts blue");
    var table3dl = TestKit.path ("identity.3dl");
    var sb2 = new StringBuilder ("0 1023\n");
    for (int ri = 0; ri < 2; ri++) for (int gi = 0; gi < 2; gi++) for (int bi = 0; bi < 2; bi++) sb2.append ("%d %d %d\n".printf (ri * 1023, gi * 1023, bi * 1023));
    FileUtils.set_contents (table3dl, sb2.str);
    var l3 = Lut3D.load (table3dl);
    float o1, o2, o3;
    l3.apply (0.3f, 0.6f, 0.9f, out o1, out o2, out o3);
    close_to (o1, 0.3, 0.002, "3dl identity red");
    close_to (o3, 0.9, 0.002, "3dl identity blue");
    var screen = new FloatImage (16, 8);
    for (int y = 0; y < 8; y++) for (int x = 0; x < 16; x++) {
        if (x < 8) screen.set_pixel (x, y, Tone.decode (0.1f), Tone.decode (0.85f), Tone.decode (0.15f), 1);
        else screen.set_pixel (x, y, Tone.decode (0.8f), Tone.decode (0.6f), Tone.decode (0.5f), 1);
    }
    var key = Catalog.find ("key.chroma").create ();
    key.params.values["feather"].value = 0;
    VideoFx.apply (key, screen, ctx);
    check (alpha_at (screen, 2, 4) < 0.05, "green screen becomes transparent");
    check (alpha_at (screen, 13, 4) > 0.95, "skin tone stays opaque");
    var curves = Catalog.find ("color.curves").create ();
    curves.params.texts["master"] = "0,0;0.5,0.75;1,1";
    var mid = new FloatImage.filled (2, 2, Tone.decode (0.5f), Tone.decode (0.5f), Tone.decode (0.5f), 1);
    VideoFx.apply (curves, mid, ctx);
    mid.get_pixel (0, 0, out r, out g, out b, out a);
    close_to (Tone.encode (r), 0.75, 0.01, "master curve lifts midtones");
    var wheels = Catalog.find ("color.wheels").create ();
    wheels.params.values["gain-r"].value = 0.5;
    var w = new FloatImage.filled (2, 2, Tone.decode (0.5f), Tone.decode (0.5f), Tone.decode (0.5f), 1);
    VideoFx.apply (wheels, w, ctx);
    w.get_pixel (0, 0, out r, out g, out b, out a);
    check (Tone.encode (r) > 0.7 && (Tone.encode (g) - 0.5).abs () < 0.01, "gain wheel warms highlights");
    var mask = Catalog.find ("mask").create ();
    mask.params.values["feather"].value = 0;
    var masked = new FloatImage.filled (100, 100, 1, 1, 1, 1);
    VideoFx.apply (mask, masked, ctx);
    check (alpha_at (masked, 50, 50) > 0.99 && alpha_at (masked, 5, 5) < 0.01, "rectangular mask keeps only its inside");
    double pq = Tone.nits_to_pq (203);
    close_to (Tone.pq_to_nits (pq), 203, 0.01, "PQ round trip");
    close_to (pq, 0.58, 0.01, "203 nits in PQ");
    close_to (Tone.hlg_to_scene (Tone.scene_to_hlg (0.26)), 0.26, 1e-6, "HLG round trip");
}

void test_mixer () throws Error {
    var p = new Project ();
    var s = p.sequence;
    var e = new Edits (p);
    string uri = File.new_for_path (make_wav ("tone.wav", 4, 1000, 0.5)).get_uri ();
    var m = Probe.probe (uri);
    p.media.add (m);
    var a1 = s.tracks_of (TrackKind.AUDIO)[0];
    var clips = e.make_media_clips (m, 0, 4 * S, null, a1.id);
    e.place (clips, 0, false);
    var mixer = new AudioMixer (p, s, 48000);
    var buf = new float[48000 * 2];
    mixer.render (48000, 48000, buf);
    double rms = 0;
    for (int i = 0; i < 48000; i++) rms += buf[i * 2] * buf[i * 2];
    rms = Math.sqrt (rms / 48000);
    close_to (rms, 0.5 / Math.SQRT2, 0.01, "mixer passes a centred clip at unity");
    clips[0].params.ensure ("volume", 0).value = -6;
    a1.volume.value = -6;
    mixer.render (48000, 48000, buf);
    rms = 0;
    for (int i = 0; i < 48000; i++) rms += buf[i * 2] * buf[i * 2];
    rms = Math.sqrt (rms / 48000);
    close_to (Singularity.Audio.gain_to_db (rms / (0.5 / Math.SQRT2)), -12, 0.2, "clip and track gain add up");
    clips[0].params.values["volume"].value = 0;
    a1.volume.value = 0;
    a1.pan.value = 100;
    mixer.render (48000, 4800, buf);
    double left = 0, right = 0;
    for (int i = 0; i < 4800; i++) {
        left += buf[i * 2].abs ();
        right += buf[i * 2 + 1].abs ();
    }
    check (left < right * 0.01, "hard right pan silences the left channel");
    a1.pan.value = 0;
    a1.muted = true;
    mixer.render (0, 4800, buf);
    double sum = 0;
    for (int i = 0; i < 9600; i++) sum += buf[i].abs ();
    check (sum == 0, "muted track is silent");
    a1.muted = false;
    var comp = Catalog.find ("audio.limiter").create ();
    comp.params.values["ceiling"].value = -12;
    a1.effects.add (comp);
    mixer.render (48000, 24000, buf);
    float peak = 0;
    for (int i = 4000; i < 48000; i++) peak = float.max (peak, buf[i].abs ());
    check (peak <= (float) Singularity.Audio.db_to_gain (-12) + 1e-3, "track limiter holds the ceiling (peak %.3f)".printf (peak));
    a1.effects.clear ();
    var tr = new Transition ();
    tr.track = a1.id;
    tr.from_clip = "";
    tr.to_clip = clips[0].id;
    tr.kind = "constant-gain";
    tr.duration = S;
    tr.align = 1;
    s.transitions.add (tr);
    var fresh = new AudioMixer (p, s, 48000);
    fresh.render (0, 48000, buf);
    double first = 0, last = 0;
    for (int i = 0; i < 4800; i++) first += buf[i * 2] * buf[i * 2];
    for (int i = 43200; i < 48000; i++) last += buf[i * 2] * buf[i * 2];
    check (first < last * 0.1, "fade in starts quiet");
    fresh.close ();
    mixer.close ();
}

void test_frame_cache_and_composition () throws Error {
    var cache = new FrameCache (File.new_for_path (TestKit.path ("cache")));
    var img = new FloatImage.filled (32, 16, 0.5f, 0.25f, 0.1f, 1);
    cache.store ("abcdef", img, true);
    cache.clear_memory ();
    var back = cache.lookup ("abcdef", 32, 16);
    check (back != null, "disk cache returns the frame");
    if (back != null) {
        float r, g, b, a;
        back.get_pixel (3, 3, out r, out g, out b, out a);
        close_to (r, 0.5, 0.01, "cached frame keeps its colour");
    }
    check (cache.disk_hits == 1, "the second level was used");
    string comp = """{"format":"keyframe-composition","width":320,"height":180,"duration":2000000000,
      "layers":[{"type":"rect","fill":"#ff0000ff","props":{"x":{"value":0,"keys":[{"t":0,"v":0,"i":"linear"},{"t":1000000000,"v":320,"i":"linear"}]},"y":90,"width":40,"height":40}}]}""";
    string file = TestKit.path ("moving.json");
    FileUtils.set_contents (file, comp);
    var c = Composition.load (File.new_for_path (file));
    var frame = c.render (500000000, 320, 180);
    check (alpha_at (frame, 160, 90) > 0.99 && alpha_at (frame, 20, 90) < 0.01, "composition animates its layer");
}

void test_media_cache () throws Error {
    string uri = File.new_for_path (make_video ("count.webm", 75, 25, 160, 90, true)).get_uri ();
    var thumb = MediaCache.compute_thumb (uri, Tc.SECOND);
    check (thumb != null && thumb.height == 72, "thumbnail is generated");
    var peaks = MediaCache.compute_peaks (uri);
    check (peaks != null && peaks.values.length >= 290 && peaks.values.length < 420, "waveform peaks cover the media (%d)".printf (peaks != null ? peaks.values.length : 0));
    if (peaks != null) close_to (peaks.at (1.5), 0.25, 0.03, "peak level matches the tone");
}

void test_reader_sequence () throws Error {
    string? media = Environment.get_variable ("MONTAGE_EXTRA_MEDIA");
    if (media == null) return;
    string uri = File.new_for_path (media).get_uri ();
    var p = new Project ();
    var m = Probe.probe (uri);
    p.media.add (m);
    var e = new Edits (p);
    e.place (e.make_media_clips (m, 0, m.duration, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null), 0, false);
    Importing_match (p, m);
    var r = new Renderer (p, p.sequence, 0.5);
    r.cache = new FrameCache (null);
    foreach (int64 t in new int64[] { 0, 3000000000, 0, 3000000000, 6000000000 }) {
        var img = r.render (t);
        save_png (img, "seq-%lld.png".printf (t / 1000000000));
    }
    var fresh = new Renderer (p, p.sequence, 0.5);
    save_png (fresh.render_uncached (3000000000), "fresh-3.png");
    var cold = new Renderer (p, p.sequence, 0.5, true);
    save_png (cold.render (5000000000), "fresh-5.png");
}

void Importing_match (Project p, MediaItem m) {
    p.sequence.width = m.width;
    p.sequence.height = m.height;
    p.sequence.fps_n = m.fps_n;
    p.sequence.fps_d = m.fps_d;
}

void test_installed_filters () throws Error {
    var list = Catalog.installed_filters ();
    bool balance = false;
    foreach (var f in list) if (f.type == "gst:videobalance") balance = true;
    check (list.size > 5 && balance, "installed GStreamer video filters are listed (%d)".printf (list.size));
    var e = Catalog.find ("gst:videobalance").create ();
    e.params.texts["props"] = "saturation=0";
    var img = new FloatImage.filled (32, 16, Tone.decode (0.8f), Tone.decode (0.2f), Tone.decode (0.2f), 1);
    var ctx = new FxContext (new FxState ());
    VideoFx.apply (e, img, ctx);
    float r, g, b, a;
    img.get_pixel (4, 4, out r, out g, out b, out a);
    check ((r - g).abs () < 0.03 && (g - b).abs () < 0.03, "a GStreamer filter runs as an effect (desaturated)");
}

void test_showcase () throws Error {
    string uri = File.new_for_path (make_video ("count.webm", 75, 25, 160, 90, true)).get_uri ();
    var p = new Project ();
    var s = p.sequence;
    var m = Probe.probe (uri);
    p.media.add (m);
    var e = new Edits (p);
    var v1 = s.tracks_of (TrackKind.VIDEO)[0].id;
    var v2 = s.tracks_of (TrackKind.VIDEO)[1].id;
    var base_clip = e.make_media_clips (m, 0, 3 * S, v1, null);
    e.place (base_clip, 0, false);
    var grade = Catalog.find ("color.wheels").create ();
    grade.params.values["gain-b"].value = 0.3;
    grade.params.values["lift-r"].value = 0.1;
    base_clip[0].effects.add (grade);
    var vig = Catalog.find ("vignette").create ();
    vig.params.values["amount"].value = 60;
    base_clip[0].effects.add (vig);
    var inset = e.make_media_clips (m, S, 3 * S, v2, null);
    e.place (inset, 0, false);
    inset[0].params.ensure ("scale", 100).value = 40;
    inset[0].params.ensure ("x", 0).value = 520;
    inset[0].params.ensure ("y", 0).value = -260;
    inset[0].params.ensure ("rotation", 0).value = -6;
    var t3 = e.add_track (TrackKind.VIDEO);
    var title = new Clip ();
    title.kind = ClipKind.TITLE;
    title.track = t3.id;
    title.duration = 3 * S;
    title.title = Titles.builtin ()[1].data.copy ();
    title.title.fields["name"] = "Montage";
    title.title.fields["role"] = "Multitrack engine, linear light";
    var tl = new Gee.ArrayList<Clip> ();
    tl.add (title);
    e.place (tl, 0, false);
    var r = new Renderer (p, s, 0.5);
    save_png (r.render (1500000000), "showcase-composite.png");
    var big = new Clip ();
    big.kind = ClipKind.TITLE;
    big.track = t3.id;
    big.duration = 2 * S;
    big.title = Titles.builtin ()[2].data.copy ();
    big.title.fields["title"] = "MONTAGE";
    big.title.fields["subtitle"] = "Titles with outline and shadow";
    var bl = new Gee.ArrayList<Clip> ();
    bl.add (big);
    e.place (bl, 4 * S, false);
    var c1 = new Clip ();
    c1.kind = ClipKind.COLOR;
    c1.color = "#204070ff";
    c1.track = v1;
    c1.duration = 2 * S;
    var cl = new Gee.ArrayList<Clip> ();
    cl.add (c1);
    e.place (cl, 4 * S, false);
    r = new Renderer (p, s, 0.5);
    save_png (r.render (5 * S), "showcase-title.png");
    e.add_transition (base_clip[0].id, true, "iris", 2 * S, 0);
    r = new Renderer (p, s, 0.5);
    save_png (r.render (2900000000), "showcase-iris.png");
}

int main (string[] args) {
    init (args);
    try {
        test_probe_and_decoder ();
        test_render ();
        test_transition_and_title ();
        test_color_and_keying ();
        test_mixer ();
        test_frame_cache_and_composition ();
        test_showcase ();
        test_installed_filters ();
        test_media_cache ();
        test_reader_sequence ();
    } catch (Error e) {
        check (false, "unexpected error: " + e.message);
    }
    return finish ("engine");
}
