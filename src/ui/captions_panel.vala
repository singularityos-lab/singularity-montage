using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace TranscribeOps {
        public void transcribe (MontageWindow w) {
            var c = w.ctl.primary;
            MediaItem? m = null;
            if (c != null && (c.kind == ClipKind.MEDIA || c.kind == ClipKind.MULTICAM)) m = w.project.find_media (c.media);
            if (m == null && w.ctl.source_media != null) m = w.ctl.source_media;
            if (m == null || !m.has_audio) {
                w.say (_("Select a clip with sound to transcribe."));
                return;
            }
            var app = (MontageApp) w.application;
            var backend = Speech.find (app.get_str ("transcription-command", ""));
            if (backend == null) {
                w.say (_("No speech recognition is available. Turn on dictation in Settings, Keyboard, or set a transcription command in Montage settings."));
                return;
            }
            string uri = m.uri;
            int64 duration = m.duration;
            string lang = app.get_str ("transcription-language", "");
            if (lang == "") lang = Intl.get_language_names ()[0].split ("_")[0];
            string media_id = m.id;
            string tmp = Path.build_filename (Environment.get_user_cache_dir (), "singularity-montage", "speech", new_id ());
            Gee.ArrayList<Word>? words = null;
            Tasks.run (w, _("Transcribing with %s").printf (backend.name), (p) => { words = Speech.transcribe (uri, 0, duration, lang, backend, tmp, p); }, (err) => {
                DirUtils.remove (tmp);
                if (err != null) {
                    w.say (err);
                    return;
                }
                var item = w.project.find_media (media_id);
                if (item == null) return;
                w.project.checkpoint (_("Transcribe"));
                item.transcript = Transcript.serialize (words);
                w.project.commit ();
                w.say (ngettext ("Transcribed %d word. Open the Captions workspace to edit by text.", "Transcribed %d words. Open the Captions workspace to edit by text.", words.size).printf (words.size));
                w.activate_action ("win.workspace", new Variant.string ("captions"));
            });
        }
    }

    public class CaptionsPanel : Box {
        MontageWindow w;
        Controller ctl;
        FlowBox words = new FlowBox ();
        PreferencesGroup transcript_group;
        PreferencesGroup caption_group;
        ActionRow remove_row;
        int selection_start = -1;
        int selection_end = -1;
        Gee.ArrayList<Word> current_words = new Gee.ArrayList<Word> ();
        Clip? current_clip;

        public CaptionsPanel (MontageWindow w) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.w = w;
            ctl = w.ctl;
            spacing = 12;
            var tg = new PreferencesGroup ();
            tg.title = _("Transcript");
            transcript_group = tg;
            var transcribe = new Button.with_label (_("Transcribe"));
            transcribe.tooltip_text = _("Transcribe the selected clip");
            transcribe.valign = Align.CENTER;
            transcribe.clicked.connect (() => w.activate_action ("win.transcribe", null));
            tg.add_header_suffix (transcribe);
            words.selection_mode = SelectionMode.NONE;
            words.max_children_per_line = 40;
            words.column_spacing = 2;
            words.row_spacing = 2;
            words.margin_top = words.margin_bottom = 8;
            words.margin_start = words.margin_end = 8;
            tg.add_row (words);
            remove_row = Rows.remove (_("Remove Selected Words"), remove_selection);
            remove_row.subtitle = _("Cut the selected phrase out of the timeline");
            tg.add_row (remove_row);
            tg.add_row (Rows.action (_("Create Captions"), _("Turn the transcripts of the sequence into captions"), make_captions));
            append (tg);
            var cg = new PreferencesGroup ();
            cg.title = _("Captions");
            caption_group = cg;
            var add = new Button.from_icon_name ("list-add-symbolic");
            add.tooltip_text = _("Add a caption at the playhead");
            add.valign = Align.CENTER;
            add.clicked.connect (() => {
                var cues = new Gee.ArrayList<Cue> ();
                cues.add (new Cue (ctl.playhead, ctl.playhead + 2 * Tc.SECOND, _("New caption")));
                try {
                    Subtitles.add_cues (ctl.project, cues, _("Add Caption"));
                } catch (Error e) {
                    w.say (e.message);
                }
            });
            cg.add_header_suffix (add);
            append (cg);
            var io = new PreferencesGroup ();
            io.title = _("Subtitle Files");
            io.add_row (Rows.action (_("Import SRT or WebVTT…"), null, () => w.activate_action ("win.import-subtitles", null)));
            io.add_row (Rows.action (_("Export SRT…"), null, () => w.activate_action ("win.export-srt", null)));
            io.add_row (Rows.action (_("Export WebVTT…"), null, () => w.activate_action ("win.export-vtt", null)));
            append (io);
            ctl.project.changed.connect (() => {
                if (get_mapped ()) rebuild ();
            });
            ctl.selection_changed.connect (() => {
                if (get_mapped ()) rebuild ();
            });
            map.connect (rebuild);
        }

        void clear (Widget container) {
            if (container is Box) {
                Widget? x;
                while ((x = ((Box) container).get_first_child ()) != null) ((Box) container).remove (x);
            } else if (container is FlowBox) {
                ((FlowBox) container).remove_all ();
            }
        }

        public void rebuild () {
            caption_group.clear ();
            foreach (var t in ctl.seq.tracks) {
                if (t.kind != TrackKind.SUBTITLE) continue;
                foreach (var c in ctl.seq.on_track (t.id)) {
                    var clip = c;
                    var row = new EntryRow ("%s  %s".printf (Tc.format (c.position, ctl.seq.fps_n, ctl.seq.fps_d), Tc.clock (c.duration)));
                    row.text = c.text.replace ("\n", " / ");
                    row.entry_activated.connect (() => {
                        ctl.project.checkpoint (_("Caption Text"));
                        clip.text = row.text.replace (" / ", "\n");
                        ctl.project.commit ();
                    });
                    var jump = new Button.from_icon_name ("media-playback-start-symbolic");
                    jump.add_css_class ("flat");
                    jump.valign = Align.CENTER;
                    jump.tooltip_text = _("Go to caption");
                    jump.clicked.connect (() => ctl.seek (clip.position));
                    row.add_suffix (jump);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete caption");
                    del.clicked.connect (() => {
                        ctl.project.checkpoint (_("Delete Caption"));
                        ctl.seq.clips.remove (clip);
                        ctl.project.commit ();
                    });
                    row.add_suffix (del);
                    caption_group.add_row (row);
                }
            }
            caption_group.description = caption_group.get_rows ().size == 0 ? _("No captions yet. Transcribe a clip or import a subtitle file.") : "";
            clear (words);
            current_words.clear ();
            current_clip = null;
            var c = ctl.primary;
            MediaItem? m = null;
            if (c != null && c.media != "") m = ctl.project.find_media (c.media);
            if (m == null || m.transcript == "") {
                transcript_group.description = m == null ? _("Select a clip on the timeline to see its transcript.") : _("This clip has no transcript yet.");
                words.visible = false;
                remove_row.visible = false;
                return;
            }
            current_clip = c;
            var all = Transcript.parse (m.transcript);
            int64 src0 = c.in_point, src1 = c.in_point + c.source_span ();
            foreach (var word in all) if (word.end > src0 && word.start < src1) current_words.add (word);
            transcript_group.description = _("Click a word to move there. Click the first and Shift click the last word of a phrase to select it.");
            words.visible = current_words.size > 0;
            remove_row.visible = current_words.size > 0;
            for (int i = 0; i < current_words.size; i++) {
                int index = i;
                var b = new ToggleButton.with_label (current_words[i].text);
                b.add_css_class ("flat");
                b.active = selection_start >= 0 && index >= selection_start && index <= selection_end;
                var click = new GestureClick ();
                click.pressed.connect ((n, x, y) => {
                    var state = click.get_current_event_state ();
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0 && selection_start >= 0) {
                        selection_end = index;
                        if (selection_end < selection_start) {
                            int tmp = selection_start;
                            selection_start = selection_end;
                            selection_end = tmp;
                        }
                    } else {
                        selection_start = selection_end = index;
                        var clip = current_clip;
                        if (clip != null) ctl.seek (clip.position + (current_words[index].start - clip.in_point));
                    }
                    Idle.add (() => {
                        rebuild ();
                        return Source.REMOVE;
                    });
                });
                b.add_controller (click);
                words.append (b);
            }
        }

        void remove_selection () {
            if (current_clip == null || selection_start < 0 || selection_end >= current_words.size) {
                w.say (_("Select words in the transcript first."));
                return;
            }
            var c = current_clip;
            int64 s = current_words[selection_start].start, e = current_words[selection_end].end;
            int64 t0 = c.position + int64.max (0, s - c.in_point);
            int64 t1 = c.position + int64.min (c.duration, e - c.in_point);
            var starts = new Gee.ArrayList<int64?> ();
            var ends = new Gee.ArrayList<int64?> ();
            starts.add (ctl.seq.snap (t0));
            ends.add (ctl.seq.snap (t1));
            try {
                ctl.edits.remove_ranges (starts, ends, _("Remove Words"));
                w.say (_("Removed \"%s\" from the timeline.").printf (selected_text ()));
                selection_start = selection_end = -1;
            } catch (Error err) {
                w.say (err.message);
            }
        }

        string selected_text () {
            var sb = new StringBuilder ();
            for (int i = selection_start; i <= selection_end && i < current_words.size; i++) {
                if (sb.len > 0) sb.append (" ");
                sb.append (current_words[i].text);
            }
            return sb.str;
        }

        void make_captions () {
            var cues = new Gee.ArrayList<Cue> ();
            foreach (var c in ctl.seq.clips) {
                var t = ctl.seq.track (c.track);
                if (t == null || t.kind != TrackKind.AUDIO || c.media == "") continue;
                var m = ctl.project.find_media (c.media);
                if (m == null || m.transcript == "") continue;
                var in_clip = new Gee.ArrayList<Word> ();
                foreach (var word in Transcript.parse (m.transcript)) {
                    if (word.end <= c.in_point || word.start >= c.in_point + c.source_span ()) continue;
                    in_clip.add (new Word (word.text, c.position + (word.start - c.in_point), c.position + (word.end - c.in_point)));
                }
                cues.add_all (Transcript.to_cues (in_clip));
            }
            if (cues.size == 0) {
                w.say (_("Transcribe the clips with sound first."));
                return;
            }
            try {
                Subtitles.add_cues (ctl.project, cues, _("Captions from Transcript"));
                w.say (ngettext ("Created %d caption.", "Created %d captions.", cues.size).printf (cues.size));
            } catch (Error e) {
                w.say (e.message);
            }
        }
    }
}
