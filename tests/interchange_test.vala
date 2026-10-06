using Singularity.Apps.Montage;
using Singularity.Apps.Montage.TestKit;

const int64 S = 1000000000;

string fixture (string name) {
    return Path.build_filename (Environment.get_variable ("MONTAGE_FIXTURES") ?? "tests/fixtures", name);
}

Gee.ArrayList<Clip> clips_of (Singularity.Apps.Montage.Sequence s, TrackKind kind, int index) {
    var tracks = s.tracks_of (kind);
    if (index >= tracks.size) return new Gee.ArrayList<Clip> ();
    return s.on_track (tracks[index].id);
}

string name_of (Project p, Clip c) {
    var m = p.find_media (c.media);
    if (m == null) return "";
    string n = m.metadata.has_key ("source name") ? m.metadata["source name"] : m.name;
    return n.down ();
}

void check_reference (Project p, string label, bool with_audio, bool exact_transition) {
    var s = p.sequence;
    var v = clips_of (s, TrackKind.VIDEO, 0);
    check (v.size == 3, "%s: three video clips (got %d)".printf (label, v.size));
    if (v.size != 3) return;
    close_to ((double) v[0].position / S, 0, 0.05, "%s: first clip at 0".printf (label));
    close_to ((double) v[0].in_point / S, 1, 0.05, "%s: first clip source in".printf (label));
    close_to ((double) v[0].duration / S, 3, 0.05, "%s: first clip length".printf (label));
    close_to ((double) v[1].position / S, 4, 0.05, "%s: gap kept before second clip".printf (label));
    check (name_of (p, v[0]).contains ("interview"), "%s: first clip media resolved (%s)".printf (label, name_of (p, v[0])));
    check (name_of (p, v[2]).contains ("closing"), "%s: last clip media resolved (%s)".printf (label, name_of (p, v[2])));
    int64 end = v[2].end;
    close_to ((double) end / S, 10, 0.05, "%s: timeline ends at 10 s".printf (label));
    if (exact_transition) {
        check (s.transitions.size >= 1, "%s: dissolve read".printf (label));
        if (s.transitions.size >= 1) close_to ((double) s.transitions[0].duration / S, 1, 0.05, "%s: dissolve length".printf (label));
    }
    if (with_audio) {
        var a = clips_of (s, TrackKind.AUDIO, 0);
        check (a.size == 2, "%s: two audio clips (got %d)".printf (label, a.size));
        if (a.size == 2) close_to ((double) a[1].position / S, 4, 0.05, "%s: music position".printf (label));
    }
}

Project read_file (string name) throws Error {
    return Importers.read (File.new_for_path (fixture (name)));
}

void test_read_references () throws Error {
    var otio = read_file ("reference.otio");
    check_reference (otio, "OTIO", true, true);
    check (otio.sequence.markers.size == 1 && otio.sequence.markers[0].name == "Chapter One", "OTIO marker read");
    check_reference (read_file ("reference.edl"), "EDL", false, true);
    check_reference (read_file ("reference.xml"), "FCP XML", true, true);
    check_reference (read_file ("reference.fcpxml"), "FCPXML", true, false);
    check_reference (read_file ("reference.kdenlive"), "Kdenlive", true, false);
}

void test_round_trips () throws Error {
    var source = read_file ("reference.otio");
    var s = source.sequence;
    string otio_path = TestKit.path ("round.otio");
    FileUtils.set_contents (otio_path, Otio.write (source, s));
    check_reference (Otio.read (load (otio_path), File.new_for_path (otio_path)), "OTIO round trip", true, true);
    string edl_path = TestKit.path ("round.edl");
    FileUtils.set_contents (edl_path, Edl.write (source, s));
    check_reference (Edl.read (load (edl_path), File.new_for_path (edl_path)), "EDL round trip", false, true);
    string xml_path = TestKit.path ("round.xml");
    FileUtils.set_contents (xml_path, Fcp7.write (source, s));
    check_reference (Fcp7.read (load (xml_path), File.new_for_path (xml_path)), "FCP XML round trip", true, true);
    string fcpx_path = TestKit.path ("round.fcpxml");
    FileUtils.set_contents (fcpx_path, FcpXml.write (source, s));
    check_reference (FcpXml.read (load (fcpx_path), File.new_for_path (fcpx_path)), "FCPXML round trip", true, false);
    var native = File.new_for_path (TestKit.path ("round.montage"));
    NativeFormat.save (source, native);
    var back = NativeFormat.load (native);
    check (back.serialize () == source.serialize (), "native project round trip is lossless");
    var zip = ZipArchive.read (native);
    bool has_otio = false;
    foreach (var n in zip.names ()) if (n.has_suffix (".otio")) has_otio = true;
    check (has_otio && zip.text ("project.json") != null, "native archive carries JSON and OTIO");
    var bundle = File.new_for_path (TestKit.path ("round.otioz"));
    Otio.write_bundle (source, s, bundle);
    check (ZipArchive.read (bundle).text ("content.otio") != null, "OTIOZ bundle written");
}

string load (string path) throws Error {
    string text;
    FileUtils.get_contents (path, out text);
    return text;
}

void test_premiere () throws Error {
    string xml = """<?xml version="1.0" encoding="UTF-8"?>
<PremiereData Version="3">
 <Sequence ObjectUID="seq-1" ClassID="x" Version="1"><Name>Main Edit</Name>
  <TrackGroups Version="1"><TrackGroup Version="1" Index="0"><First>{video}</First><Second ObjectRef="10"/></TrackGroup>
   <TrackGroup Version="1" Index="1"><First>{audio}</First><Second ObjectRef="20"/></TrackGroup></TrackGroups></Sequence>
 <VideoTrackGroup ObjectID="10" Version="1"><TrackGroup Version="1"><FrameRate>10160640000</FrameRate>
  <Tracks Version="1"><Track Index="0" ObjectURef="vt-1"/></Tracks></TrackGroup></VideoTrackGroup>
 <AudioTrackGroup ObjectID="20" Version="1"><TrackGroup Version="1"><Tracks Version="1"><Track Index="0" ObjectURef="at-1"/></Tracks></TrackGroup></AudioTrackGroup>
 <VideoClipTrack ObjectUID="vt-1" Version="1"><ClipTrack Version="1"><ClipItems Version="1"><TrackItems Version="1">
  <TrackItem Index="0" ObjectRef="30"/><TrackItem Index="1" ObjectRef="31"/></TrackItems></ClipItems></ClipTrack></VideoClipTrack>
 <AudioClipTrack ObjectUID="at-1" Version="1"><ClipTrack Version="1"><ClipItems Version="1"><TrackItems Version="1">
  <TrackItem Index="0" ObjectRef="32"/></TrackItems></ClipItems></ClipTrack></AudioClipTrack>
 <VideoClipTrackItem ObjectID="30" Version="1"><ClipTrackItem Version="1"><TrackItem Version="1"><Start>0</Start><End>762048000000</End></TrackItem><SubClip ObjectRef="40"/></ClipTrackItem></VideoClipTrackItem>
 <VideoClipTrackItem ObjectID="31" Version="1"><ClipTrackItem Version="1"><TrackItem Version="1"><Start>1016064000000</End_unused><End>1524096000000</End></TrackItem><SubClip ObjectRef="41"/></ClipTrackItem></VideoClipTrackItem>
 <AudioClipTrackItem ObjectID="32" Version="1"><ClipTrackItem Version="1"><TrackItem Version="1"><Start>0</Start><End>762048000000</End></TrackItem><SubClip ObjectRef="42"/></ClipTrackItem></AudioClipTrackItem>
 <SubClip ObjectID="40" Version="1"><Clip ObjectRef="50"/><Name>Interview take 3</Name></SubClip>
 <SubClip ObjectID="41" Version="1"><Clip ObjectRef="51"/></SubClip>
 <SubClip ObjectID="42" Version="1"><Clip ObjectRef="52"/></SubClip>
 <VideoClip ObjectID="50" Version="1"><Clip Version="1"><Source ObjectRef="60"/><InPoint>254016000000</InPoint></Clip></VideoClip>
 <VideoClip ObjectID="51" Version="1"><Clip Version="1"><Source ObjectRef="61"/><InPoint>0</InPoint><PlaybackSpeed>2</PlaybackSpeed></Clip></VideoClip>
 <AudioClip ObjectID="52" Version="1"><Clip Version="1"><Source ObjectRef="62"/><InPoint>254016000000</InPoint></Clip></AudioClip>
 <VideoMediaSource ObjectID="60" Version="1"><MediaSource Version="1"><Media ObjectURef="m-1"/></MediaSource></VideoMediaSource>
 <VideoMediaSource ObjectID="61" Version="1"><MediaSource Version="1"><Media ObjectURef="m-2"/></MediaSource></VideoMediaSource>
 <AudioMediaSource ObjectID="62" Version="1"><MediaSource Version="1"><Media ObjectURef="m-1"/></MediaSource></AudioMediaSource>
 <Media ObjectUID="m-1" Version="1"><ActualMediaFilePath>/media/interview.mov</ActualMediaFilePath><Title>interview.mov</Title></Media>
 <Media ObjectUID="m-2" Version="1"><ActualMediaFilePath>/media/broll.mov</ActualMediaFilePath><Title>broll.mov</Title></Media>
</PremiereData>""".replace ("1016064000000</End_unused>", "1016064000000</Start>");
    var conv = new ZlibCompressor (ZlibCompressorFormat.GZIP, 6);
    var mem = new MemoryOutputStream.resizable ();
    var stream = new ConverterOutputStream (mem, conv);
    size_t done;
    stream.write_all (xml.data, out done);
    stream.close ();
    var data = mem.steal_data ();
    data.length = (int) mem.get_data_size ();
    var p = Premiere.read (data, null);
    var s = p.sequence;
    check (s.name == "Main Edit", "Premiere sequence name");
    check (s.fps_n == 25, "Premiere frame rate from ticks");
    var v = clips_of (s, TrackKind.VIDEO, 0);
    check (v.size == 2, "Premiere video clips (got %d)".printf (v.size));
    if (v.size == 2) {
        close_to ((double) v[0].duration / S, 3, 0.01, "Premiere clip length from ticks");
        close_to ((double) v[0].in_point / S, 1, 0.01, "Premiere in point");
        close_to ((double) v[1].position / S, 4, 0.01, "Premiere clip position");
        close_to (v[1].params.get_value ("speed", 0, 100), 200, 0.1, "Premiere playback speed");
        check (v[0].name == "Interview take 3", "Premiere subclip name");
    }
    var a = clips_of (s, TrackKind.AUDIO, 0);
    check (a.size == 1 && v.size == 2 && a[0].link != "" && a[0].link == v[0].link, "Premiere audio linked to its video");
}

void test_legacy () throws Error {
    string text = """{"version":2,"tracks":[{"id":"video-1","name":"Video 1","kind":"video","locked":false,"muted":false,"visible":true},
      {"id":"wave-mix","name":"Wave Mix","kind":"audio","locked":false,"muted":false,"visible":true}],
      "clips":[{"id":"a","uri":"file:///media/one.webm","track":"video-1","position":0,"start":0,"end":2000000000},
      {"id":"b","uri":"file:///media/mix.wav","track":"wave-mix","position":0,"start":0,"end":2000000000}]}""";
    string path = TestKit.path ("legacy.montage");
    FileUtils.set_contents (path, text);
    var p = NativeFormat.load (File.new_for_path (path));
    check (p.sequence.clips.size == 2 && p.sequence.tracks_of (TrackKind.AUDIO).size == 1, "version 2 projects open");
    var written = LegacyFormat.write (p, p.sequence);
    var o = Js.parse (written);
    check (Js.integer (o, "version") == 2 && Js.objects (o, "clips").size == 2, "version 2 export for Wave");
}

int main (string[] args) {
    init (args);
    try {
        test_read_references ();
        test_round_trips ();
        test_premiere ();
        test_legacy ();
    } catch (Error e) {
        check (false, "unexpected error: " + e.message);
    }
    return finish ("interchange");
}
