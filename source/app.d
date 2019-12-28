import std.algorithm;
import std.ascii;
import std.conv;
import std.exception;
import std.format;
import std.getopt;
import std.math;
import std.stdio;

import barcode;
import bitmap;

enum A4_width_mm = 210.0;
enum A4_height_mm = 297.0;

enum min_safety_margin_mm = 1.0;

enum expected_size_bits = 21;

enum ipmm = 1.0 / 25.4;

FontFamily gfont;
double fontSizeDots = 0;

void main(string[] args)
{
	string format = "in:p%s";
	string textFormat = "%s";
	string base = digits ~ uppercase;
	long exp = 4; // 2 ^^ exp
	bool portrait = false;
	double targetDPI = 600;
	double fontSize = 70;
	long start = 36 * 36;
	string outputFile = "output.png";

	string font = "monospace", fontFallback = "Noto Sans";

	//dfmt off
	auto opt = args.getopt(
		"f|format", "The format for the QR code string to use. Insert an %s for the counting variable.", &format,
		"t|text", "The format for the human readable text string to use. Insert an %s for the counting variable.", &textFormat,
		"base", "Characters to use for counting. Use '0123456789' for decimal. Defaults to '" ~ base ~ "'", &base,
		"n|exp", "How many cuts (exponential) to make. Or: 2^n = the number of stickers on the x axis. One cut cuts the whole page into 4 rectangle, each further cut cuts all rectangles.", &exp,
		"p|portrait", "Use portrait mode stickers. If this is given, the stickers will be in size A4, A6, A8, A10, etc. Otherwise stickers will be in size A5, A7, A9, A11, etc.", &portrait,
		"d|dpi", "DPI of the generated image. Higher DPI means more pixels of same content. QR codes are always pixel perfectly scaled, so various DPI values will simply change paddings between each sticker until they fit at a bigger scale. Defaults to " ~ targetDPI.to!string, &targetDPI,
		"i|start", "The default count to start at. Defaults to " ~ start.to!string, &start,
		"o|out|output", "The image file to write to. Supported formats determined by extension: .png, .tga, .bmp; Defaults to " ~ outputFile, &outputFile,
		"font", "The font to write the text with. Defaults to " ~ font, &font,
		"fallbackfont", "The font to use when characters aren't present in the first font. Defaults to " ~ fontFallback, &fontFallback,
		"fontsize", "The font size (in units relative to each sticker size) to use for the human readable text. Defaults to " ~ fontSize.to!string, &fontSize,
	);
	//dfmt on
	if (opt.helpWanted)
	{
		defaultGetoptPrinter("Inventory stamp image generator", opt.options);
		return;
	}

	enforce(start >= 0, "Start number must be positive");
	enforce(base.length >= 2, "base must have at least 2 characters");

	DerelictFT.load();

	FT_Library ft;
	FT_Init_FreeType(&ft);

	long num = pow(2, exp);

	fontSizeDots = fontSize / num * targetDPI * ipmm;

	loadFace(ft, font, fontSizeDots, &gfont.font);
	loadFace(ft, fontFallback, fontSizeDots, &gfont.fallback);

	if (portrait)
		render!(A4_width_mm, A4_height_mm)(num, num, format, textFormat, base,
				targetDPI, start, outputFile);
	else
		render!(A4_height_mm, A4_width_mm)(num, num / 2, format, textFormat, base,
				targetDPI, start, outputFile);
}

void render(double width_mm, double height_mm)(long numX, long numY, string format,
		string textFormat, string base, double targetDPI, long start, string outputFile)
{
	const barcode_width_mm = (width_mm - numX * min_safety_margin_mm * 2) / numX;
	writefln("barcode size (mm): %.1f", barcode_width_mm);

	const pixelCountExact = barcode_width_mm * targetDPI * ipmm;
	const marginPixels = cast(int) round(min_safety_margin_mm * targetDPI * ipmm);
	const pixelsPerQRBit = cast(int) floor(pixelCountExact / expected_size_bits);
	const qrBitOffset = -pixelsPerQRBit / 2;
	const stampPixelWidth = cast(int)(pixelsPerQRBit * expected_size_bits + round(
			min_safety_margin_mm * 2 * targetDPI * ipmm));
	const stampPixelHeight = cast(int) round(stampPixelWidth * sqrt(2.0)); // DIN-A sqrt(2) ratios
	writeln("used pixel width per barcode: ", stampPixelWidth,
			", available area per barcode: ", width_mm / numX * targetDPI * ipmm);

	const exactWidth = cast(int) round(width_mm * targetDPI * ipmm);
	const exactHeight = cast(int) round(height_mm * targetDPI * ipmm);

	IFImage image;
	image.w = exactWidth;
	image.h = exactHeight;
	image.c = ColFmt.Y;
	image.pixels = new ubyte[image.w * image.h * image.c];
	image.pixels[] = 0;

	auto qr = new Qr();

	foreach (y; 0 .. numY)
		foreach (x; 0 .. numX)
		{
			const n = x + y * numX + start;
			string id = serialize(format, base, n);
			string text = serialize(textFormat, base, n);
			auto code = qr.encode(id);
			if (code.width > expected_size_bits || code.height > expected_size_bits)
				stderr.writeln("warning: ID ", id, " (", text, ") is ", code.width,
						"x", code.height, " and will extend over protection regions");

			const px_x = exactWidth / numX * x;
			const px_y = exactHeight / numY * y;

			image.fillRect!1(px_x + 1, px_y + 1, stampPixelWidth - 2, stampPixelHeight - 2, [
					255
					]); // at least 2px border for cutting lines

			const qr_center_x = px_x + stampPixelWidth / 2;
			const qr_center_y = px_y + stampPixelWidth / 2;

			const half_w = code.width / 2;
			const half_h = code.height / 2;

			foreach (qy; 0 .. code.height)
				foreach (qx; 0 .. code.width)
					if (code[qx, qy])
						image.fillRect!1(qr_center_x + (qx - half_w) * pixelsPerQRBit + qrBitOffset,
								qr_center_y + (qy - half_h) * pixelsPerQRBit + qrBitOffset,
								pixelsPerQRBit, pixelsPerQRBit, [0]);

			const qr_edge_y = px_y + stampPixelWidth / 2 + (
					code.height - 1 - half_h) * pixelsPerQRBit + pixelsPerQRBit;
			const gray_area_height = stampPixelHeight - 1 - (qr_edge_y - px_y);
			// image.fillRect!1(px_x + 1, qr_edge_y, stampPixelWidth - 2, gray_area_height, [
			// 		180
			// 		]);
			image.fillRect!1(px_x + 1, qr_edge_y, stampPixelWidth - 2, pixelsPerQRBit / 2, [
					0
					]);

			const text_size = measureText(gfont, 0, text);
			image.drawText!1(gfont, 0, text, qr_center_x - text_size[0] / 2,
					px_y + stampPixelHeight - gray_area_height / 2 - marginPixels / 2 + cast(int) fontSizeDots / 2,
					[0]);
		}

	write_image(outputFile, image.w, image.h, image.pixels, image.c);
	writeln("written ", numX * numY, " stamps into ", outputFile);
}

string serialize(string fmt, string base, long n)
{
	assert(n >= 0);

	const b = base.length;
	int len = 0;
	char[64] buf;
	while (n > 0)
	{
		auto d = n % b;
		n /= b;
		buf[len++] = base[d];
	}

	const(char)[] digit;
	if (len == 0)
	{
		digit = base[0 .. 1];
	}
	else
	{
		auto tmp = buf[0 .. len];
		reverse(tmp);
		digit = tmp;
	}

	return format(fmt, digit);
}
