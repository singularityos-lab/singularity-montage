using Singularity.Apps.Montage;
using Singularity.Apps.Montage.TestKit;

const int64 S = 1000000000;
const int64 F = 40000000;

MediaItem fake_media (Project p, string name, int64 duration) {
    var m = new MediaItem ();
    m.uri = "file:///nonexistent/" + name;
    m.name = name;
    m.duration = duration;
    m.width = 1920;
    m.height = 1080;
    m.fps_n = 25;
    m.has_video = true;
    m.has_audio = true;
    p.media.add (m);
    return m;
}

Clip place (Singularity.Apps.Montage.Sequence s, MediaItem m, Track t, int64 position, int64 duration, int64 in_point, string link) {
    var c = new Clip ();
    c.media = m.id;
    c.track = t.id;
    c.position = position;
    c.duration = duration;
    c.in_point = in_point;
    c.link = link;
    s.clips.add (c);
    return c;
}

string uri_of (Project p, Clip c) {
    var m = p.find_media (c.media);
    return m != null ? m.uri : "";
}

void test_roundtrip () throws Error {
    var p = new Project ();
    var s = p.sequence;
    s.fps_n = 25;
    s.fps_d = 1;
    var a = fake_media (p, "a.mov", 20 * S);
    var b = fake_media (p, "b.mov", 20 * S);
    var v1 = s.tracks_of (TrackKind.VIDEO)[0];
    var a1 = s.tracks_of (TrackKind.AUDIO)[0];
    var c1 = place (s, a, v1, 0, 4 * S, 2 * S, "l1");
    var c2 = place (s, b, v1, 4 * S, 3 * S, 5 * S, "l2");
    place (s, a, v1, 9 * S, 2 * S, 10 * S, "l3");
    place (s, a, a1, 0, 4 * S, 2 * S, "l1");
    place (s, b, a1, 4 * S, 3 * S, 5 * S, "l2");
    place (s, a, a1, 9 * S, 2 * S, 10 * S, "l3");
    var tr = new Transition ();
    tr.track = v1.id;
    tr.from_clip = c1.id;
    tr.to_clip = c2.id;
    tr.duration = 20 * F;
    tr.align = 0;
    s.transitions.add (tr);
    s.markers.add (new Marker (5 * S, "Chapter"));

    var file = File.new_for_path (path ("roundtrip.aaf"));
    Aaf.write (p, s, file);
    uint8[] data;
    file.load_contents (null, out data, null);
    check (data.length > 512 && data[0] == 0xd0 && data[1] == 0xcf, "the written file is a compound document");

    var r = Aaf.read (data, file);
    check (r.sequences.size == 1, "one composition becomes one sequence (got %d)".printf (r.sequences.size));
    var rs = r.sequence;
    check (rs.fps_n == 25 && rs.fps_d == 1, "edit rate becomes the sequence rate (got %d/%d)".printf (rs.fps_n, rs.fps_d));
    check (rs.tracks_of (TrackKind.VIDEO).size == 2 && rs.tracks_of (TrackKind.AUDIO).size == 2, "every track becomes a slot and back");
    var rv = rs.on_track (rs.tracks_of (TrackKind.VIDEO)[0].id);
    var ra = rs.on_track (rs.tracks_of (TrackKind.AUDIO)[0].id);
    check (rv.size == 3, "three video clips come back (got %d)".printf (rv.size));
    check (ra.size == 3, "three audio clips come back (got %d)".printf (ra.size));
    if (rv.size == 3) {
        check (rv[0].position == 0 && rv[0].duration == 4 * S && rv[0].in_point == 2 * S, "first clip is frame accurate (%lld %lld %lld)".printf (rv[0].position, rv[0].duration, rv[0].in_point));
        check (rv[1].position == 4 * S && rv[1].duration == 3 * S && rv[1].in_point == 5 * S, "dissolved clip keeps its cut (%lld %lld %lld)".printf (rv[1].position, rv[1].duration, rv[1].in_point));
        check (rv[2].position == 9 * S && rv[2].duration == 2 * S && rv[2].in_point == 10 * S, "clip after the gap keeps its place (%lld %lld %lld)".printf (rv[2].position, rv[2].duration, rv[2].in_point));
        check (uri_of (r, rv[0]) == "file:///nonexistent/a.mov" && uri_of (r, rv[1]) == "file:///nonexistent/b.mov" && uri_of (r, rv[2]) == "file:///nonexistent/a.mov", "media locations survive");
        check (rv[0].media == rv[2].media, "the same file maps to one media item");
        check (rs.transitions.size == 1, "the dissolve comes back (got %d)".printf (rs.transitions.size));
        if (rs.transitions.size == 1) {
            var t = rs.transitions[0];
            check (t.from_clip == rv[0].id && t.to_clip == rv[1].id, "the dissolve joins the right clips");
            check (t.duration == 20 * F && t.align == 0, "the dissolve keeps its length and alignment (%lld %d)".printf (t.duration, t.align));
        }
    }
    if (ra.size == 3) {
        check (ra[0].position == 0 && ra[1].position == 4 * S && ra[2].position == 9 * S, "audio positions survive");
        check (ra[0].duration == 4 * S && ra[1].duration == 3 * S && ra[2].duration == 2 * S, "audio durations survive");
        check (ra[0].in_point == 2 * S && ra[1].in_point == 5 * S && ra[2].in_point == 10 * S, "audio in points survive");
        check (uri_of (r, ra[1]) == "file:///nonexistent/b.mov", "audio media location survives");
        if (rv.size == 3) check (rv[0].link != "" && rv[0].link == ra[0].link && rv[2].link == ra[2].link, "matching picture and sound are linked again");
    }
    check (r.media.size == 2, "two media items (got %d)".printf (r.media.size));
    check (rs.markers.size == 1 && rs.markers[0].time == 5 * S && rs.markers[0].name == "Chapter", "markers survive");
}

void test_fixture () throws Error {
    string? dir = Environment.get_variable ("MONTAGE_FIXTURES");
    check (dir != null, "MONTAGE_FIXTURES is set");
    if (dir == null) return;
    var file = File.new_for_path (Path.build_filename (dir, "sample.aaf"));
    uint8[] data;
    file.load_contents (null, out data, null);
    var r = Aaf.read (data, file);
    var s = r.sequence;
    check (s.name == "Sample Cut", "composition name (got %s)".printf (s.name));
    check (s.fps_n == 25 && s.fps_d == 1, "fixture edit rate");
    var v = s.on_track (s.tracks_of (TrackKind.VIDEO)[0].id);
    var a = s.on_track (s.tracks_of (TrackKind.AUDIO)[0].id);
    check (v.size == 3, "fixture video clips (got %d)".printf (v.size));
    check (a.size == 2, "fixture audio clips (got %d)".printf (a.size));
    if (v.size == 3) {
        check (v[0].position == 0 && v[0].duration == 60 * F && v[0].in_point == 10 * F, "fixture first clip");
        check (v[1].position == 85 * F && v[1].duration == 45 * F && v[1].in_point == 40 * F, "fixture clip before the dissolve (%lld %lld %lld)".printf (v[1].position, v[1].duration, v[1].in_point));
        check (v[2].position == 130 * F && v[2].duration == 35 * F && v[2].in_point == 105 * F, "fixture clip after the dissolve (%lld %lld %lld)".printf (v[2].position, v[2].duration, v[2].in_point));
        check (uri_of (r, v[0]) == "file:///media/shot_a.mov" && uri_of (r, v[1]) == "file:///media/shot_b.mov", "fixture locator URLs");
        check (s.transitions.size == 1 && s.transitions[0].duration == 10 * F && s.transitions[0].from_clip == v[1].id, "fixture dissolve");
    }
    if (a.size == 2) {
        check (a[0].position == 0 && a[0].duration == 60 * F && a[0].in_point == 10 * F, "fixture first audio clip");
        check (a[1].position == 85 * F && a[1].duration == 50 * F && a[1].in_point == 40 * F, "fixture second audio clip");
        if (v.size == 3) check (v[0].link != "" && v[0].link == a[0].link, "fixture picture and sound are linked");
    }
}

void test_large () throws Error {
    var p = new Project ();
    var s = p.sequence;
    s.fps_n = 25;
    s.fps_d = 1;
    var m = fake_media (p, "long.wav", 4000 * S);
    var a1 = s.tracks_of (TrackKind.AUDIO)[0];
    int count = 15000;
    for (int i = 0; i < count; i++) place (s, m, a1, i * 2 * F, F, i * F, "");
    var file = File.new_for_path (path ("large.aaf"));
    Aaf.write (p, s, file);
    uint8[] data;
    file.load_contents (null, out data, null);
    check (data.length > 8 * 1024 * 1024, "the large timeline needs extended allocation tables (%d bytes)".printf (data.length));
    var r = Aaf.read (data, file);
    var clips = r.sequence.on_track (r.sequence.tracks_of (TrackKind.AUDIO)[0].id);
    check (clips.size == count, "every clip of a large timeline comes back (got %d)".printf (clips.size));
    if (clips.size == count) {
        var last = clips[count - 1];
        check (last.position == (count - 1) * 2 * F && last.duration == F && last.in_point == (count - 1) * F, "the last clip of a large timeline is exact");
    }
}

void test_nested () throws Error {
    var p = new Project ();
    var s = p.sequence;
    s.fps_n = 25;
    s.fps_d = 1;
    var m = fake_media (p, "inner.mov", 30 * S);
    var inner = new Singularity.Apps.Montage.Sequence ("Inner");
    inner.fps_n = 25;
    inner.fps_d = 1;
    inner.add_default_tracks ();
    p.sequences.add (inner);
    place (inner, m, inner.tracks_of (TrackKind.VIDEO)[0], 0, 6 * S, S, "");
    var c = new Clip ();
    c.kind = ClipKind.SEQUENCE;
    c.sequence = inner.id;
    c.track = s.tracks_of (TrackKind.VIDEO)[0].id;
    c.position = 2 * S;
    c.duration = 3 * S;
    c.in_point = S;
    s.clips.add (c);
    var file = File.new_for_path (path ("nested.aaf"));
    Aaf.write (p, s, file);
    uint8[] data;
    file.load_contents (null, out data, null);
    var r = Aaf.read (data, file);
    check (r.sequences.size == 2 && r.sequence.name == s.name, "the nested sequence becomes a second sequence behind the top one");
    var v = r.sequence.on_track (r.sequence.tracks_of (TrackKind.VIDEO)[0].id);
    check (v.size == 1 && v[0].kind == ClipKind.SEQUENCE, "the nested clip stays a sequence clip");
    if (v.size == 1 && r.sequences.size == 2) {
        check (v[0].sequence == r.sequences[1].id && v[0].position == 2 * S && v[0].duration == 3 * S && v[0].in_point == S, "the nested clip keeps its timing");
        var iv = r.sequences[1].on_track (r.sequences[1].tracks_of (TrackKind.VIDEO)[0].id);
        check (iv.size == 1 && iv[0].in_point == S && iv[0].duration == 6 * S && uri_of (r, iv[0]) == "file:///nonexistent/inner.mov", "the inner sequence keeps its clip");
    }
}

void test_garbage () {
    uint8[] junk = new uint8[2048];
    bool refused = false;
    try {
        Aaf.read (junk, null);
    } catch (Error e) {
        refused = true;
    }
    check (refused, "a non compound file is refused");
}

int main (string[] args) {
    init (args);
    try {
        test_roundtrip ();
        test_fixture ();
        test_large ();
        test_nested ();
    } catch (Error e) {
        check (false, "unexpected error: %s".printf (e.message));
    }
    test_garbage ();
    return finish ("aaf");
}
