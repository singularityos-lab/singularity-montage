using Singularity.Apps.Montage;
using Singularity.Apps.Montage.TestKit;
using Singularity.Imaging;

const int64 S = 1000000000;

string uri_of (string file) {
    return File.new_for_path (file).get_uri ();
}

Project with_media (string uri, out MediaItem m) throws Error {
    var p = new Project ();
    p.sequence.width = 320;
    p.sequence.height = 180;
    p.sequence.fps_n = 25;
    m = Probe.probe (uri);
    p.media.add (m);
    return p;
}

double red_of (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return Tone.encode (r) * 255;
}

string make_tone_at (string name, double seconds, double start, double tone) throws Error {
    string file = TestKit.path (name);
    if (FileUtils.test (file, FileTest.EXISTS)) return file;
    var pipeline = (Gst.Pipeline) Gst.parse_launch ("appsrc name=a format=time ! audioconvert ! wavenc ! filesink location=\"%s\"".printf (file));
    var a = (Gst.App.Src) pipeline.get_by_name ("a");
    a.caps = Gst.Caps.from_string ("audio/x-raw,format=F32LE,layout=interleaved,rate=48000,channels=2,channel-mask=(bitmask)0x3");
    pipeline.set_state (Gst.State.PLAYING);
    int total = (int) (seconds * 48000);
    var s = new float[total * 2];
    uint seed = 7;
    for (int i = 0; i < total; i++) {
        double t = (double) i / 48000;
        float v = 0;
        for (int k = 0; k < 4; k++) {
            double bang = start + k * 1.3;
            if (t >= bang && t < bang + 0.15) {
                seed = seed * 1103515245 + 12345;
                v = (float) (((seed >> 8) & 0xffff) / 65535.0 - 0.5) * 0.8f;
            }
        }
        v += (float) (0.02 * Math.sin (2 * Math.PI * tone * t));
        s[i * 2] = v;
        s[i * 2 + 1] = v;
    }
    uint8[] bytes = new uint8[s.length * 4];
    Memory.copy (bytes, s, bytes.length);
    var buf = new Gst.Buffer.wrapped ((owned) bytes);
    buf.pts = 0;
    buf.duration = (int64) (seconds * Gst.SECOND);
    a.push_buffer (buf);
    a.end_of_stream ();
    pipeline.get_bus ().timed_pop_filtered (60 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
    pipeline.set_state (Gst.State.NULL);
    return file;
}

string make_scenes (string name) throws Error {
    string file = TestKit.path (name);
    if (FileUtils.test (file, FileTest.EXISTS)) return file;
    var pipeline = (Gst.Pipeline) Gst.parse_launch ("appsrc name=v format=time ! videoconvert ! vp8enc deadline=1 ! webmmux ! filesink location=\"%s\"".printf (file));
    var v = (Gst.App.Src) pipeline.get_by_name ("v");
    v.caps = Gst.Caps.from_string ("video/x-raw,format=RGBA,width=160,height=90,framerate=25/1");
    pipeline.set_state (Gst.State.PLAYING);
    uint8[,] colors = { { 220, 40, 40 }, { 40, 200, 60 }, { 40, 60, 220 }, { 230, 220, 60 } };
    for (int i = 0; i < 100; i++) {
        int scene = i / 25;
        var data = new uint8[160 * 90 * 4];
        for (int p = 0; p < 160 * 90; p++) {
            int x = p % 160;
            data[p * 4] = (uint8) (colors[scene, 0] * (x + 40) / 200);
            data[p * 4 + 1] = (uint8) (colors[scene, 1] * (x + 40) / 200);
            data[p * 4 + 2] = (uint8) (colors[scene, 2] * (x + 40) / 200);
            data[p * 4 + 3] = 255;
        }
        var buf = new Gst.Buffer.wrapped ((owned) data);
        buf.pts = i * 40 * Gst.MSECOND;
        buf.duration = 40 * Gst.MSECOND;
        v.push_buffer (buf);
    }
    v.end_of_stream ();
    pipeline.get_bus ().timed_pop_filtered (60 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
    pipeline.set_state (Gst.State.NULL);
    return file;
}

string make_shaky (string name) throws Error {
    string file = TestKit.path (name);
    if (FileUtils.test (file, FileTest.EXISTS)) return file;
    var pipeline = (Gst.Pipeline) Gst.parse_launch ("appsrc name=v format=time ! videoconvert ! vp8enc deadline=1 target-bitrate=2000000 ! webmmux ! filesink location=\"%s\"".printf (file));
    var v = (Gst.App.Src) pipeline.get_by_name ("v");
    v.caps = Gst.Caps.from_string ("video/x-raw,format=RGBA,width=320,height=180,framerate=25/1");
    pipeline.set_state (Gst.State.PLAYING);
    for (int i = 0; i < 50; i++) {
        int dx = (int) Math.round (6 * Math.sin (i * 1.7)), dy = (int) Math.round (5 * Math.cos (i * 2.3));
        var data = new uint8[320 * 180 * 4];
        for (int y = 0; y < 180; y++) for (int x = 0; x < 320; x++) {
            int sx = x - dx, sy = y - dy;
            bool box = ((sx / 20) + (sy / 20)) % 2 == 0;
            bool target = sx > 140 && sx < 180 && sy > 70 && sy < 110;
            int o = (y * 320 + x) * 4;
            data[o] = target ? 250 : (box ? 200 : 40);
            data[o + 1] = target ? 30 : (box ? 200 : 40);
            data[o + 2] = target ? 30 : (box ? 200 : 40);
            data[o + 3] = 255;
        }
        var buf = new Gst.Buffer.wrapped ((owned) data);
        buf.pts = i * 40 * Gst.MSECOND;
        buf.duration = 40 * Gst.MSECOND;
        v.push_buffer (buf);
    }
    v.end_of_stream ();
    pipeline.get_bus ().timed_pop_filtered (60 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
    pipeline.set_state (Gst.State.NULL);
    return file;
}

void test_proxy_and_prerender () throws Error {
    string uri = uri_of (make_video ("count.webm", 75, 25, 160, 90, true));
    MediaItem m;
    var p = with_media (uri, out m);
    var pm = new ProxyManager (p);
    string out_path = TestKit.path ("proxy.mkv");
    pm.generate (uri, out_path, 96, 54, 25, 1, true, m.duration, m.id);
    var proxy = Probe.probe (uri_of (out_path));
    check (proxy.height == 54 && proxy.has_audio, "proxy is small and keeps the sound");
    close_to ((double) proxy.duration / S, 3, 0.1, "proxy keeps the length");
    check ((proxy.metadata["video codec"] ?? "").down ().contains ("jpeg"), "proxy is intra frame (%s)".printf (proxy.metadata["video codec"] ?? ""));
    m.proxy_uri = uri_of (out_path);
    m.proxy_state = "ready";
    var e = new Edits (p);
    e.place (e.make_media_clips (m, 0, 2 * S, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null), 0, false);
    var with_proxy = new Renderer (p, p.sequence, 1, true);
    close_to (red_of (with_proxy.render (S), 160, 90), frame_red (25), 10, "playback through the proxy shows the right frame");
    var original = new Renderer (p, p.sequence, 1, false);
    close_to (red_of (original.render (S), 160, 90), frame_red (25), 6, "export renders from the original");
    check (!Prerender.heavy (p, p.sequence, S), "a single plain clip is not heavy");
    var fx = Catalog.find ("blur").create ();
    p.sequence.clips[0].effects.add (fx);
    check (Prerender.heavy (p, p.sequence, S), "a clip with effects is pre rendered");
    var cache = new FrameCache (File.new_for_path (TestKit.path ("prerender")));
    var pre = new Prerender (p, cache);
    pre.scale = 0.5;
    var loop = new MainLoop ();
    pre.updated.connect (() => {
        if (pre.heavy_starts.size > 0 && pre.is_done (pre.heavy_ends[0] - p.sequence.frame)) loop.quit ();
    });
    pre.schedule ();
    Timeout.add_seconds (60, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    check (pre.heavy_starts.size == 1 && pre.is_done (S), "background render fills the heavy section");
    var r = new Renderer (p, p.sequence, 0.5, p.use_proxies);
    r.cache = cache;
    r.render (S);
    check (cache.hits + cache.disk_hits >= 1, "playback reuses the background render");
    p.sequence.clips[0].effects[0].params.values["radius"].value = 3;
    r.render (S);
    check (cache.misses >= 1, "editing the effect invalidates the cached frame");
}

void test_scene_sync_stabilize_track () throws Error {
    var cuts = Analysis.detect_scenes (uri_of (make_scenes ("scenes.webm")), 0, -1, 0.6);
    check (cuts.size == 3, "three scene changes detected (%d)".printf (cuts.size));
    if (cuts.size == 3) close_to ((double) cuts[1] / S, 2, 0.05, "second cut at 2 s");
    string a = make_tone_at ("cam-a.wav", 8, 1.0, 300);
    string b = make_tone_at ("cam-b.wav", 8, 2.25, 500);
    double conf;
    int64 off = Analysis.audio_offset (uri_of (a), uri_of (b), 5 * S, out conf);
    close_to ((double) off / S, -1.25, 0.02, "audio sync finds the 1.25 s offset (confidence %.2f)".printf (conf));
    string shaky = uri_of (make_shaky ("shaky.webm"));
    string data = Analysis.stabilize (shaky, 0, -1, 0.5);
    var stab = StabilizeData.parse (data);
    check (stab.size >= 45, "motion analysed for every frame (%d)".printf (stab.size));
    double x, y, ang;
    if (Environment.get_variable ("MONTAGE_DEBUG_STAB") != null) for (int i = 0; i < 20; i++) {
        stab.lookup ((int64) i * 40000000, out x, out y, out ang);
        printerr ("stab %d x %.2f y %.2f a %.4f expected %.2f %.2f\n", i, x, y, ang, -6 * Math.sin (i * 1.7), -5 * Math.cos (i * 2.3));
    }
    stab.lookup (11 * 40 * 1000000, out x, out y, out ang);
    double expected = -6 * Math.sin (11 * 1.7);
    check ((x - expected).abs () < 3.5, "stabilizer counters the shake (%.1f vs %.1f)".printf (x, expected));
    var times = new Gee.ArrayList<int64?> ();
    var xs = new Gee.ArrayList<double?> ();
    var ys = new Gee.ArrayList<double?> ();
    Analysis.track_point (shaky, 0, -1, 160, 90, 40, 320, 180, times, xs, ys);
    check (times.size >= 45, "point tracked through the clip");
    bool follows = true;
    for (int i = 0; i < times.size; i++) {
        int fi = (int) (times[i] / 40000000);
        double ex = 160 + Math.round (6 * Math.sin (fi * 1.7));
        if ((xs[i] - ex).abs () > 3) follows = false;
    }
    check (follows, "mask tracking follows the moving target");
}

void test_multicam_speed_adjustment () throws Error {
    string ua = uri_of (make_video ("count.webm", 75, 25, 160, 90, true));
    string ub = uri_of (make_scenes ("scenes.webm"));
    MediaItem a;
    var p = with_media (ua, out a);
    var b = Probe.probe (ub);
    p.media.add (b);
    var mc = new MediaItem ();
    mc.kind = "multicam";
    mc.name = "Multicam";
    mc.angles.add (new MulticamAngle (a.id, "A", 0));
    mc.angles.add (new MulticamAngle (b.id, "B", 0));
    mc.duration = 3 * S;
    mc.has_video = true;
    mc.width = 160;
    mc.height = 90;
    p.media.add (mc);
    var e = new Edits (p);
    var clips = e.make_media_clips (mc, 0, 3 * S, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null);
    e.place (clips, 0, false);
    var c = clips[0];
    c.cuts.add (new MulticamCut (0, 0));
    c.cuts.add (new MulticamCut (S, 1));
    var r = new Renderer (p, p.sequence, 1);
    close_to (red_of (r.render (500000000), 160, 90), frame_red (12), 6, "angle A before the cut");
    var cut_img = r.render (1500000000);
    float cr, cg, cb, ca;
    cut_img.get_pixel (160, 90, out cr, out cg, out cb, out ca);
    check (Tone.encode (cg) > 0.4 && Tone.encode (cr) < 0.2, "angle B after the cut shows the second camera");
    p.sequence.clips.clear ();
    var sc = e.make_media_clips (a, 0, 3 * S, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null);
    e.place (sc, 0, false);
    e.set_speed (sc[0].id, 50, false, true, true);
    check (p.sequence.clips[0].duration == 6 * S, "half speed doubles the length");
    r = new Renderer (p, p.sequence, 1);
    double mid = red_of (r.render (1020000000), 160, 90);
    double f12 = frame_red (12), f13 = frame_red (13);
    check (mid > double.min (f12, f13) + 1 && mid < double.max (f12, f13) - 1, "frame blending mixes neighbouring frames (%.1f)".printf (mid));
    var ramp = p.sequence.clips[0].params.ensure ("speed", 100);
    ramp.keys.clear ();
    ramp.set_key (0, 100);
    ramp.set_key (2 * S, 300);
    int64 at2 = p.sequence.clips[0].source_time (S);
    check (at2 > S && at2 < 2 * S, "speed ramp accelerates the source");
    p.sequence.clips[0].reverse = true;
    ramp.keys.clear ();
    ramp.value = 100;
    p.sequence.clips[0].duration = 3 * S;
    check (p.sequence.clips[0].source_time (0) > 2 * S, "reverse plays from the end");
    p.sequence.clips[0].reverse = false;
    var adj = new Clip ();
    adj.kind = ClipKind.ADJUSTMENT;
    adj.track = p.sequence.tracks_of (TrackKind.VIDEO)[1].id;
    adj.duration = 3 * S;
    var bw = Catalog.find ("color.bw").create ();
    adj.effects.add (bw);
    var list = new Gee.ArrayList<Clip> ();
    list.add (adj);
    e.place (list, 0, false);
    r = new Renderer (p, p.sequence, 1);
    var img = r.render (S / 2);
    float rr, gg, bb, aa;
    img.get_pixel (40, 45, out rr, out gg, out bb, out aa);
    check ((rr - gg).abs () < 0.01 && (gg - bb).abs () < 0.01 && aa > 0.99, "adjustment layer greys everything below it");
}

void test_color_match_and_hue () throws Error {
    var src = new FloatImage.filled (16, 16, Tone.decode (0.3f), Tone.decode (0.4f), Tone.decode (0.5f), 1);
    for (int i = 0; i < 16; i++) src.set_pixel (i, 0, Tone.decode (0.1f), Tone.decode (0.2f), Tone.decode (0.3f), 1);
    var reference = new FloatImage.filled (16, 16, Tone.decode (0.6f), Tone.decode (0.5f), Tone.decode (0.3f), 1);
    for (int i = 0; i < 16; i++) reference.set_pixel (i, 0, Tone.decode (0.5f), Tone.decode (0.4f), Tone.decode (0.2f), 1);
    var e = Analysis.match_color (src, reference, "ref");
    var copy = src.copy ();
    VideoFx.apply (e, copy, new FxContext (new FxState ()));
    var m1 = new double[3];
    var s1 = new double[3];
    var m2 = new double[3];
    var s2 = new double[3];
    Analysis.color_stats (copy, m1, s1);
    Analysis.color_stats (reference, m2, s2);
    for (int c = 0; c < 3; c++) close_to (m1[c], m2[c], 0.02, "colour match aligns channel %d".printf (c));
    var curves = Catalog.find ("color.curves").create ();
    curves.params.texts["hue-sat"] = "0,0;0.5,0.5;1,0";
    var red = new FloatImage.filled (2, 2, Tone.decode (0.8f), Tone.decode (0.2f), Tone.decode (0.2f), 1);
    VideoFx.apply (curves, red, new FxContext (new FxState ()));
    float r, g, b, a;
    red.get_pixel (0, 0, out r, out g, out b, out a);
    check ((Tone.encode (r) - Tone.encode (g)).abs () < 0.02, "hue vs saturation curve removes red saturation");
}

void test_mixer_buses_automation_duck () throws Error {
    var p = new Project ();
    var s = p.sequence;
    var e = new Edits (p);
    var voice = Probe.probe (uri_of (make_tone_at ("voice.wav", 6, 1.0, 200)));
    var music = Probe.probe (uri_of (make_wav ("music.wav", 6, 440, 0.3)));
    p.media.add (voice);
    p.media.add (music);
    var a1 = s.tracks_of (TrackKind.AUDIO)[0];
    var a2 = s.tracks_of (TrackKind.AUDIO)[1];
    var vc = e.make_media_clips (voice, 0, 6 * S, null, a1.id);
    e.place (vc, 0, false);
    var mc = e.make_media_clips (music, 0, 6 * S, null, a2.id);
    e.place (mc, 0, false);
    vc[0].role = "dialogue";
    mc[0].role = "music";
    var bus = new Singularity.Apps.Montage.Bus ("Music Bus");
    bus.volume.value = -12;
    s.buses.add (bus);
    a2.bus = bus.id;
    a1.muted = true;
    var mixer = new AudioMixer (p, s, 48000);
    var buf = new float[48000 * 2];
    mixer.render (0, 48000, buf);
    double rms = 0;
    for (int i = 4800; i < 48000; i++) rms += buf[i * 2] * buf[i * 2];
    rms = Math.sqrt (rms / 43200);
    close_to (Singularity.Audio.gain_to_db (rms / (0.3 / Math.SQRT2)), -12, 0.3, "bus volume applies to routed tracks");
    a1.muted = false;
    var vol = mc[0].params.ensure ("volume", 0);
    vol.set_key (0, 0);
    vol.set_key (2 * S, -20);
    mixer.close ();
    mixer = new AudioMixer (p, s, 48000);
    a1.muted = true;
    mixer.render (2 * 48000 + 4800, 4800, buf);
    rms = 0;
    for (int i = 0; i < 4800; i++) rms += buf[i * 2] * buf[i * 2];
    rms = Math.sqrt (rms / 4800);
    close_to (Singularity.Audio.gain_to_db (rms / (0.3 / Math.SQRT2)), -32, 0.5, "volume automation keyframes shape the clip");
    a1.muted = false;
    vol.keys.clear ();
    vol.value = 0;
    var plan = Analysis.plan_duck (p.clone (), s.id, -15);
    int keys = Analysis.apply_duck (p, s, plan);
    check (keys > 4, "ducking writes volume keyframes (%d)".printf (keys));
    var music_vol = s.clip (mc[0].id).params.values["volume"];
    if (Environment.get_variable ("MONTAGE_DEBUG_STAB") != null) for (int i = 0; i < 30; i++) printerr ("duck %.1f %.2f\n", i / 10.0, music_vol.at (i * 100000000L));
    check (music_vol.at (1050 * 1000000) < -8 && music_vol.at (500 * 1000000) > -2, "music dips while the voice speaks");
}

void test_subtitles_transcript () throws Error {
    string srt = "1\n00:00:01,000 --> 00:00:02,500\nHello <i>there</i>\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond line\nwith two rows\n";
    var cues = Subtitles.parse (srt);
    check (cues.size == 2 && cues[0].text == "Hello there" && cues[0].start == S && cues[0].end == 2500000000, "SRT is parsed and tags removed");
    var vtt = Subtitles.parse (Subtitles.to_vtt (cues));
    check (vtt.size == 2 && vtt[1].text == "Second line\nwith two rows", "WebVTT round trip");
    check (Subtitles.to_srt (cues).contains ("00:00:01,000 --> 00:00:02,500"), "SRT writer uses commas");
    var p = new Project ();
    Subtitles.add_cues (p, cues, "Import");
    check (Subtitles.all (p.sequence).size == 2 && p.sequence.tracks_of (TrackKind.SUBTITLE).size == 1, "captions become a subtitle track");
    var r = new Renderer (p, p.sequence, 0.25);
    var img = r.render (1500000000);
    int white = 0;
    for (int y = 0; y < img.height; y++) for (int x = 0; x < img.width; x++) {
        float rr, gg, bb, aa;
        img.get_pixel (x, y, out rr, out gg, out bb, out aa);
        if (aa > 0.9 && rr > 0.9) white++;
    }
    check (white > 20, "captions burn into the picture");
    var words = new Gee.ArrayList<Word> ();
    string[] text = { "This", "is", "a", "short", "test.", "Then", "another", "sentence", "follows", "here." };
    for (int i = 0; i < text.length; i++) words.add (new Word (text[i], i * 400000000L, i * 400000000L + 350000000));
    var made = Transcript.to_cues (words, 20);
    check (made.size >= 2 && made[0].text.has_prefix ("This is a short"), "transcript becomes readable captions");
    var back = Transcript.parse (Transcript.serialize (words));
    check (back.size == 10 && back[4].text == "test.", "transcript is stored with timings");
    string script = TestKit.path ("fake-asr.sh");
    FileUtils.set_contents (script, "#!/bin/sh\necho hello world from the voice\n");
    FileUtils.chmod (script, 0755);
    var backend = new CommandSpeechBackend (script + " {file} {language}");
    var spoken = Speech.transcribe (uri_of (make_tone_at ("speech.wav", 6, 1.0, 200)), 0, 6 * S, "en", backend, TestKit.path ("asr"));
    check (spoken.size >= 5 && spoken[0].start >= 800000000 && spoken[0].start < 1300000000, "speech segments are timed from the audio (%d words, first at %lld)".printf (spoken.size, spoken.size > 0 ? spoken[0].start : -1));
}

void test_review_and_shared () throws Error {
    var p = new Project ();
    var c = new ReviewComment ();
    c.time = 2 * S;
    c.text = "Trim this";
    c.author = "Editor";
    p.sequence.comments.add (c);
    string json = Review.comments_json (p.sequence);
    var o = Js.parse (json);
    var list = Js.objects (o, "comments");
    var reply = new Json.Object ();
    reply.set_string_member ("author", "Client");
    reply.set_string_member ("text", "Agreed");
    reply.set_int_member ("created", 10);
    var replies = new Json.Array ();
    replies.add_object_element (reply);
    list[0].set_array_member ("replies", replies);
    list[0].set_boolean_member ("resolved", true);
    var extra = new Json.Object ();
    extra.set_string_member ("id", "new1");
    extra.set_int_member ("time", 5 * S);
    extra.set_string_member ("text", "Colour is too warm");
    extra.set_string_member ("author", "Client");
    o.get_array_member ("comments").add_object_element (extra);
    var node = new Json.Node (Json.NodeType.OBJECT);
    node.set_object (o);
    int n = Review.merge (p, p.sequence, Js.write (node));
    check (n == 2 && p.sequence.comments.size == 2 && p.sequence.comments[0].resolved && p.sequence.comments[0].replies.size == 1, "review replies and new comments merge back");
    string html = Review.html (p.sequence, "review.mp4");
    check (html.contains ("<video") && html.contains ("Trim this") && html.contains ("Download Comments"), "review page carries the player and comments");
    var file = File.new_for_path (TestKit.path ("shared/project.montage"));
    DirUtils.create_with_parents (TestKit.path ("shared"), 0755);
    NativeFormat.save (p, file);
    SharedProject.acquire (file, p.sequence.id);
    check (SharedProject.holder (file, p.sequence.id) == SharedProject.me (), "sequence lock is taken");
    var lock_file = File.new_for_path (TestKit.path ("shared/.project.montage.locks/" + p.sequence.id + ".lock"));
    FileUtils.set_contents (lock_file.get_path (), "someone@elsewhere\n");
    SharedProject.refresh_locks (p, file);
    var e = new Edits (p);
    var m = new MediaItem ();
    m.uri = "file:///x.webm";
    m.duration = 5 * S;
    m.has_video = true;
    p.media.add (m);
    var clips = e.make_media_clips (m, 0, S, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null);
    p.sequence.clips.add_all (clips);
    bool refused = false;
    try {
        e.split (S / 2, new Gee.ArrayList<string> ());
    } catch (Error err) {
        refused = true;
    }
    check (refused, "a sequence locked by someone else cannot be edited");
    var theirs = NativeFormat.load (file);
    theirs.sequence.name = "Their Edit";
    NativeFormat.save (theirs, file);
    p.sequence.name = "Mine";
    int merged = SharedProject.merge_from_disk (p, file);
    check (merged >= 1 && p.sequence.name == "Their Edit", "saving takes the sequence edited by the lock holder");
}

void test_session_recovery () throws Error {
    Environment.set_variable ("XDG_STATE_HOME", TestKit.path ("state"), true);
    var p = new Project ();
    var s = new Session (p);
    p.checkpoint ("x");
    p.sequence.name = "Unsaved Work";
    p.commit ();
    s.write_recovery ();
    var file = Session.recovery_dir ().get_child (s.id + ".lock");
    FileUtils.set_contents (file.get_path (), "999999");
    var orphans = Session.orphans ();
    bool found = false;
    foreach (var o in orphans) if (o.file.get_basename () == s.id + ".montage") found = true;
    check (found, "a crashed session leaves a recoverable project");
    var other = new Session (new Project ());
    foreach (var o in orphans) if (o.file.get_basename () == s.id + ".montage") {
        var back = other.recover (o);
        check (back.sequence.name == "Unsaved Work", "recovery restores the unsaved edit");
    }
    var saved = File.new_for_path (TestKit.path ("versions/proj.montage"));
    DirUtils.create_with_parents (TestKit.path ("versions"), 0755);
    other.versions = 2;
    for (int i = 0; i < 4; i++) {
        other.save (saved);
        Thread.usleep (1100000);
    }
    int kept = 0;
    var dir = saved.get_parent ().get_child ("Montage Auto-Save").enumerate_children ("standard::name", 0);
    while (dir.next_file () != null) kept++;
    check (kept == 2, "earlier versions are kept and pruned (%d)".printf (kept));
}

void test_queue () throws Error {
    string uri = uri_of (make_video ("count.webm", 75, 25, 160, 90, true));
    MediaItem m;
    var p = with_media (uri, out m);
    var e = new Edits (p);
    e.place (e.make_media_clips (m, 0, S, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, p.sequence.tracks_of (TrackKind.AUDIO)[0].id), 0, false);
    var queue = new ExportQueue ();
    var loop = new MainLoop ();
    int finished = 0;
    queue.job_finished.connect ((j, ok, err) => {
        if (!ok) printerr ("job failed: %s\n", err);
        if (++finished == 3) loop.quit ();
    });
    string[] presets = { "webm-1080", "audio-flac", "seq-png" };
    string[] names = { "q.webm", "q.flac", "q.png" };
    for (int i = 0; i < 3; i++) {
        var st = new ExportSettings ();
        st.preset = Presets.find (presets[i]).copy ();
        st.preset.width = 160;
        st.preset.height = 90;
        st.output = File.new_for_path (TestKit.path (names[i]));
        st.end = 400000000;
        queue.add (new ExportJob (p.clone (), st));
    }
    check (queue.pending == 3, "three jobs wait in the queue");
    Timeout.add_seconds (120, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    check (finished == 3 && FileUtils.test (TestKit.path ("q.webm"), FileTest.EXISTS) && FileUtils.test (TestKit.path ("q.flac"), FileTest.EXISTS)
        && FileUtils.test (TestKit.path ("q_000009.png"), FileTest.EXISTS), "the queue runs every job in turn");
    var hdr = new ExportSettings ();
    hdr.preset = Presets.find ("hdr10").copy ();
    hdr.preset.width = 320;
    hdr.preset.height = 180;
    hdr.output = File.new_for_path (TestKit.path ("hdr.mp4"));
    hdr.end = 400000000;
    var job = new ExportJob (p.clone (), hdr);
    try {
        job.run_sync ();
        string ffprobe = Environment.find_program_in_path ("ffprobe") ?? "";
        if (ffprobe != "") {
            string output;
            Process.spawn_command_line_sync ("%s -v error -select_streams v:0 -show_entries stream=pix_fmt,color_transfer,color_primaries -of csv=p=0 %s".printf (ffprobe, GLib.Shell.quote (hdr.output.get_path ())), out output);
            check (output.contains ("10le") && output.contains ("smpte2084") && output.contains ("bt2020"), "HDR10 export is 10 bit PQ Rec.2020 (%s)".printf (output.strip ()));
        }
    } catch (Error err) {
        check (false, "HDR export failed: " + err.message);
    }
}

void test_keyframe_live () throws Error {
    string? sample = Environment.get_variable ("MONTAGE_KEYFRAME_SAMPLE");
    if (sample == null || !FileUtils.test (sample, FileTest.EXISTS) || Gst.ElementFactory.find ("keyframedec") == null) {
        printerr ("keyframe sample not available, skipped\n");
        return;
    }
    string copy = TestKit.path ("live.keyframe");
    var src = File.new_for_path (sample);
    src.copy (File.new_for_path (copy), FileCopyFlags.OVERWRITE);
    var p = new Project ();
    p.sequence.width = 320;
    p.sequence.height = 180;
    var m = Probe.probe (uri_of (copy));
    check (m.has_video && m.duration > 0, "a Keyframe project probes as live video (%s)".printf (Tc.clock (m.duration)));
    p.media.add (m);
    var e = new Edits (p);
    e.place (e.make_media_clips (m, 0, m.duration, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null), 0, false);
    var r = new Renderer (p, p.sequence, 1);
    var img = r.render (m.duration / 2);
    double sum = 0;
    for (int y = 0; y < img.height; y += 4) for (int x = 0; x < img.width; x += 4) {
        float rr, gg, bb, aa;
        img.get_pixel (x, y, out rr, out gg, out bb, out aa);
        sum += aa;
    }
    check (sum > 100, "the composition renders through keyframedec without an intermediate file");
    save_png (img, "keyframe-live.png");
    string sig1 = r.signature (m.duration / 2);
    Thread.usleep (1100000);
    var f = File.new_for_path (copy);
    uint8[] data;
    f.load_contents (null, out data, null);
    f.replace_contents (data, null, false, FileCreateFlags.NONE, null);
    check (r.signature (m.duration / 2) != sig1, "saving the composition invalidates cached frames");
}

void test_bench_4k () throws Error {
    if (Environment.get_variable ("MONTAGE_BENCH") == null) return;
    string file = TestKit.path ("uhd.webm");
    if (!FileUtils.test (file, FileTest.EXISTS)) {
        var pl = (Gst.Pipeline) Gst.parse_launch ("videotestsrc pattern=smpte num-buffers=75 ! video/x-raw,width=3840,height=2160,framerate=25/1 ! timeoverlay ! vp9enc deadline=1 cpu-used=8 threads=8 ! webmmux ! filesink location=\"%s\"".printf (file));
        pl.set_state (Gst.State.PLAYING);
        pl.get_bus ().timed_pop_filtered (600 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
        pl.set_state (Gst.State.NULL);
    }
    MediaItem m;
    var p = with_media (uri_of (file), out m);
    p.sequence.width = 3840;
    p.sequence.height = 2160;
    var e = new Edits (p);
    e.place (e.make_media_clips (m, 0, 3 * S, p.sequence.tracks_of (TrackKind.VIDEO)[0].id, null), 0, false);
    string proxy = TestKit.path ("uhd-proxy.mkv");
    var pm = new ProxyManager (p);
    int64 t0 = get_monotonic_time ();
    pm.generate (m.uri, proxy, 960, 540, 25, 1, false, m.duration, m.id);
    double proxy_seconds = (get_monotonic_time () - t0) / 1e6;
    foreach (bool use in new bool[] { false, true }) {
        if (use) {
            m.proxy_uri = uri_of (proxy);
            m.proxy_state = "ready";
        }
        var r = new Renderer (p, p.sequence, 0.25, use);
        int64 start = get_monotonic_time ();
        for (int i = 0; i < 50; i++) r.render (i * 40000000L);
        double fps = 50 / ((get_monotonic_time () - start) / 1e6);
        printerr ("bench 4K preview at quarter size, %s: %.1f fps\n", use ? "proxy" : "original", fps);
        if (use) check (fps >= 25, "4K timeline plays in real time through the proxy (%.1f fps)".printf (fps));
        r.close ();
    }
    printerr ("bench proxy generation for 3 s of 4K: %.1f s\n", proxy_seconds);
}

int main (string[] args) {
    init (args);
    try {
        test_proxy_and_prerender ();
        test_scene_sync_stabilize_track ();
        test_multicam_speed_adjustment ();
        test_color_match_and_hue ();
        test_mixer_buses_automation_duck ();
        test_subtitles_transcript ();
        test_review_and_shared ();
        test_session_recovery ();
        test_queue ();
        test_keyframe_live ();
        test_bench_4k ();
    } catch (Error e) {
        check (false, "unexpected error: " + e.message);
    }
    return finish ("features");
}
