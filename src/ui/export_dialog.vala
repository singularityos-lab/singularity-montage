using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    public class ExportDialog : AppDialog {
        MontageWindow w;
        Gee.ArrayList<ExportPreset> presets;
        ChoiceRow preset_drop;
        EntryRow file_row;
        ChoiceRow range_drop;
        SpinRow width_row;
        SpinRow height_row;
        SpinRow bitrate_row;
        SpinRow quality_row;
        SpinRow max_size_row;
        SwitchRow hardware_row;
        ChoiceRow subtitles_drop;
        SwitchRow chapters_row;
        SwitchRow normalize_row;
        ChoiceRow loudness_drop;
        ChoiceRow reframe_drop;
        PreferencesGroup fmt;
        File? folder;
        double[] targets = { -14, -16, -23, -24 };

        public ExportDialog (MontageWindow w) {
            base (w.application, true, false);
            this.w = w;
            title = _("Export");
            transient_for = w;
            set_default_size (560, 760);
            presets = Presets.usable ();
            var app = (MontageApp) w.application;
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            content_box.append (scroll);
            fmt = new PreferencesGroup ();
            fmt.title = _("Format");
            var names = new Gee.ArrayList<string> ();
            int initial = 0;
            string last = app.get_str ("last-preset", "web-1080");
            for (int i = 0; i < presets.size; i++) {
                names.add ("%s: %s".printf (presets[i].category, presets[i].name));
                if (presets[i].id == last) initial = i;
            }
            preset_drop = new ChoiceRow (_("Preset"), null, names.to_array (), initial);
            fmt.add_row (preset_drop);
            if (presets.size < Presets.all ().size) fmt.add_row (new ActionRow (_("More Formats"), Master.install_hint ()));
            fmt.add_row (Rows.action (_("Save as Preset"), _("Keep these settings in the preset list"), () => {
                try {
                    var p = current_preset ();
                    p.name = _("%s (custom)").printf (p.name);
                    Presets.save_user (p);
                    fmt.description = _("Preset saved.");
                } catch (Error e) {
                    fmt.description = e.message;
                }
            }));
            box.append (fmt);
            var dest = new PreferencesGroup ();
            dest.title = _("Destination");
            file_row = new EntryRow (_("File Name"));
            dest.add_row (file_row);
            var folder_row = new ActionRow (_("Folder"), "");
            var choose = new Button.with_label (_("Choose…"));
            choose.valign = Align.CENTER;
            choose.clicked.connect (() => {
                var dialog = new FileDialog ();
                dialog.select_folder.begin (this, null, (o, r) => {
                    try {
                        folder = dialog.select_folder.end (r);
                        folder_row.subtitle = folder.get_path () ?? folder.get_uri ();
                    } catch (Error e) {
                    }
                });
            });
            folder_row.add_suffix (choose);
            dest.add_row (folder_row);
            folder = w.session.origin != null ? w.session.origin.get_parent () : File.new_for_path (Environment.get_user_special_dir (UserDirectory.VIDEOS) ?? Environment.get_home_dir ());
            folder_row.subtitle = folder.get_path () ?? "";
            box.append (dest);
            var range = new PreferencesGroup ();
            range.title = _("Range and Size");
            bool has_marks = w.ctl.seq.in_point >= 0 || w.ctl.seq.out_point >= 0;
            range_drop = new ChoiceRow (_("Range"), null, { _("Whole Sequence"), _("In to Out"), _("Work Area Around Playhead (10 s)") }, has_marks ? 1 : 0);
            range.add_row (range_drop);
            width_row = new SpinRow (_("Width"), _("Pixels, 0 keeps the sequence size"), 0, 16384, 2, 0);
            height_row = new SpinRow (_("Height"), _("Pixels"), 0, 16384, 2, 0);
            range.add_row (width_row);
            range.add_row (height_row);
            reframe_drop = new ChoiceRow (_("Different Shape"), _("When the output is not the shape of the sequence"), { _("Fit with Borders"), _("Fill and Crop") });
            range.add_row (reframe_drop);
            box.append (range);
            var quality = new PreferencesGroup ();
            quality.title = _("Quality");
            bitrate_row = new SpinRow (_("Video Bitrate"), _("Kilobits per second, 0 uses the quality setting"), 0, 400000, 500, 0);
            quality_row = new SpinRow (_("Quality"), _("Higher is better and larger"), 1, 100, 1, 70);
            max_size_row = new SpinRow (_("Maximum File Size"), _("Megabytes, 0 for no limit"), 0, 100000, 10, 0);
            hardware_row = new SwitchRow (_("Hardware Encoding"), _("Use the graphics card encoder when available, otherwise the software encoder"), app.get_bool ("hardware-encoding", true));
            quality.add_row (bitrate_row);
            quality.add_row (quality_row);
            quality.add_row (max_size_row);
            quality.add_row (hardware_row);
            box.append (quality);
            var extras = new PreferencesGroup ();
            extras.title = _("Captions, Chapters and Loudness");
            subtitles_drop = new ChoiceRow (_("Captions"), null, { _("None"), _("Burn into Picture"), _("Embed as Track"), _("SRT File Next to Video"), _("WebVTT File Next to Video") });
            extras.add_row (subtitles_drop);
            chapters_row = new SwitchRow (_("Chapters"), _("Write chapter markers into the file"), true);
            extras.add_row (chapters_row);
            normalize_row = new SwitchRow (_("Normalize Loudness"), _("Measure the mix and match a loudness target"), w.ctl.seq.normalize);
            extras.add_row (normalize_row);
            int target_index = 0;
            for (int i = 0; i < targets.length; i++) if (targets[i] == w.ctl.seq.loudness_target) target_index = i;
            loudness_drop = new ChoiceRow (_("Target"), null, { _("Web and Social, -14 LUFS"), _("Podcast, -16 LUFS"), _("Broadcast EBU R128, -23 LUFS"), _("Broadcast ATSC A/85, -24 LUFS") }, target_index);
            extras.add_row (loudness_drop);
            box.append (extras);
            var buttons = new Box (Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            buttons.margin_start = buttons.margin_end = 18;
            buttons.margin_bottom = 16;
            buttons.margin_top = 8;
            var cancel = add_cancel_button (_("Cancel"));
            buttons.append (cancel);
            var queue = new Button.with_label (_("Add to Queue"));
            queue.add_css_class ("suggested-action");
            queue.clicked.connect (() => {
                if (submit ()) close_dialog ();
            });
            buttons.append (queue);
            content_box.append (buttons);
            preset_drop.notify["index"].connect (load_preset);
            load_preset ();
        }

        ExportPreset selected {
            owned get { return presets[(int) preset_drop.index]; }
        }

        void load_preset () {
            var p = selected;
            width_row.value = p.width;
            height_row.value = p.height;
            bitrate_row.value = p.vbitrate;
            quality_row.value = p.quality;
            max_size_row.value = p.max_size_mb;
            reframe_drop.index = p.reframe == "fill" ? 1 : 0;
            string base_name = (w.session.origin != null ? (w.session.origin.get_basename () ?? "").replace (".montage", "") : w.ctl.seq.name);
            file_row.text = base_name + "." + p.extension;
            bool video = !p.audio_only;
            width_row.sensitive = height_row.sensitive = bitrate_row.sensitive = quality_row.sensitive = video && !p.master;
            subtitles_drop.sensitive = video;
            string info;
            if (p.image_sequence) info = _("Writes one numbered %s file per frame with Montage's own writer.").printf (p.extension.up ());
            else if (p.audio_only) {
                string? enc = p.acodec == "pcm" ? "wavenc" : Encoders.audio (p.acodec);
                info = enc != null ? _("Audio encoder: %s").printf (enc) : _("No %s encoder is installed.").printf (p.acodec.up ());
            } else {
                string? hw = Encoders.pick (p.vcodec, true);
                string? sw = Encoders.pick (p.vcodec, false);
                if (p.master) info = Master.available (p.vcodec) ? _("Encoder: %s, 10 bit, PCM audio.").printf (Master.describe (p.vcodec)) : Master.install_hint ();
                else if (hw == null) info = _("No %s encoder is installed. Install the GStreamer plugins for it or choose WebM or AV1.").printf (p.vcodec.up ());
                else if (Encoders.is_hardware (hw)) info = _("Encoder: %s on the graphics card, with %s as the software fallback.").printf (hw, sw ?? _("none"));
                else info = _("Encoder: %s (software).").printf (hw);
            }
            fmt.description = info;
        }

        ExportPreset current_preset () {
            var p = selected.copy ();
            p.width = (int) width_row.value;
            p.height = (int) height_row.value;
            p.vbitrate = (int) bitrate_row.value;
            p.quality = (int) quality_row.value;
            p.max_size_mb = (int) max_size_row.value;
            p.reframe = reframe_drop.index == 1 ? "fill" : "fit";
            return p;
        }

        bool submit () {
            var p = current_preset ();
            string name = file_row.text.strip ();
            if (name == "") {
                fmt.description = _("Enter a file name.");
                return false;
            }
            if (!name.has_suffix ("." + p.extension)) name += "." + p.extension;
            var settings = new ExportSettings ();
            settings.preset = p;
            settings.output = folder.get_child (name);
            settings.hardware = hardware_row.active;
            string[] subs = { "none", "burn", "embed", "srt", "vtt" };
            settings.subtitles = subs[subtitles_drop.index];
            settings.chapters = chapters_row.active;
            settings.normalize = normalize_row.active;
            settings.loudness_target = targets[loudness_drop.index];
            settings.sequence_id = w.ctl.seq.id;
            var seq = w.ctl.seq;
            if (range_drop.index == 1) {
                settings.start = seq.in_point >= 0 ? seq.in_point : 0;
                settings.end = seq.out_point >= 0 ? seq.out_point : seq.duration;
            } else if (range_drop.index == 2) {
                settings.start = int64.max (0, w.ctl.playhead - 5 * Tc.SECOND);
                settings.end = int64.min (seq.duration, w.ctl.playhead + 5 * Tc.SECOND);
            }
            if (seq.duration <= 0) {
                fmt.description = _("The sequence is empty.");
                return false;
            }
            var app = (MontageApp) w.application;
            if (app.settings != null) app.settings.set_string ("last-preset", selected.id);
            var job = new ExportJob (w.project.clone (), settings);
            w.ctl.queue.add (job);
            w.say (_("Added %s to the export queue.").printf (name));
            return true;
        }
    }
}
