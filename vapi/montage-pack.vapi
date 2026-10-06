[CCode (cheader_filename = "master_pack.h")]
namespace MasterPack {
    [CCode (cname = "montage_master_pack")]
    public void pack ([CCode (array_length = false)] uint16[] rgba, int width, int height, int layout, [CCode (array_length = false)] uint8[] output, [CCode (array_length = false)] size_t[] offsets, [CCode (array_length = false)] int[] strides);
}
