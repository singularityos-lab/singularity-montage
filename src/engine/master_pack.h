#pragma once

#include <glib.h>

void montage_master_pack (const guint16 *rgba, int width, int height, int layout, guint8 *out, const gsize *offsets, const gint *strides);
