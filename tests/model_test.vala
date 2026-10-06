using Singularity.Apps.Montage;
using Singularity.Apps.Montage.TestKit;

const int64 S = 1000000000;

MediaItem fake_media (Project p, string name, int64 duration, bool video = true, bool audio = true) {
    var m = new MediaItem ();
    m.uri = "file:///nonexistent/" + name;
    m.name = name;
    m.duration = duration;
    m.width = 1920;
    m.height = 1080;
    m.has_video = video;
    m.has_audio = audio;
    p.media.add (m);
    return m;
}

Track vtrack (Project p, int n) {
    return p.sequence.tracks_of (TrackKind.VIDEO)[n];
}

Track atrack (Project p, int n) {
    return p.sequence.tracks_of (TrackKind.AUDIO)[n];
}

void test_insert_overwrite () throws Error {
    var p = new Project ();
    var e = new Edits (p);
    var m = fake_media (p, "a.mp4", 10 * S);
    var clips = e.make_media_clips (m, 0, 4 * S, vtrack (p, 0).id, atrack (p, 0).id);
    check (clips.size == 2 && clips[0].link != "" && clips[0].link == clips[1].link, "media clips are linked video and audio");
    e.place (clips, 0, false);
    var more = e.make_media_clips (m, 2 * S, 5 * S, vtrack (p, 0).id, atrack (p, 0).id);
    e.place (more, 2 * S, true);
    var v = p.sequence.on_track (vtrack (p, 0).id);
    check (v.size == 3, "insert splits the clip under the insert point (got %d)".printf (v.size));
    check (v[0].duration == 2 * S && v[1].position == 2 * S && v[1].duration == 3 * S, "insert places the new clip");
    check (v[2].position == 5 * S && v[2].in_point == 2 * S && v[2].duration == 2 * S, "the remainder moves after the insert");
    var a = p.sequence.on_track (atrack (p, 0).id);
    check (a.size == 3 && a[2].position == 5 * S, "audio follows the insert");
    var over = e.make_media_clips (m, 0, 1 * S, vtrack (p, 0).id, null);
    e.place (over, 2500000000, false);
    v = p.sequence.on_track (vtrack (p, 0).id);
    check (v.size == 5, "overwrite splits the middle clip (got %d)".printf (v.size));
    check (v[1].end == 2500000000 && v[2].position == 2500000000 && v[3].position == 3500000000 && v[3].in_point == 3500000000, "overwrite trims around the new clip");
    check (p.sequence.duration == 7 * S, "overwrite keeps the sequence length");
    p.undo ();
    check (p.sequence.on_track (vtrack (p, 0).id).size == 3, "undo overwrite");
    p.redo ();
    check (p.sequence.on_track (vtrack (p, 0).id).size == 5, "redo overwrite");
}

void test_split_ripple () throws Error {
    var p = new Project ();
    var e = new Edits (p);
    var m = fake_media (p, "b.mp4", 10 * S);
    e.place (e.make_media_clips (m, 0, 6 * S, vtrack (p, 0).id, atrack (p, 0).id), 0, false);
    e.split (2 * S, new Gee.ArrayList<string> ());
    var v = p.sequence.on_track (vtrack (p, 0).id);
    var a = p.sequence.on_track (atrack (p, 0).id);
    check (v.size == 2 && a.size == 2, "split cuts every unlocked track at the playhead");
    check (v[1].in_point == 2 * S && v[1].link == a[1].link && v[1].link != v[0].link, "right halves keep a new shared link");
    var ids = new Gee.ArrayList<string> ();
    ids.add (v[0].id);
    e.ripple_delete (ids);
    v = p.sequence.on_track (vtrack (p, 0).id);
    a = p.sequence.on_track (atrack (p, 0).id);
    check (v.size == 1 && v[0].position == 0 && v[0].in_point == 2 * S, "ripple delete closes the gap on video");
    check (a.size == 1 && a[0].position == 0, "ripple delete closes the gap on linked audio");
    vtrack (p, 0).locked = true;
    bool refused = false;
    try {
        e.split (S, new Gee.ArrayList<string> ());
        refused = p.sequence.on_track (vtrack (p, 0).id).size == 1;
    } catch (Error err) {
        refused = true;
    }
    check (refused, "locked tracks are not split");
}

void test_trims () throws Error {
    var p = new Project ();
    var e = new Edits (p);
    var m = fake_media (p, "c.mp4", 20 * S, true, false);
    var first = e.make_media_clips (m, 2 * S, 6 * S, vtrack (p, 0).id, null);
    e.place (first, 0, false);
    var second = e.make_media_clips (m, 10 * S, 14 * S, vtrack (p, 0).id, null);
    e.place (second, 4 * S, false);
    string a = first[0].id, b = second[0].id;
    var seq = p.sequence;
    e.trim (a, false, S, TrimMode.ROLL);
    check (seq.clip (a).duration == 5 * S && seq.clip (b).position == 5 * S && seq.clip (b).in_point == 11 * S && seq.clip (b).duration == 3 * S, "roll moves the edit point");
    e.trim (b, true, -S, TrimMode.ROLL);
    check (seq.clip (a).duration == 4 * S && seq.clip (b).position == 4 * S, "roll back from the head");
    e.trim (b, false, 0, TrimMode.SLIP);
    e.trim (b, true, 3 * S, TrimMode.SLIP);
    check (seq.clip (b).in_point == 13 * S && seq.clip (b).position == 4 * S && seq.clip (b).duration == 4 * S, "slip changes only the source");
    int64 applied = e.trim (b, true, 10 * S, TrimMode.SLIP);
    check (seq.clip (b).in_point + seq.clip (b).duration <= 20 * S && applied == 3 * S, "slip stops at the end of the media");
    var third = e.make_media_clips (m, 0, 2 * S, vtrack (p, 0).id, null);
    e.place (third, 8 * S, false);
    string c = third[0].id;
    e.trim (b, true, S, TrimMode.SLIDE);
    check (seq.clip (b).position == 5 * S && seq.clip (a).duration == 5 * S && seq.clip (c).position == 9 * S && seq.clip (c).duration == S,
        "slide moves the clip and adjusts both neighbours");
    e.trim (a, false, S, TrimMode.RIPPLE);
    check (seq.clip (a).duration == 6 * S && seq.clip (b).position == 6 * S && seq.clip (c).position == 10 * S, "ripple trim pushes later clips");
    e.trim (a, true, S, TrimMode.RIPPLE);
    check (seq.clip (a).position == 0 && seq.clip (a).in_point == 3 * S && seq.clip (b).position == 5 * S, "ripple head trim pulls later clips");
    e.trim (b, false, -S, TrimMode.NORMAL);
    check (seq.clip (b).end == seq.clip (c).position - S, "selection trim leaves a gap");
    e.trim (b, false, 5 * S, TrimMode.NORMAL);
    check (seq.clip (b).end == seq.clip (c).position, "selection trim stops at the next clip");
}

void test_move_nest_speed () throws Error {
    var p = new Project ();
    var e = new Edits (p);
    var m = fake_media (p, "d.mp4", 10 * S);
    var clips = e.make_media_clips (m, 0, 4 * S, vtrack (p, 0).id, atrack (p, 0).id);
    e.place (clips, 0, false);
    var ids = new Gee.ArrayList<string> ();
    ids.add (clips[0].id);
    e.move (ids, 2 * S, 1, false);
    var seq = p.sequence;
    check (seq.clip (clips[0].id).track == vtrack (p, 1).id && seq.clip (clips[0].id).position == 2 * S, "video moves to V2");
    check (seq.clip (clips[1].id).track == atrack (p, 0).id && seq.clip (clips[1].id).position == 2 * S, "linked audio moves in time only");
    e.set_speed (clips[0].id, 200, false, false, true);
    check (seq.clip (clips[0].id).duration == 2 * S && seq.clip (clips[1].id).duration == 2 * S, "double speed halves both linked clips");
    check (seq.clip (clips[0].id).source_time (3 * S) == 2 * S, "speed maps timeline to source");
    var nested = e.nest (ids, "Nested");
    check (p.sequences.size == 2 && nested.clips.size == 2, "nest moves the clips into a new sequence");
    int seq_clips = 0;
    foreach (var c in seq.clips) if (c.kind == ClipKind.SEQUENCE) seq_clips++;
    check (seq_clips == 2, "nest leaves linked sequence clips behind");
    check (p.sequence_contains (seq, nested.id), "nested sequence is referenced");
    var copy = Project.parse (p.serialize ());
    check (copy.sequences.size == 2 && copy.serialize () == p.serialize (), "project round trip is lossless");
}

void test_transitions_markers_serialization () throws Error {
    var p = new Project ();
    var e = new Edits (p);
    var m = fake_media (p, "e.mp4", 10 * S, true, false);
    m.tags.add ("interview");
    m.metadata["scene"] = "12A";
    m.label = 3;
    var a = e.make_media_clips (m, 0, 3 * S, vtrack (p, 0).id, null);
    e.place (a, 0, false);
    var b = e.make_media_clips (m, 5 * S, 8 * S, vtrack (p, 0).id, null);
    e.place (b, 3 * S, false);
    var t = e.add_transition (a[0].id, true, "wipe", S, 0);
    check (t.from_clip == a[0].id && t.to_clip == b[0].id && t.start_at (3 * S) == 2500000000, "centred transition between adjacent clips");
    var marker = e.add_marker (1500000000, "Intro", "chapter");
    check (p.sequence.markers.size == 1 && marker.kind == "chapter", "chapter marker added");
    a[0].params.ensure ("opacity", 100).set_key (0, 0);
    a[0].params.ensure ("opacity", 100).set_key (S, 100);
    var effect = Catalog.find ("color.primary").create ();
    effect.params.values["exposure"].value = 1;
    a[0].effects.add (effect);
    p.commit ();
    var copy = Project.parse (p.serialize ());
    var ca = copy.sequence.clip (a[0].id);
    check (ca.params.values["opacity"].keys.size == 2 && (ca.params.get_value ("opacity", S / 2, 0) - 50).abs () < 1e-6, "keyframes survive save");
    check (ca.effects.size == 1 && ca.effects[0].params.values["exposure"].value == 1, "effects survive save");
    check (copy.sequence.transitions.size == 1 && copy.sequence.transitions[0].kind == "wipe", "transitions survive save");
    var found = copy.search ("12a", "*", 0);
    check (found.size == 1, "search finds metadata");
    check (copy.search ("interview", "*", 3).size == 1 && copy.search ("interview", "*", 2).size == 0, "search filters by label");
    bool rejected = false;
    try {
        Project.parse ("{\"format\":\"montage\",\"version\":99,\"sequences\":[]}");
    } catch (Error err) {
        rejected = true;
    }
    check (rejected, "newer project versions are refused");
}

void test_delete_range_and_snap () throws Error {
    var p = new Project ();
    var e = new Edits (p);
    var m = fake_media (p, "f.mp4", 20 * S);
    e.place (e.make_media_clips (m, 0, 10 * S, vtrack (p, 0).id, atrack (p, 0).id), 0, false);
    e.delete_range (2 * S, 4 * S, true);
    var v = p.sequence.on_track (vtrack (p, 0).id);
    check (v.size == 2 && v[1].position == 2 * S && v[1].in_point == 4 * S && p.sequence.duration == 8 * S, "extract removes the range and closes it");
    int64 snapped = e.snap_point (2 * S + 30000000, 100000000);
    check (snapped == 2 * S, "snap pulls to the nearest edit");
    var starts = new Gee.ArrayList<int64?> ();
    var ends = new Gee.ArrayList<int64?> ();
    starts.add (S);
    ends.add (S + 500000000);
    starts.add (5 * S);
    ends.add (6 * S);
    e.remove_ranges (starts, ends, "Text cut");
    check (p.sequence.duration == 8 * S - 1500000000, "removing transcript ranges shortens the sequence");
    foreach (var c in p.sequence.clips) check (e.sync_offset (c) == 0, "pieces left by cuts stay in sync");
}

int main (string[] args) {
    init (args);
    try {
        test_insert_overwrite ();
        test_split_ripple ();
        test_trims ();
        test_move_nest_speed ();
        test_transitions_markers_serialization ();
        test_delete_range_and_snap ();
    } catch (Error e) {
        check (false, "unexpected error: " + e.message);
    }
    return finish ("model");
}
