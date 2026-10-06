using Singularity.Apps.Montage;
using Singularity.Apps.Montage.TestKit;
using Singularity.Imaging;

const int64 S = 1000000000;

Project timeline () throws Error {
    var p = new Project ();
    var s = p.sequence;
    s.width = 320;
    s.height = 180;
    s.fps_n = 25;
    var e = new Edits (p);
    string uri = File.new_for_path (make_video ("count.webm", 75, 25, 160, 90, true)).get_uri ();
    var m = Probe.probe (uri);
    p.media.add (m);
    var clips = e.make_media_clips (m, 0, 2 * S, s.tracks_of (TrackKind.VIDEO)[0].id, s.tracks_of (TrackKind.AUDIO)[0].id);
    e.place (clips, 0, false);
    var title = new Clip ();
    title.kind = ClipKind.TITLE;
    title.track = s.tracks_of (TrackKind.VIDEO)[1].id;
    title.duration = S;
    title.title = Titles.builtin ()[0].data.copy ();
    var l = new Gee.ArrayList<Clip> ();
    l.add (title);
    e.place (l, 500000000, false);
    e.add_marker (0, "Opening", "chapter");
    e.add_marker (S, "Second", "chapter");
    var sub = new Gee.ArrayList<Cue> ();
    sub.add (new Cue (200000000, 900000000, "Hello"));
    Subtitles.add_cues (p, sub, "Subtitles");
    return p;
}

ExportJob job (Project p, string preset, string name) {
    var settings = new ExportSettings ();
    settings.preset = Presets.find (preset).copy ();
    settings.preset.width = 320;
    settings.preset.height = 180;
    settings.output = File.new_for_path (TestKit.path (name));
    settings.hardware = true;
    return new ExportJob (p.clone (), settings);
}

void run (ExportJob j, string label) {
    try {
        j.run_sync ();
        check (j.settings.output.query_exists (), "%s produced a file".printf (label));
    } catch (Error e) {
        check (false, "%s failed: %s".printf (label, e.message));
    }
}

void test_formats () throws Error {
    var p = timeline ();
    var webm = job (p, "webm-1080", "out.webm");
    webm.settings.subtitles = "embed";
    run (webm, "WebM");
    var m = Probe.probe (webm.settings.output.get_uri ());
    close_to ((double) m.duration / S, 2.0, 0.1, "WebM has the sequence length");
    check (m.has_video && m.has_audio && m.width == 320, "WebM has both streams at the output size");
    var discoverer = new Gst.PbUtils.Discoverer (10 * Gst.SECOND);
    var info = discoverer.discover_uri (webm.settings.output.get_uri ());
    var toc = info.get_toc ();
    int chapters = 0;
    if (toc != null) foreach (var entry in toc.get_entries ()) chapters += (int) entry.get_sub_entries ().length ();
    check (chapters == 2, "WebM carries two chapters (got %d)".printf (chapters));
    check (FileUtils.test (TestKit.path ("out.vtt"), FileTest.EXISTS), "WebM gets a WebVTT sidecar");
    var mkv = job (p, "archive-av1", "out.mkv");
    mkv.settings.subtitles = "embed";
    run (mkv, "MKV AV1");
    var mkv_info = discoverer.discover_uri (mkv.settings.output.get_uri ());
    var subs = mkv_info.get_subtitle_streams ();
    check (subs != null && subs.length () == 1, "MKV embeds the subtitle track");
    var mp4 = job (p, "web-1080", "out.mp4");
    mp4.settings.subtitles = "srt";
    run (mp4, "MP4");
    check (mp4.encoder_used == "x264enc", "software H.264 fallback chosen without hardware (%s)".printf (mp4.encoder_used));
    check (FileUtils.test (TestKit.path ("out.srt"), FileTest.EXISTS), "sidecar SRT written");
    string ffprobe = Environment.find_program_in_path ("ffprobe") ?? "";
    if (ffprobe != "") {
        string output;
        Process.spawn_command_line_sync ("%s -v error -show_chapters -of csv %s".printf (ffprobe, GLib.Shell.quote (mp4.settings.output.get_path ())), out output);
        check (output.contains ("Opening") && output.contains ("Second"), "MP4 chapters are readable by other players");
    }
    var range = job (p, "web-sequence", "range.mp4");
    range.settings.start = 500000000;
    range.settings.end = 1500000000;
    run (range, "Range export");
    var rm = Probe.probe (range.settings.output.get_uri ());
    close_to ((double) rm.duration / S, 1.0, 0.1, "range export has the marked length");
    var vertical = job (p, "vertical-1080", "vertical.mp4");
    vertical.settings.preset.width = 180;
    vertical.settings.preset.height = 320;
    run (vertical, "Vertical");
    var vm = Probe.probe (vertical.settings.output.get_uri ());
    check (vm.width == 180 && vm.height == 320, "vertical preset reframes the picture");
    var small = job (p, "social-small", "small.mp4");
    small.settings.preset.max_size_mb = 1;
    run (small, "Size limited");
    int64 size = small.settings.output.query_info ("standard::size", FileQueryInfoFlags.NONE).get_size ();
    check (size < 1024 * 1024, "size limited export stays under 1 MB (%lld)".printf (size));
}

string probe_field (string ffprobe, string path, string stream, string fields) {
    string output = "";
    try {
        Process.spawn_command_line_sync ("%s -v error -select_streams %s -show_entries stream=%s -of default=nw=1 %s".printf (ffprobe, stream, fields, GLib.Shell.quote (path)), out output);
    } catch (Error e) {
    }
    return output;
}

void test_master_backend (Project p, string backend) throws Error {
    Environment.set_variable ("MONTAGE_MASTER_BACKEND", backend, true);
    Master.reset ();
    if (!Master.available ("prores")) {
        print ("SKIP: no %s master backend on this system\n".printf (backend));
        return;
    }
    string ffprobe = Environment.find_program_in_path ("ffprobe") ?? "";
    string[] codecs = { "master-prores", "master-prores4444", "master-dnxhr", "master-ffv1" };
    string[] names = { "prores", "prores", "dnxhd", "ffv1" };
    string[] pix = { "yuv422p10le", "yuva444p1", "yuv422p10le", "yuv444p10le" };
    string[] profiles = { "profile=HQ", "profile=4444", "profile=DNXHR HQX", "" };
    for (int i = 0; i < codecs.length; i++) {
        string codec = codecs[i];
        if (!Master.available (Presets.find (codec).vcodec)) {
            print ("SKIP: %s cannot write %s on this system\n".printf (backend, codec));
            continue;
        }
        var j = job (p, codec, "%s-%s.%s".printf (backend, codec, codec == "master-ffv1" ? "mkv" : "mov"));
        run (j, "%s %s".printf (backend, codec));
        check (j.encoder_used.down ().has_prefix (backend), "%s %s used the %s backend (%s)".printf (backend, codec, backend, j.encoder_used));
        if (ffprobe == "") continue;
        string path = j.settings.output.get_path ();
        string v = probe_field (ffprobe, path, "v:0", "codec_name,profile,pix_fmt,color_space,color_primaries,color_transfer,color_range,width,height");
        check (v.contains ("codec_name=" + names[i]) && v.contains ("pix_fmt=" + pix[i]) && v.contains (profiles[i]), "%s %s is 10 bit %s %s (%s)".printf (backend, codec, names[i], pix[i], v.replace ("\n", " ").strip ()));
        check (v.contains ("color_space=bt709") && v.contains ("color_primaries=bt709") && v.contains ("color_transfer=bt709") && (names[i] == "prores" || v.contains ("color_range=tv")),
            "%s %s carries BT.709 limited range colour tags".printf (backend, codec));
        check (v.contains ("width=320") && v.contains ("height=180"), "%s %s keeps the frame size".printf (backend, codec));
        string a = probe_field (ffprobe, path, "a:0", "codec_name,sample_rate,channels");
        check (a.contains ("codec_name=pcm_s24le") && a.contains ("channels=2"), "%s %s has 24 bit PCM stereo audio (%s)".printf (backend, codec, a.replace ("\n", " ").strip ()));
        string duration = "";
        Process.spawn_command_line_sync ("%s -v error -show_entries format=duration -of csv=p=0 %s".printf (ffprobe, GLib.Shell.quote (path)), out duration);
        close_to (double.parse (duration.strip ()), 2.0, 0.1, "%s %s has the sequence length".printf (backend, codec));
    }
}

void test_masters_and_images () throws Error {
    var p = timeline ();
    string? saved = Environment.get_variable ("MONTAGE_MASTER_BACKEND");
    test_master_backend (p, "gstreamer");
    test_master_backend (p, "ffmpeg");
    Environment.set_variable ("MONTAGE_MASTER_BACKEND", "none", true);
    Master.reset ();
    bool hidden = true;
    foreach (var preset in Presets.usable ()) if (preset.master) hidden = false;
    check (hidden && Presets.usable ().size < Presets.all ().size && Master.install_hint () != "", "master presets are hidden without a backend");
    var refused = job (p, "master-prores", "none-master.mov");
    try {
        refused.run_sync ();
        check (false, "a master export without a backend is refused");
    } catch (Error e) {
        check (!refused.settings.output.query_exists (), "a master export without a backend is refused (%s)".printf (e.message));
    }
    if (saved != null) Environment.set_variable ("MONTAGE_MASTER_BACKEND", saved, true);
    else Environment.unset_variable ("MONTAGE_MASTER_BACKEND");
    Master.reset ();
    foreach (var seq_preset in new string[] { "seq-png", "seq-tiff", "seq-exr" }) {
        var j = job (p, seq_preset, "frames-" + seq_preset + "." + Presets.find (seq_preset).extension);
        j.settings.start = 0;
        j.settings.end = 200000000;
        try {
            j.run_sync ();
        } catch (Error e) {
            check (false, "%s failed: %s".printf (seq_preset, e.message));
        }
        string first = TestKit.path ("frames-%s_000000.%s".printf (seq_preset, Presets.find (seq_preset).extension));
        string last = TestKit.path ("frames-%s_000004.%s".printf (seq_preset, Presets.find (seq_preset).extension));
        check (FileUtils.test (first, FileTest.EXISTS) && FileUtils.test (last, FileTest.EXISTS), "%s writes one file per frame".printf (seq_preset));
        if (seq_preset != "seq-exr") {
            try {
                var pix = new Gdk.Pixbuf.from_file (first);
                check (pix.width == 320 && pix.height == 180, "%s frames open in other tools".printf (seq_preset));
            } catch (Error e) {
                check (false, "%s frame unreadable: %s".printf (seq_preset, e.message));
            }
        } else {
            uint8[] data;
            FileUtils.get_data (first, out data);
            check (data[0] == 0x76 && data[1] == 0x2f && data[2] == 0x31 && data[3] == 0x01, "EXR magic number");
        }
    }
    var wav = job (p, "audio-wav", "mix.wav");
    wav.settings.normalize = true;
    wav.settings.loudness_target = -16;
    run (wav, "WAV");
    var mixer_check = new AudioReader (wav.settings.output.get_uri (), 48000);
    var buf = new float[96000 * 2];
    mixer_check.read (0, 96000, buf);
    var meter = new Singularity.Audio.LoudnessMeter (48000, 2);
    meter.add (buf, 96000);
    close_to (meter.integrated, -16, 0.6, "loudness normalisation reaches the target");
}

void test_mp4_chapters_unit () throws Error {
    var p = timeline ();
    var j = job (p, "web-sequence", "chapters.mp4");
    j.settings.chapters = false;
    run (j, "plain MP4");
    var marks = new Gee.ArrayList<Marker> ();
    marks.add (new Marker (0, "One"));
    marks.add (new Marker (S, "Two"));
    Mp4Chapters.inject (j.settings.output, marks);
    var m = Probe.probe (j.settings.output.get_uri ());
    close_to ((double) m.duration / S, 2.0, 0.1, "MP4 still plays after adding chapters");
}

int main (string[] args) {
    init (args);
    try {
        test_formats ();
        test_masters_and_images ();
        test_mp4_chapters_unit ();
    } catch (Error e) {
        check (false, "unexpected error: " + e.message);
    }
    return finish ("export");
}
