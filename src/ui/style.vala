namespace Singularity.Apps.Montage {
    namespace Style {
        public const string CSS = """
.montage-monitor {
  background-color: @card_bg;
  border-radius: 16px;
  padding: 6px 6px 0 6px;
}
.sx-inspector {
  border-left: 1px solid @border_color;
}
.montage-status {
  padding: 4px 14px 6px 14px;
  border-top: 1px solid @border_color;
}
.montage-thumb {
  border-radius: 6px;
  background-color: @card_bg;
}
.sx-media-bin .montage-media-row {
  padding-top: 4px;
  padding-bottom: 4px;
}
.sx-channel-strip {
  padding: 8px 4px;
  border-radius: 12px;
}
.sx-channel-strip.selected {
  background-color: alpha(@accent_color, 0.14);
}
.sx-channel-strip.master {
  margin-left: 6px;
}
.sx-strip-pan {
  margin-left: 6px;
  margin-right: 6px;
}
.sx-strip-toggle {
  min-width: 26px;
  min-height: 22px;
  padding: 0 4px;
  font-size: 11px;
  font-weight: 700;
  background-color: @card_bg;
}
.sx-strip-toggle.mute:checked {
  background-color: @warning_color;
  color: rgba(0, 0, 0, 0.85);
}
.sx-strip-toggle.solo:checked {
  background-color: @success_color;
  color: rgba(0, 0, 0, 0.85);
}
.sx-strip-menu {
  min-height: 24px;
  padding: 0 6px;
  margin-left: 2px;
  margin-right: 2px;
}
.montage-meter {
  min-width: 6px;
  border-radius: 3px;
}
""";
    }
}
