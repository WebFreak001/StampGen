module bitmap;

public import derelict.freetype.ft;
public import imageformats;

import std.algorithm;
import std.conv;
import std.file;
import std.math;
import std.path;
import std.process;
import std.range;
import std.string;
import std.traits;
import std.uni;
import std.utf;

ubyte[n] mix(ubyte n, F)(ubyte[n] a, ubyte[n] b, F fac)
		if (n >= 1 && n <= 4 && isFloatingPoint!F)
{
	ubyte[n] mixed;
	foreach (i; 0 .. n)
		mixed[i] = cast(ubyte)(a[i] * (1 - fac) + b[i] * fac);
	return mixed;
}

ubyte[n] blend(size_t n)(ubyte[n] fg, ubyte[n] bg, ubyte opacity = 255)
		if (n >= 1 && n <= 4)
{
	static if (n == 4 || n == 2)
	{
		ubyte[n] r;
		if (opacity != 255)
		{
			ubyte modA = cast(ubyte)(fg[n - 1] * cast(int) opacity / 256);
			r[n - 1] = cast(ubyte)(modA + bg[n - 1] * (255 - modA) / 256);
			if (r[n - 1] == 0)
				return r;
			foreach (c; 0 .. n - 1)
				r[c] = (fg[c] * cast(int) opacity / 256 + bg[c] * (255 - modA) / 256) & 0xFF;
		}
		else
		{
			r[n - 1] = cast(ubyte)(fg[n - 1] + bg[n - 1] * (255 - fg[n - 1]) / 256);
			if (r[n - 1] == 0)
				return r;
			foreach (c; 0 .. n - 1)
				r[c] = (fg[c] + bg[c] * (255 - fg[n - 1]) / 256) & 0xFF;
		}
		return r;
	}
	else
	{
		if (opacity != 255)
			return mix!n(bg, fg, opacity / 255.0);
		else
			return fg;
	}
}

void fillRect(ubyte n)(ref IFImage image, size_t x, size_t y, size_t w, size_t h, ubyte[n] pixel)
		if (n >= 1 && n <= 4)
{
	assert(n == image.c, "Wrong image format");
	if (w <= 0 || h <= 0)
		return;
	if (x + w < 0 || y + h < 0 || x >= image.w || y >= image.h)
		return;
	if (x < 0)
	{
		w -= x;
		x = 0;
	}
	if (y < 0)
	{
		h -= y;
		y = 0;
	}
	if (w <= 0 || h <= 0)
		return;
	if (x + w > image.w)
		w = image.w - x;
	if (y + h > image.h)
		h = image.h - y;
	ubyte[] row = new ubyte[n * w];
	for (size_t xx = 0; xx < w; xx++)
		row[xx * n .. xx * n + n] = pixel;
	for (size_t v; v < h; v++)
		image.pixels[(x + (y + v) * image.w) * n .. (x + w + (y + v) * image.w) * n] = row;
}

IFImage premultiply(IFImage image)
{
	if (image.c != ColFmt.RGBA)
		return image;
	for (size_t y = 0; y < image.h; y++)
		for (size_t x = 0; x < image.w; x++)
		{
			ubyte a = image.pixels[(x + y * image.w) * 4 + 3];
			image.pixels[(x + y * image.w) * 4 + 0] = cast(ubyte)(
					image.pixels[(x + y * image.w) * 4 + 0] * a / 256);
			image.pixels[(x + y * image.w) * 4 + 1] = cast(ubyte)(
					image.pixels[(x + y * image.w) * 4 + 1] * a / 256);
			image.pixels[(x + y * image.w) * 4 + 2] = cast(ubyte)(
					image.pixels[(x + y * image.w) * 4 + 2] * a / 256);
		}
	return image;
}

IFImage premultiplyReverse(IFImage image)
{
	if (image.c != ColFmt.RGBA)
		return image;
	for (size_t y = 0; y < image.h; y++)
		for (size_t x = 0; x < image.w; x++)
		{
			ubyte a = image.pixels[(x + y * image.w) * 4 + 3];
			ubyte r = image.pixels[(x + y * image.w) * 4 + 0];
			ubyte g = image.pixels[(x + y * image.w) * 4 + 1];
			ubyte b = image.pixels[(x + y * image.w) * 4 + 2];
			image.pixels[(x + y * image.w) * 4 + 2] = cast(ubyte)(r * a / 256);
			image.pixels[(x + y * image.w) * 4 + 1] = cast(ubyte)(g * a / 256);
			image.pixels[(x + y * image.w) * 4 + 0] = cast(ubyte)(b * a / 256);
		}
	return image;
}

void draw(size_t n)(ref IFImage image, FT_Bitmap bitmap, size_t x, size_t y, ubyte[n] color)
		if (n >= 1 && n <= 4)
{
	assert(image.c == n, "Wrong image format");
	if (bitmap.pitch <= 0)
		return;
	size_t w = bitmap.width;
	size_t h = bitmap.rows;
	if (x + w < 0 || y + h < 0 || x >= image.w || y >= image.h)
		return;
	if (x < 0)
	{
		w -= x;
		x = 0;
	}
	if (w <= 0 || h <= 0)
		return;
	if (x + w >= image.w)
		w = image.w - x - 1;
	if (bitmap.pixel_mode == FT_PIXEL_MODE_GRAY)
		for (size_t ly; ly < h; ly++)
			for (size_t lx; lx < w; lx++)
			{
				if (ly + y < 0 || ly + y >= image.h)
					continue;
				ubyte[n] col = color;
				ubyte a = bitmap.buffer[lx + ly * bitmap.pitch];
				col = mix(image.pixels[(lx + x + (ly + y) * image.w) * n .. (lx + x + (ly + y) * image.w)
						* n + n][0 .. n], color, a / 255.0f);
				image.pixels[(lx + x + (ly + y) * image.w) * n .. (lx + x + (ly + y) * image.w) * n + n] = blend(col,
						image.pixels[(lx + x + (ly + y) * image.w) * n .. (lx + x + (ly + y) * image.w) * n + n][0
							.. n]);
			}
	else
		throw new Exception("Unsupported bitmap format");
}

void draw(ref IFImage image, IFImage bitmap, size_t x, size_t y, size_t width = 0,
		size_t height = 0, ubyte opacity = 255)
{
	assert(bitmap.c == image.c, "Image format mismatch");
	size_t w = width == 0 ? bitmap.w : width;
	size_t h = height == 0 ? bitmap.h : height;
	if (w > bitmap.w)
		w = bitmap.w;
	if (h > bitmap.h)
		h = bitmap.h;
	if (x + w < 0 || y + h < 0 || x >= image.w || y >= image.h || opacity == 0)
		return;
	if (x < 0)
	{
		w -= x;
		x = 0;
	}
	if (w <= 0 || h <= 0)
		return;
	if (x + w >= image.w)
		w = image.w - x - 1;
	const runtimeChannels = cast(int) image.c;
ChannelSwitch:
	switch (runtimeChannels)
	{
		static foreach (c; [ColFmt.Y, ColFmt.YA, ColFmt.RGB, ColFmt.RGBA])
		{
	case c:
			for (size_t ly; ly < h; ly++)
				for (size_t lx; lx < w; lx++)
				{
					if (ly + y < 0 || ly + y >= image.h)
						continue;
					image.pixels[(lx + x + (ly + y) * image.w) * c .. (lx + x + (ly + y) * image.w) * c + c] = blend(
							bitmap.pixels[(lx + ly * bitmap.w) * c .. (lx + ly * bitmap.w) * c + c][0 .. c],
							image.pixels[(lx + x + (ly + y) * image.w) * c .. (lx + x + (ly + y) * image.w) * c
								+ c][0 .. c], opacity);
				}
			break ChannelSwitch;
		}
	default:
		assert(false);
	}
}

float[2] drawText(size_t n)(ref IFImage image, FontFamily font, size_t fontIndex,
		string text, float x, float y, ubyte[n] color) if (n >= 1 && n <= 4)
{
	FT_Face used = font.fonts[fontIndex];
	bool kerning = FT_HAS_KERNING(used);
	uint glyphIndex, prev;
	foreach (c; text.byDchar)
	{
		used = font.fonts[fontIndex];
		glyphIndex = FT_Get_Char_Index(used, cast(FT_ULong) c);
		if (kerning && prev && glyphIndex)
		{
			FT_Vector delta;
			FT_Get_Kerning(used, prev, glyphIndex, FT_Kerning_Mode.FT_KERNING_DEFAULT, &delta);
			x += delta.x / 64.0f;
			y += delta.y / 64.0f;
		}
		prev = glyphIndex;
		if (glyphIndex == 0)
		{
			used = font.fonts[$ - 1];
			glyphIndex = FT_Get_Char_Index(used, cast(FT_ULong) c);
		}
		if (FT_Load_Glyph(used, glyphIndex, FT_LOAD_RENDER))
			continue;

		image.draw(used.glyph.bitmap, cast(size_t)(x + used.glyph.bitmap_left),
				cast(size_t)(y - used.glyph.bitmap_top), color);

		x += used.glyph.advance.x / 64.0f;
		y += used.glyph.advance.y / 64.0f;
	}
	return [x, y];
}

float[2] measureText(FontFamily font, size_t fontIndex, string text)
{
	FT_Face used = font.fonts[fontIndex];
	float x, y;
	x = y = 0;
	float h = 0;
	bool kerning = FT_HAS_KERNING(used);
	uint glyphIndex, prev;
	foreach (c; text.byDchar)
	{
		used = font.fonts[fontIndex];
		glyphIndex = FT_Get_Char_Index(used, cast(FT_ULong) c);
		if (kerning && prev && glyphIndex)
		{
			FT_Vector delta;
			FT_Get_Kerning(used, prev, glyphIndex, FT_Kerning_Mode.FT_KERNING_DEFAULT, &delta);
			x += delta.x / 64.0f;
			y += delta.y / 64.0f;
		}
		prev = glyphIndex;
		if (glyphIndex == 0)
		{
			used = font.fonts[$ - 1];
			glyphIndex = FT_Get_Char_Index(used, cast(FT_ULong) c);
		}
		if (FT_Load_Glyph(used, glyphIndex, FT_LOAD_COMPUTE_METRICS))
			continue;

		x += used.glyph.advance.x / 64.0f;
		y += used.glyph.advance.y / 64.0f;
	}
	return [x, y];
}

struct FontFamily
{
	union
	{
		FT_Face[2] fonts;
		struct
		{
			FT_Face font, fallback;
		}
	}
}

void loadFace(FT_Library lib, string font, double fontSizeDots, FT_Face* face)
{
	string absPath;
	if (font.canFind("/"))
		absPath = font;
	else
	{
		auto fontProc = execute(["fc-match", font]);
		if (fontProc.status != 0)
			throw new Exception("fc-match returned non-zero");
		auto idx = fontProc.output.indexOf(':');
		string fontFile = fontProc.output[0 .. idx];
		foreach (file; dirEntries("/usr/share/fonts", SpanMode.depth))
			if (file.baseName == fontFile)
				absPath = file;
		if ("~/.local/share/fonts".expandTilde.exists)
			foreach (file; dirEntries("~/.local/share/fonts".expandTilde, SpanMode.depth))
				if (file.baseName == fontFile)
					absPath = file;
	}
	import std.stdio;

	writeln("Loading font from ", absPath);
	enforceFT(FT_New_Face(lib, absPath.toStringz, 0, face));
	enforceFT(FT_Set_Char_Size(*face, 0, cast(int) round(fontSizeDots * 64), 0, 0));
	enforceFT(FT_Select_Charmap(*face, FT_ENCODING_UNICODE));
}

enum FTErrors
{
	FT_Err_Ok = 0x00,
	FT_Err_Cannot_Open_Resource = 0x01,
	FT_Err_Unknown_File_Format = 0x02,
	FT_Err_Invalid_File_Format = 0x03,
	FT_Err_Invalid_Version = 0x04,
	FT_Err_Lower_Module_Version = 0x05,
	FT_Err_Invalid_Argument = 0x06,
	FT_Err_Unimplemented_Feature = 0x07,
	FT_Err_Invalid_Table = 0x08,
	FT_Err_Invalid_Offset = 0x09,
	FT_Err_Array_Too_Large = 0x0A,
	FT_Err_Missing_Module = 0x0B,
	FT_Err_Missing_Property = 0x0C,

	FT_Err_Invalid_Glyph_Index = 0x10,
	FT_Err_Invalid_Character_Code = 0x11,
	FT_Err_Invalid_Glyph_Format = 0x12,
	FT_Err_Cannot_Render_Glyph = 0x13,
	FT_Err_Invalid_Outline = 0x14,
	FT_Err_Invalid_Composite = 0x15,
	FT_Err_Too_Many_Hints = 0x16,
	FT_Err_Invalid_Pixel_Size = 0x17,

	FT_Err_Invalid_Handle = 0x20,
	FT_Err_Invalid_Library_Handle = 0x21,
	FT_Err_Invalid_Driver_Handle = 0x22,
	FT_Err_Invalid_Face_Handle = 0x23,
	FT_Err_Invalid_Size_Handle = 0x24,
	FT_Err_Invalid_Slot_Handle = 0x25,
	FT_Err_Invalid_CharMap_Handle = 0x26,
	FT_Err_Invalid_Cache_Handle = 0x27,
	FT_Err_Invalid_Stream_Handle = 0x28,

	FT_Err_Too_Many_Drivers = 0x30,
	FT_Err_Too_Many_Extensions = 0x31,

	FT_Err_Out_Of_Memory = 0x40,
	FT_Err_Unlisted_Object = 0x41,

	FT_Err_Cannot_Open_Stream = 0x51,
	FT_Err_Invalid_Stream_Seek = 0x52,
	FT_Err_Invalid_Stream_Skip = 0x53,
	FT_Err_Invalid_Stream_Read = 0x54,
	FT_Err_Invalid_Stream_Operation = 0x55,
	FT_Err_Invalid_Frame_Operation = 0x56,
	FT_Err_Nested_Frame_Access = 0x57,
	FT_Err_Invalid_Frame_Read = 0x58,

	FT_Err_Raster_Uninitialized = 0x60,
	FT_Err_Raster_Corrupted = 0x61,
	FT_Err_Raster_Overflow = 0x62,
	FT_Err_Raster_Negative_Height = 0x63,

	FT_Err_Too_Many_Caches = 0x70,

	FT_Err_Invalid_Opcode = 0x80,
	FT_Err_Too_Few_Arguments = 0x81,
	FT_Err_Stack_Overflow = 0x82,
	FT_Err_Code_Overflow = 0x83,
	FT_Err_Bad_Argument = 0x84,
	FT_Err_Divide_By_Zero = 0x85,
	FT_Err_Invalid_Reference = 0x86,
	FT_Err_Debug_OpCode = 0x87,
	FT_Err_ENDF_In_Exec_Stream = 0x88,
	FT_Err_Nested_DEFS = 0x89,
	FT_Err_Invalid_CodeRange = 0x8A,
	FT_Err_Execution_Too_Long = 0x8B,
	FT_Err_Too_Many_Function_Defs = 0x8C,
	FT_Err_Too_Many_Instruction_Defs = 0x8D,
	FT_Err_Table_Missing = 0x8E,
	FT_Err_Horiz_Header_Missing = 0x8F,
	FT_Err_Locations_Missing = 0x90,
	FT_Err_Name_Table_Missing = 0x91,
	FT_Err_CMap_Table_Missing = 0x92,
	FT_Err_Hmtx_Table_Missing = 0x93,
	FT_Err_Post_Table_Missing = 0x94,
	FT_Err_Invalid_Horiz_Metrics = 0x95,
	FT_Err_Invalid_CharMap_Format = 0x96,
	FT_Err_Invalid_PPem = 0x97,
	FT_Err_Invalid_Vert_Metrics = 0x98,
	FT_Err_Could_Not_Find_Context = 0x99,
	FT_Err_Invalid_Post_Table_Format = 0x9A,
	FT_Err_Invalid_Post_Table = 0x9B,

	FT_Err_Syntax_Error = 0xA0,
	FT_Err_Stack_Underflow = 0xA1,
	FT_Err_Ignore = 0xA2,
	FT_Err_No_Unicode_Glyph_Name = 0xA3,
	FT_Err_Glyph_Too_Big = 0xA4,

	FT_Err_Missing_Startfont_Field = 0xB0,
	FT_Err_Missing_Font_Field = 0xB1,
	FT_Err_Missing_Size_Field = 0xB2,
	FT_Err_Missing_Fontboundingbox_Field = 0xB3,
	FT_Err_Missing_Chars_Field = 0xB4,
	FT_Err_Missing_Startchar_Field = 0xB5,
	FT_Err_Missing_Encoding_Field = 0xB6,
	FT_Err_Missing_Bbx_Field = 0xB7,
	FT_Err_Bbx_Too_Big = 0xB8,
	FT_Err_Corrupted_Font_Header = 0xB9,
	FT_Err_Corrupted_Font_Glyphs = 0xBA,

	FT_Err_Max,
}

void enforceFT(FT_Error err)
{
	if (err == 0)
		return;
	throw new Exception((cast(FTErrors) err).to!string);
}
