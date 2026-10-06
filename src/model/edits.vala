namespace Singularity.Apps.Montage {
    public enum TrimMode {
        NORMAL,
        RIPPLE,
        ROLL,
        SLIP,
        SLIDE;

        public string label () {
            switch (this) {
                case RIPPLE: return _("Ripple");
                case ROLL: return _("Roll");
                case SLIP: return _("Slip");
                case SLIDE: return _("Slide");
                default: return _("Selection");
            }
        }
    }

    public class Edits : Object {
        public Project project;

        Gee.HashMap<string, string> relinks = new Gee.HashMap<string, string> ();

        public Edits (Project project) {
            this.project = project;
        }

        string relink (string link, int64 at) {
            string key = "%s@%lld".printf (link, at);
            if (!relinks.has_key (key)) relinks[key] = new_id ();
            return relinks[key];
        }

        Sequence seq {
            owned get { return project.sequence; }
        }

        void ensure_unlocked (Clip c) throws Error {
            if (project.foreign_locks.contains (seq.id)) throw new IOError.PERMISSION_DENIED (_("Someone else is editing %s. Ask them to release it.").printf (seq.name));
            var t = seq.track (c.track);
            if (t == null) throw new IOError.INVALID_ARGUMENT (_("The clip has no track."));
            if (t.locked) throw new IOError.PERMISSION_DENIED (_("Unlock the track %s before editing.").printf (t.name));
        }

        public static int64 source_delta (Clip c, int64 timeline_delta) {
            var s = c.params.values["speed"];
            double speed = s == null ? 1 : s.at (c.in_point) / 100.0;
            return (int64) Math.round (timeline_delta * speed);
        }

        public void trim_head_raw (Clip c, int64 delta) {
            int64 sd = source_delta (c, delta);
            c.position += delta;
            c.duration -= delta;
            if (!c.reverse) {
                c.in_point += sd;
                c.params.shift (sd - delta);
            }
            foreach (var m in c.markers) m.time -= delta;
        }

        public void trim_tail_raw (Clip c, int64 delta) {
            c.duration += delta;
            if (c.reverse) c.in_point -= source_delta (c, delta);
        }

        void remove_clip (Clip c) {
            seq.clips.remove (c);
            var dead = new Gee.ArrayList<Transition> ();
            foreach (var t in seq.transitions) if (t.from_clip == c.id || t.to_clip == c.id) dead.add (t);
            foreach (var t in dead) seq.transitions.remove (t);
        }

        public void clear_range (string track_id, int64 start, int64 end, Gee.Collection<Clip>? keep = null) {
            if (end <= start) return;
            foreach (var c in seq.on_track (track_id)) {
                if (keep != null && keep.contains (c)) continue;
                if (c.end <= start || c.position >= end) continue;
                if (c.position >= start && c.end <= end) {
                    remove_clip (c);
                } else if (c.position < start && c.end > end) {
                    var right = c.copy ();
                    right.id = new_id ();
                    if (c.link != "") right.link = relink (c.link, end);
                    trim_head_raw (right, end - c.position);
                    c.duration = start - c.position;
                    seq.clips.add (right);
                    foreach (var t in seq.transitions) if (t.from_clip == c.id) t.from_clip = right.id;
                } else if (c.position < start) {
                    c.duration = start - c.position;
                    drop_transition_after (c);
                } else {
                    trim_head_raw (c, end - c.position);
                    drop_transition_before (c);
                }
            }
        }

        void drop_transition_after (Clip c) {
            var dead = new Gee.ArrayList<Transition> ();
            foreach (var t in seq.transitions) if (t.from_clip == c.id) dead.add (t);
            foreach (var t in dead) seq.transitions.remove (t);
        }

        void drop_transition_before (Clip c) {
            var dead = new Gee.ArrayList<Transition> ();
            foreach (var t in seq.transitions) if (t.to_clip == c.id) dead.add (t);
            foreach (var t in dead) seq.transitions.remove (t);
        }

        Gee.HashSet<string> ripple_tracks (Gee.Collection<string> tracks) {
            var r = new Gee.HashSet<string> ();
            r.add_all (tracks);
            foreach (var t in seq.tracks) if (t.sync_lock && !t.locked) r.add (t.id);
            return r;
        }

        void split_track_at (string track_id, int64 t) {
            var c = seq.clip_at (track_id, t);
            if (c == null || c.position == t) return;
            split_clip (c, t);
        }

        Clip split_clip (Clip c, int64 t) {
            var right = c.copy ();
            right.id = new_id ();
            if (c.link != "") right.link = relink (c.link, t);
            trim_head_raw (right, t - c.position);
            int64 tail = c.end - t;
            c.duration -= tail;
            if (c.reverse) c.in_point += source_delta (c, tail);
            var keep = new Gee.ArrayList<Marker> ();
            foreach (var m in c.markers) if (m.time < c.duration) keep.add (m);
            c.markers = keep;
            var right_markers = new Gee.ArrayList<Marker> ();
            foreach (var m in right.markers) if (m.time >= 0) right_markers.add (m);
            right.markers = right_markers;
            seq.clips.add (right);
            foreach (var tr in seq.transitions) if (tr.from_clip == c.id) tr.from_clip = right.id;
            return right;
        }

        void shift_after (Gee.Collection<string> tracks, int64 at, int64 delta, Gee.Collection<Clip>? skip = null) {
            foreach (var c in seq.clips) {
                if (!tracks.contains (c.track) || c.position < at) continue;
                if (skip != null && skip.contains (c)) continue;
                c.position += delta;
            }
            foreach (var m in seq.markers) if (m.time >= at && delta != 0 && tracks.size >= seq.tracks.size) m.time += delta;
        }

        public void place (Gee.List<Clip> clips, int64 at, bool insert) throws Error {
            if (clips.size == 0) return;
            int64 first = int64.MAX, last = 0;
            var tracks = new Gee.HashSet<string> ();
            foreach (var c in clips) {
                var t = seq.track (c.track);
                if (t == null) throw new IOError.INVALID_ARGUMENT (_("Choose a destination track."));
                if (t.locked) throw new IOError.PERMISSION_DENIED (_("Unlock the track %s before editing.").printf (t.name));
                first = int64.min (first, c.position);
                last = int64.max (last, c.end);
                tracks.add (c.track);
            }
            int64 offset = at - first;
            int64 span = last - first;
            project.checkpoint (insert ? _("Insert") : _("Overwrite"));
            if (insert) {
                var affected = ripple_tracks (tracks);
                foreach (var tid in affected) split_track_at (tid, at);
                shift_after (affected, at, span);
            }
            foreach (var c in clips) {
                c.position += offset;
                if (!insert) clear_range (c.track, c.position, c.end);
                seq.clips.add (c);
            }
            project.commit ();
        }

        public Gee.ArrayList<Clip> make_media_clips (MediaItem m, int64 in_point, int64 out_point, string? video_track, string? audio_track) {
            var r = new Gee.ArrayList<Clip> ();
            string link = m.has_video && m.has_audio && video_track != null && audio_track != null ? new_id () : "";
            int64 length = m.still ? out_point - in_point : int64.min (out_point, m.duration) - in_point;
            if (length <= 0) return r;
            if (m.kind == "multicam") {
                if (video_track != null) {
                    var c = new Clip ();
                    c.kind = ClipKind.MULTICAM;
                    c.media = m.id;
                    c.track = video_track;
                    c.in_point = in_point;
                    c.duration = length;
                    c.link = link;
                    r.add (c);
                }
                if (audio_track != null) {
                    var a = new Clip ();
                    a.kind = ClipKind.MULTICAM;
                    a.media = m.id;
                    a.track = audio_track;
                    a.in_point = in_point;
                    a.duration = length;
                    a.link = link;
                    r.add (a);
                }
                return r;
            }
            if (m.has_video && video_track != null) {
                var c = new Clip ();
                c.media = m.id;
                c.track = video_track;
                c.in_point = in_point;
                c.duration = length;
                c.link = link;
                r.add (c);
            }
            if (m.has_audio && audio_track != null) {
                var c = new Clip ();
                c.media = m.id;
                c.track = audio_track;
                c.in_point = in_point;
                c.duration = length;
                c.link = link;
                r.add (c);
            }
            return r;
        }

        public Gee.ArrayList<Clip> selection_with_links (Gee.Collection<string> ids, bool follow_links = true) {
            var r = new Gee.ArrayList<Clip> ();
            var seen = new Gee.HashSet<string> ();
            foreach (var id in ids) {
                var c = seq.clip (id);
                if (c == null) continue;
                var group = follow_links ? seq.linked (c) : new Gee.ArrayList<Clip> ();
                if (!follow_links) group.add (c);
                foreach (var g in group) if (seen.add (g.id)) r.add (g);
            }
            return r;
        }

        public void split (int64 t, Gee.Collection<string> ids) throws Error {
            t = seq.snap (t);
            var targets = new Gee.ArrayList<Clip> ();
            if (ids.size > 0) {
                foreach (var c in selection_with_links (ids)) if (t > c.position && t < c.end) targets.add (c);
            } else {
                foreach (var c in seq.clips) {
                    var tr = seq.track (c.track);
                    if (tr != null && !tr.locked && t > c.position && t < c.end) targets.add (c);
                }
            }
            if (targets.size == 0) throw new IOError.INVALID_ARGUMENT (_("Place the playhead over a clip to split it."));
            foreach (var c in targets) ensure_unlocked (c);
            project.checkpoint (_("Split"));
            var links = new Gee.HashMap<string, string> ();
            foreach (var c in targets) {
                var right = split_clip (c, t);
                if (c.link != "") {
                    if (!links.has_key (c.link)) links[c.link] = new_id ();
                    right.link = links[c.link];
                }
            }
            project.commit ();
        }

        public void lift (Gee.Collection<string> ids) throws Error {
            var clips = selection_with_links (ids);
            if (clips.size == 0) return;
            foreach (var c in clips) ensure_unlocked (c);
            project.checkpoint (_("Delete"));
            foreach (var c in clips) remove_clip (c);
            project.commit ();
        }

        public void ripple_delete (Gee.Collection<string> ids) throws Error {
            var clips = selection_with_links (ids);
            if (clips.size == 0) return;
            foreach (var c in clips) ensure_unlocked (c);
            project.checkpoint (_("Ripple Delete"));
            int64 start = int64.MAX, end = 0;
            var tracks = new Gee.HashSet<string> ();
            foreach (var c in clips) {
                start = int64.min (start, c.position);
                end = int64.max (end, c.end);
                tracks.add (c.track);
                remove_clip (c);
            }
            ripple_close (tracks, start, end);
            project.commit ();
        }

        void ripple_close (Gee.Collection<string> tracks, int64 start, int64 end) {
            var affected = new Gee.HashSet<string> ();
            foreach (var tid in ripple_tracks (tracks)) {
                bool blocked = false;
                foreach (var c in seq.clips) if (c.track == tid && c.position < end && c.end > start) blocked = true;
                if (!blocked) affected.add (tid);
            }
            shift_after (affected, end, start - end);
        }

        public void delete_range (int64 start, int64 end, bool ripple) throws Error {
            start = seq.snap (start);
            end = seq.snap (end);
            if (end <= start) throw new IOError.INVALID_ARGUMENT (_("Mark an in and out point first."));
            project.checkpoint (ripple ? _("Extract") : _("Lift"));
            var tracks = new Gee.ArrayList<string> ();
            foreach (var t in seq.tracks) {
                if (t.locked || !t.target) continue;
                clear_range (t.id, start, end);
                tracks.add (t.id);
            }
            if (ripple) shift_after (tracks, end, start - end);
            project.commit ();
        }

        public void remove_ranges (Gee.List<int64?> starts, Gee.List<int64?> ends, string label) throws Error {
            if (starts.size == 0) return;
            project.checkpoint (label);
            var order = new Gee.ArrayList<int> ();
            for (int i = 0; i < starts.size; i++) order.add (i);
            order.sort ((a, b) => starts[a] > starts[b] ? -1 : (starts[a] < starts[b] ? 1 : 0));
            foreach (int i in order) {
                int64 s = starts[i], e = ends[i];
                if (e <= s) continue;
                var tracks = new Gee.ArrayList<string> ();
                foreach (var t in seq.tracks) {
                    if (t.locked) continue;
                    clear_range (t.id, s, e);
                    tracks.add (t.id);
                }
                shift_after (tracks, e, s - e);
            }
            project.commit ();
        }

        Clip? neighbour (Clip c, bool before) {
            Clip? best = null;
            foreach (var o in seq.on_track (c.track)) {
                if (o == c) continue;
                if (before && o.end <= c.position && (best == null || o.end > best.end)) best = o;
                if (!before && o.position >= c.end && (best == null || o.position < best.position)) best = o;
            }
            return best;
        }

        int64 head_room (Clip c) {
            if (c.kind.generated ()) return int64.MAX / 4;
            return c.reverse ? project.media_length (c) - c.in_point - c.source_span () : c.in_point;
        }

        int64 tail_room (Clip c) {
            if (c.kind.generated ()) return int64.MAX / 4;
            var s = c.params.values["speed"];
            double speed = s == null ? 1 : double.max (0.01, s.at (c.in_point) / 100.0);
            int64 source_left = c.reverse ? c.in_point : project.media_length (c) - c.in_point - c.source_span ();
            return (int64) (source_left / speed);
        }

        public int64 trim (string clip_id, bool head, int64 delta, TrimMode mode, bool follow_links = true) throws Error {
            var c = seq.clip (clip_id);
            if (c == null) throw new IOError.NOT_FOUND (_("The clip no longer exists."));
            delta = seq.snap (delta);
            if (delta == 0) return 0;
            var group = follow_links ? seq.linked (c) : new Gee.ArrayList<Clip> ();
            if (!follow_links) group.add (c);
            foreach (var g in group) ensure_unlocked (g);
            int64 applied = delta;
            int64 frame = seq.frame;
            foreach (var g in group) applied = clamp_trim (g, head, applied, mode, frame);
            if (applied == 0) throw new IOError.INVALID_ARGUMENT (_("There is no more media to trim into."));
            project.checkpoint (mode.label ());
            foreach (var g in group) apply_trim (g, head, applied, mode);
            project.commit ();
            return applied;
        }

        int64 clamp_trim (Clip c, bool head, int64 delta, TrimMode mode, int64 frame) {
            int64 d = delta;
            switch (mode) {
                case TrimMode.SLIP:
                    if (c.kind.generated ()) return 0;
                    int64 lo = -c.in_point;
                    int64 hi = project.media_length (c) - c.in_point - c.source_span ();
                    return d.clamp (lo, int64.max (lo, hi));
                case TrimMode.SLIDE: {
                    var prev = neighbour (c, true);
                    var next = neighbour (c, false);
                    if (prev != null) d = int64.max (d, -(prev.duration - frame));
                    else d = int64.max (d, -c.position);
                    if (next != null) d = int64.min (d, next.duration - frame);
                    if (prev != null && prev.end == c.position) d = int64.min (d, tail_room (prev));
                    if (next != null && next.position == c.end) d = int64.max (d, -head_room (next));
                    return d;
                }
                case TrimMode.ROLL: {
                    var other = neighbour (c, head);
                    if (head) {
                        d = int64.max (d, -head_room (c));
                        d = int64.min (d, c.duration - frame);
                        if (other != null && other.end == c.position) {
                            d = int64.max (d, -(other.duration - frame));
                            d = int64.min (d, tail_room (other));
                        }
                    } else {
                        d = int64.min (d, tail_room (c));
                        d = int64.max (d, -(c.duration - frame));
                        if (other != null && other.position == c.end) {
                            d = int64.min (d, other.duration - frame);
                            d = int64.max (d, -head_room (other));
                        }
                    }
                    return d;
                }
                default:
                    if (head) {
                        d = int64.max (d, -head_room (c));
                        d = int64.min (d, c.duration - frame);
                        if (mode == TrimMode.NORMAL) {
                            var prev = neighbour (c, true);
                            int64 floor = prev != null ? prev.end : 0;
                            d = int64.max (d, floor - c.position);
                        }
                    } else {
                        d = int64.min (d, tail_room (c));
                        d = int64.max (d, -(c.duration - frame));
                        if (mode == TrimMode.NORMAL) {
                            var next = neighbour (c, false);
                            if (next != null) d = int64.min (d, next.position - c.end);
                        }
                    }
                    return d;
            }
        }

        void apply_trim (Clip c, bool head, int64 d, TrimMode mode) {
            switch (mode) {
                case TrimMode.SLIP:
                    c.in_point += d;
                    c.params.shift (d);
                    break;
                case TrimMode.SLIDE: {
                    var prev = neighbour (c, true);
                    var next = neighbour (c, false);
                    if (prev != null && prev.end == c.position) trim_tail_raw (prev, d);
                    if (next != null && next.position == c.end) trim_head_raw (next, d);
                    c.position += d;
                    break;
                }
                case TrimMode.ROLL: {
                    var other = neighbour (c, head);
                    if (head) {
                        if (other != null && other.end == c.position) trim_tail_raw (other, d);
                        trim_head_raw (c, d);
                    } else {
                        if (other != null && other.position == c.end) trim_head_raw (other, d);
                        trim_tail_raw (c, d);
                    }
                    break;
                }
                case TrimMode.RIPPLE: {
                    var tracks = new Gee.ArrayList<string> ();
                    tracks.add (c.track);
                    var skip = new Gee.ArrayList<Clip> ();
                    skip.add (c);
                    if (head) {
                        int64 old_end = c.end;
                        trim_head_raw (c, d);
                        c.position -= d;
                        shift_after (tracks, old_end, -d, skip);
                    } else {
                        int64 old_end = c.end;
                        trim_tail_raw (c, d);
                        shift_after (tracks, old_end, d, skip);
                    }
                    break;
                }
                default:
                    if (head) trim_head_raw (c, d);
                    else trim_tail_raw (c, d);
                    break;
            }
        }

        public void move (Gee.Collection<string> ids, int64 delta, int track_offset, bool insert) throws Error {
            var clips = selection_with_links (ids);
            if (clips.size == 0) return;
            int64 min_pos = int64.MAX;
            foreach (var c in clips) {
                ensure_unlocked (c);
                min_pos = int64.min (min_pos, c.position);
            }
            delta = seq.snap (delta);
            if (min_pos + delta < 0) delta = -min_pos;
            var targets = new Gee.HashMap<string, string> ();
            foreach (var c in clips) {
                int idx = seq.track_index (c.track);
                var kind = seq.tracks[idx].kind;
                var same = seq.tracks_of (kind);
                int k = same.index_of (seq.tracks[idx]);
                bool moves = ids.contains (c.id) || track_offset == 0;
                int target = moves ? (k + track_offset).clamp (0, same.size - 1) : k;
                var dest = same[target];
                if (dest.locked) throw new IOError.PERMISSION_DENIED (_("Unlock the track %s before editing.").printf (dest.name));
                targets[c.id] = dest.id;
            }
            if (delta == 0 && track_offset == 0) return;
            project.checkpoint (_("Move"));
            foreach (var c in clips) seq.clips.remove (c);
            foreach (var c in clips) {
                c.position += delta;
                c.track = targets[c.id];
            }
            if (insert) {
                int64 at = int64.MAX, span = 0;
                var tracks = new Gee.HashSet<string> ();
                foreach (var c in clips) {
                    at = int64.min (at, c.position);
                    tracks.add (c.track);
                }
                foreach (var c in clips) span = int64.max (span, c.end - at);
                var affected = ripple_tracks (tracks);
                foreach (var tid in affected) split_track_at (tid, at);
                shift_after (affected, at, span);
            } else {
                foreach (var c in clips) clear_range (c.track, c.position, c.end);
            }
            foreach (var c in clips) seq.clips.add (c);
            var dead = new Gee.ArrayList<Transition> ();
            foreach (var t in seq.transitions) {
                var a = seq.clip (t.from_clip);
                var b = seq.clip (t.to_clip);
                if ((t.from_clip != "" && a == null) || (t.to_clip != "" && b == null)) dead.add (t);
                else if (a != null && b != null && (a.track != b.track || a.end != b.position)) dead.add (t);
                else if (a != null) t.track = a.track;
                else if (b != null) t.track = b.track;
            }
            foreach (var t in dead) seq.transitions.remove (t);
            project.commit ();
        }

        public void set_speed (string clip_id, double percent, bool reverse, bool ripple, bool frame_blend) throws Error {
            var c = seq.clip (clip_id);
            if (c == null) return;
            ensure_unlocked (c);
            percent = percent.clamp (1, 10000);
            var group = seq.linked (c);
            project.checkpoint (_("Speed"));
            foreach (var g in group) {
                int64 span = g.source_span ();
                var speed = g.params.ensure ("speed", 100);
                speed.keys.clear ();
                speed.value = percent;
                g.reverse = reverse;
                g.frame_blend = frame_blend;
                int64 old_end = g.end;
                g.duration = int64.max (seq.frame, seq.snap ((int64) (span * 100.0 / percent)));
                int64 delta = g.end - old_end;
                if (ripple && delta != 0) {
                    var tracks = new Gee.ArrayList<string> ();
                    tracks.add (g.track);
                    var skip = new Gee.ArrayList<Clip> ();
                    skip.add (g);
                    shift_after (tracks, old_end, delta, skip);
                } else if (delta > 0) {
                    var keep = new Gee.ArrayList<Clip> ();
                    keep.add (g);
                    clear_range (g.track, old_end, g.end, keep);
                }
            }
            project.commit ();
        }

        public void close_gaps (string track_id) throws Error {
            var t = seq.track (track_id);
            if (t == null || t.locked) throw new IOError.PERMISSION_DENIED (_("Choose an unlocked track."));
            project.checkpoint (_("Close Gaps"));
            int64 cursor = 0;
            foreach (var c in seq.on_track (track_id)) {
                if (c.position > cursor) {
                    int64 d = c.position - cursor;
                    foreach (var l in seq.linked (c)) if (l.track != track_id) l.position -= d;
                    c.position = cursor;
                }
                cursor = c.end;
            }
            project.commit ();
        }

        public Transition add_transition (string clip_id, bool at_end, string kind, int64 duration, int align) throws Error {
            var c = seq.clip (clip_id);
            if (c == null) throw new IOError.NOT_FOUND (_("Select a clip first."));
            ensure_unlocked (c);
            var t = new Transition ();
            t.kind = kind;
            t.track = c.track;
            t.duration = int64.max (seq.frame, seq.snap (duration));
            t.align = align;
            Clip? other = null;
            foreach (var o in seq.on_track (c.track)) {
                if (at_end && o.position == c.end) other = o;
                if (!at_end && o.end == c.position) other = o;
            }
            if (at_end) {
                t.from_clip = c.id;
                t.to_clip = other != null ? other.id : "";
            } else {
                t.from_clip = other != null ? other.id : "";
                t.to_clip = c.id;
            }
            if (t.from_clip == "" || t.to_clip == "") t.align = at_end ? -1 : 1;
            var existing = seq.transition_between (t.from_clip, t.to_clip);
            project.checkpoint (_("Add Transition"));
            if (existing != null) seq.transitions.remove (existing);
            seq.transitions.add (t);
            project.commit ();
            return t;
        }

        public Sequence nest (Gee.Collection<string> ids, string name) throws Error {
            var clips = selection_with_links (ids);
            if (clips.size == 0) throw new IOError.INVALID_ARGUMENT (_("Select clips to nest."));
            foreach (var c in clips) ensure_unlocked (c);
            int64 start = int64.MAX, end = 0;
            foreach (var c in clips) {
                start = int64.min (start, c.position);
                end = int64.max (end, c.end);
            }
            project.checkpoint (_("Nest"));
            var nested = new Sequence (name);
            nested.width = seq.width; nested.height = seq.height; nested.fps_n = seq.fps_n; nested.fps_d = seq.fps_d;
            nested.sample_rate = seq.sample_rate; nested.color_space = seq.color_space;
            var map = new Gee.HashMap<string, string> ();
            foreach (var t in seq.tracks) {
                bool used = false;
                foreach (var c in clips) if (c.track == t.id) used = true;
                if (!used) continue;
                var nt = new Track (t.name, t.kind);
                nested.tracks.add (nt);
                map[t.id] = nt.id;
            }
            foreach (var c in clips) {
                var moved = c.copy ();
                moved.track = map[c.track];
                moved.position -= start;
                nested.clips.add (moved);
            }
            foreach (var t in seq.transitions.to_array ()) {
                bool inside = false;
                foreach (var c in clips) if (t.from_clip == c.id || t.to_clip == c.id) inside = true;
                if (!inside) continue;
                var nt = t.copy ();
                nt.track = map.has_key (t.track) ? map[t.track] : t.track;
                nested.transitions.add (nt);
            }
            string? video = null, audio = null;
            foreach (var c in clips) {
                var tr = seq.track (c.track);
                if (tr.kind == TrackKind.VIDEO && (video == null || seq.track_index (c.track) < seq.track_index (video))) video = c.track;
                if (tr.kind == TrackKind.AUDIO && (audio == null || seq.track_index (c.track) < seq.track_index (audio))) audio = c.track;
            }
            foreach (var c in clips) remove_clip (c);
            project.sequences.add (nested);
            string link = video != null && audio != null ? new_id () : "";
            foreach (var tid in new string?[] { video, audio }) {
                if (tid == null) continue;
                var nc = new Clip ();
                nc.kind = ClipKind.SEQUENCE;
                nc.sequence = nested.id;
                nc.track = tid;
                nc.position = start;
                nc.duration = end - start;
                nc.link = link;
                seq.clips.add (nc);
            }
            project.commit ();
            return nested;
        }

        public void link (Gee.Collection<string> ids, bool linked) throws Error {
            var clips = new Gee.ArrayList<Clip> ();
            foreach (var id in ids) {
                var c = seq.clip (id);
                if (c != null) clips.add (c);
            }
            if (clips.size == 0) return;
            project.checkpoint (linked ? _("Link") : _("Unlink"));
            string group = new_id ();
            foreach (var c in clips) c.link = linked && clips.size > 1 ? group : "";
            project.commit ();
        }

        public Track add_track (TrackKind kind) {
            project.checkpoint (_("Add Track"));
            int count = seq.tracks_of (kind).size + 1;
            string prefix = kind == TrackKind.AUDIO ? "A" : (kind == TrackKind.SUBTITLE ? "S" : "V");
            var t = new Track ("%s%d".printf (prefix, count), kind);
            int at = 0;
            for (int i = 0; i < seq.tracks.size; i++) if (seq.tracks[i].kind == kind) at = i + 1;
            if (at == 0) {
                if (kind == TrackKind.AUDIO) at = seq.tracks.size;
                else if (kind == TrackKind.SUBTITLE) at = seq.tracks.size;
            }
            seq.tracks.insert (at, t);
            project.commit ();
            return t;
        }

        public void remove_track (string id) throws Error {
            var t = seq.track (id);
            if (t == null) return;
            if (seq.tracks_of (t.kind).size <= 1 && t.kind != TrackKind.SUBTITLE) throw new IOError.INVALID_ARGUMENT (_("A sequence needs at least one track of each kind."));
            project.checkpoint (_("Remove Track"));
            foreach (var c in seq.on_track (id)) remove_clip (c);
            seq.tracks.remove (t);
            project.commit ();
        }

        public Marker add_marker (int64 t, string name, string kind) {
            project.checkpoint (_("Add Marker"));
            var m = new Marker (seq.snap (t), name);
            m.kind = kind;
            seq.markers.add (m);
            seq.markers.sort ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
            project.commit ();
            return m;
        }

        public int64 snap_point (int64 t, int64 tolerance, Gee.Collection<string>? ignore = null) {
            int64 best = t;
            int64 dist = tolerance + 1;
            var points = new Gee.ArrayList<int64?> ();
            points.add (0);
            points.add (seq.playhead);
            foreach (var c in seq.clips) {
                if (ignore != null && ignore.contains (c.id)) continue;
                points.add (c.position);
                points.add (c.end);
            }
            foreach (var m in seq.markers) points.add (m.time);
            if (seq.in_point >= 0) points.add (seq.in_point);
            if (seq.out_point >= 0) points.add (seq.out_point);
            foreach (var p in points) {
                int64 d = (p - t).abs ();
                if (d < dist) {
                    dist = d;
                    best = p;
                }
            }
            return best;
        }

        public int64 sync_offset (Clip c) {
            if (c.link == "") return 0;
            foreach (var o in seq.linked (c)) {
                if (o == c || o.media != c.media || o.kind != c.kind) continue;
                return (o.position - o.in_point) - (c.position - c.in_point);
            }
            return 0;
        }

        public void resync (string clip_id) throws Error {
            var c = seq.clip (clip_id);
            if (c == null) return;
            int64 offset = sync_offset (c);
            if (offset == 0) return;
            ensure_unlocked (c);
            project.checkpoint (_("Move into Sync"));
            c.position += offset;
            if (c.position < 0) {
                trim_head_raw (c, -c.position);
            }
            clear_range (c.track, c.position, c.end, new Gee.ArrayList<Clip>.wrap ({ c }));
            project.commit ();
        }
    }
}
