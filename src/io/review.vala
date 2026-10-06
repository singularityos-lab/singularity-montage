namespace Singularity.Apps.Montage {
    namespace Review {
        public string comments_json (Sequence s) {
            var b = new Json.Builder ();
            b.begin_object ();
            Js.s (b, "format", "montage-review");
            Js.i (b, "version", 1);
            Js.s (b, "sequence", s.name);
            Js.d (b, "fps", (double) s.fps_n / s.fps_d);
            b.set_member_name ("comments");
            b.begin_array ();
            foreach (var c in s.comments) c.write (b);
            b.end_array ();
            b.end_object ();
            return Js.write (b.get_root (), true);
        }

        public int merge (Project p, Sequence s, string text) throws Error {
            var o = Js.parse (text);
            if (Js.str (o, "format") != "montage-review") throw new IOError.INVALID_DATA (_("This is not a Montage review file."));
            int added = 0;
            p.checkpoint (_("Import Review Comments"));
            foreach (var co in Js.objects (o, "comments")) {
                var incoming = ReviewComment.read (co);
                ReviewComment? existing = null;
                foreach (var c in s.comments) if (c.id == incoming.id) existing = c;
                if (existing == null) {
                    s.comments.add (incoming);
                    added++;
                    continue;
                }
                if (incoming.resolved) existing.resolved = true;
                foreach (var r in incoming.replies) {
                    bool known = false;
                    foreach (var er in existing.replies) if (er.author == r.author && er.text == r.text && er.created == r.created) known = true;
                    if (!known) {
                        existing.replies.add (r);
                        added++;
                    }
                }
            }
            s.comments.sort ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
            p.commit ();
            return added;
        }

        public string html (Sequence s, string video_name) {
            string data = comments_json (s).replace ("</", "<\\/");
            return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Review: %s</title>
<style>
:root { color-scheme: light dark; --bg: #f6f5f4; --fg: #1d1d1f; --card: #ffffff; --accent: #1c71d8; }
@media (prefers-color-scheme: dark) { :root { --bg: #18181b; --fg: #f2f2f2; --card: #26262a; --accent: #78aeed; } }
body { margin: 0; font: 15px/1.45 system-ui, sans-serif; background: var(--bg); color: var(--fg); }
main { max-width: 1100px; margin: 0 auto; padding: 16px; display: grid; gap: 16px; grid-template-columns: minmax(0, 2fr) minmax(0, 1fr); }
@media (max-width: 760px) { main { grid-template-columns: 1fr; } }
video { width: 100%%; border-radius: 10px; background: #000; }
section { background: var(--card); border-radius: 10px; padding: 12px; }
.c { padding: 8px 0; border-bottom: 1px solid rgba(127,127,127,.25); cursor: pointer; }
.t { font-variant-numeric: tabular-nums; color: var(--accent); font-weight: 600; }
.done { opacity: .55; }
textarea, input { width: 100%%; box-sizing: border-box; margin: 4px 0; font: inherit; padding: 6px; border-radius: 6px; border: 1px solid rgba(127,127,127,.4); background: transparent; color: inherit; }
button { font: inherit; padding: 6px 14px; border-radius: 99px; border: 0; background: var(--accent); color: #fff; margin-top: 4px; }
</style></head><body><main>
<div><video id="v" controls src="%s"></video><h1>%s</h1></div>
<section><h2>Comments</h2><div id="list"></div>
<input id="author" placeholder="Your name"><textarea id="text" rows="3" placeholder="Comment at the current time"></textarea>
<button id="add">Add Comment</button> <button id="save">Download Comments</button></section>
</main>
<script>
const data = %s;
const fps = data.fps || 25;
const v = document.getElementById('v');
function tc(ns) { const s = ns / 1e9; const f = Math.floor((s %% 1) * fps); const t = Math.floor(s); return [Math.floor(t / 3600), Math.floor(t / 60) %% 60, t %% 60, f].map(n => String(n).padStart(2, '0')).join(':'); }
function render() {
  const list = document.getElementById('list'); list.textContent = '';
  data.comments.sort((a, b) => a.time - b.time).forEach(c => {
    const d = document.createElement('div'); d.className = 'c' + (c.resolved ? ' done' : '');
    const head = document.createElement('div'); head.innerHTML = '<span class="t"></span> <b></b>';
    head.children[0].textContent = tc(c.time); head.children[1].textContent = c.author || '';
    const body = document.createElement('div'); body.textContent = c.text;
    d.append(head, body);
    (c.replies || []).forEach(r => { const rr = document.createElement('div'); rr.textContent = (r.author ? r.author + ': ' : '') + r.text; rr.style.marginLeft = '14px'; d.append(rr); });
    d.onclick = () => { v.currentTime = c.time / 1e9; };
    list.append(d);
  });
}
document.getElementById('add').onclick = () => {
  const text = document.getElementById('text').value.trim(); if (!text) return;
  data.comments.push({ id: 'r' + Math.random().toString(36).slice(2), time: Math.round(v.currentTime * 1e9), duration: 0,
    author: document.getElementById('author').value.trim(), text, resolved: false, created: Math.floor(Date.now() / 1000), replies: [] });
  document.getElementById('text').value = ''; render();
};
document.getElementById('save').onclick = () => {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 1)], { type: 'application/json' }));
  a.download = 'review-comments.json'; a.click();
};
render();
</script></body></html>
""".printf (Markup.escape_text (s.name), Markup.escape_text (Uri.escape_string (video_name)), Markup.escape_text (s.name), data);
        }
    }

    namespace SharedProject {
        public string me () {
            return "%s@%s".printf (Environment.get_user_name (), Environment.get_host_name ());
        }

        File lock_dir (File project) {
            return project.get_parent ().get_child (".%s.locks".printf (project.get_basename ()));
        }

        public string? holder (File project, string seq_id) {
            var f = lock_dir (project).get_child (seq_id + ".lock");
            try {
                string text;
                if (!FileUtils.get_contents (f.get_path (), out text)) return null;
                return text.strip ().split ("\n")[0];
            } catch (Error e) {
                return null;
            }
        }

        public bool is_mine (string holder) {
            return holder == me ();
        }

        public void acquire (File project, string seq_id) throws Error {
            var dir = lock_dir (project);
            if (!dir.query_exists ()) dir.make_directory ();
            var f = dir.get_child (seq_id + ".lock");
            try {
                var stream = f.create (FileCreateFlags.NONE);
                stream.write ((me () + "\n" + new DateTime.now_utc ().to_string () + "\n").data);
                stream.close ();
            } catch (IOError.EXISTS e) {
                string? h = holder (project, seq_id);
                if (h != null && !is_mine (h)) throw new IOError.BUSY (_("%s is editing this sequence.").printf (h));
            }
        }

        public void release (File project, string seq_id) throws Error {
            var f = lock_dir (project).get_child (seq_id + ".lock");
            string? h = holder (project, seq_id);
            if (h != null && is_mine (h)) f.delete ();
        }

        public bool can_edit (File? project, string seq_id) {
            if (project == null) return true;
            string? h = holder (project, seq_id);
            return h == null || is_mine (h);
        }

        public bool shared (File? project) {
            return project != null && lock_dir (project).query_exists ();
        }

        public void refresh_locks (Project p, File? origin) {
            p.foreign_locks.clear ();
            if (origin == null) return;
            foreach (var s in p.sequences) {
                string? h = holder (origin, s.id);
                if (h != null && !is_mine (h)) p.foreign_locks.add (s.id);
            }
        }

        public int merge_from_disk (Project mine, File project) throws Error {
            if (!project.query_exists ()) return 0;
            var theirs = NativeFormat.load (project);
            int taken = 0;
            foreach (var s in theirs.sequences) {
                string? h = holder (project, s.id);
                bool mine_locked = h != null && is_mine (h);
                var local = mine.find_sequence (s.id);
                if (local == null) {
                    mine.sequences.add (s);
                    taken++;
                } else if (!mine_locked && h != null) {
                    int i = mine.sequences.index_of (local);
                    mine.sequences[i] = s;
                    taken++;
                }
            }
            foreach (var m in theirs.media) if (mine.find_media (m.id) == null && mine.media_by_uri (m.uri) == null) {
                mine.media.add (m);
                taken++;
            }
            foreach (var b in theirs.bins) if (mine.find_bin (b.id) == null) mine.bins.add (b);
            return taken;
        }
    }
}
