namespace Singularity.Apps.Montage {
    namespace MulticamOps {
        public void cut (Controller ctl, Clip c, int64 t, int angle) {
            if (t < c.position || t >= c.end) {
                ctl.say (_("Move the playhead over the multicamera clip first."));
                return;
            }
            int64 local = ctl.seq.snap (t) - c.position;
            ctl.project.checkpoint (_("Switch Angle"));
            var group = ctl.seq.linked (c);
            foreach (var g in group) {
                if (g.kind != ClipKind.MULTICAM) continue;
                var track = ctl.seq.track (g.track);
                if (track == null || track.kind != TrackKind.VIDEO) continue;
                var keep = new Gee.ArrayList<MulticamCut> ();
                foreach (var k in g.cuts) if (k.time != local) keep.add (k);
                keep.add (new MulticamCut (local, angle));
                keep.sort ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
                var clean = new Gee.ArrayList<MulticamCut> ();
                int last = -1;
                foreach (var k in keep) {
                    if (k.angle == last) continue;
                    clean.add (k);
                    last = k.angle;
                }
                g.cuts = clean;
            }
            ctl.project.commit ();
        }
    }
}
