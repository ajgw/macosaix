#import "Tiles.h"

#import "MacOSaiXDisallowedImage.h"
#import "MacOSaiXDocument.h"
#import "MacOSaiXImageOrientations.h"
#import "NSBezierPath+MacOSaiX.h"


@interface MacOSaiXMosaic (TilePrivate)
- (void)tileDidExtractBitmap:(MacOSaiXTile *)tile;
@end


@implementation MacOSaiXTile


- (id)initWithOutline:(NSBezierPath *)inOutline 
	 imageOrientation:(NSNumber *)angle
			   mosaic:(MacOSaiXMosaic *)inMosaic;
{
	if (self = [super init])
	{
		[self setOutline:inOutline];
		[self setImageOrientation:angle];
		[self setMosaic:inMosaic];
		
		disallowedImages = [[NSMutableArray array] retain];
	}
	return self;
}


- (void)setMosaic:(MacOSaiXMosaic *)inMosaic
{
	mosaic = inMosaic;	// non-retained, it retains us
}


- (MacOSaiXMosaic *)mosaic
{
	return mosaic;
}

- (void)setOutline:(NSBezierPath *)inOutline
{
    [outline autorelease];
    outline = [inOutline retain];
}


- (NSBezierPath *)outline
{
    return outline;
}


- (NSBezierPath *)rotatedOutline
{
		// Rotate the outline to offset the tile's image orientation.  The rotated outline will be centered at the origin.
	NSAffineTransform	*transform = [NSAffineTransform transform];
	NSPoint				rotationPoint = NSMakePoint(NSMidX([outline bounds]), NSMidY([outline bounds]));
	
	[transform translateXBy:rotationPoint.x yBy:rotationPoint.y];
	[transform rotateByDegrees:-[self imageOrientationAngle]];
	[transform translateXBy:-rotationPoint.x yBy:-rotationPoint.y];
	
	return [transform transformBezierPath:outline];
}


- (void)setImageOrientation:(NSNumber *)angle
{
	[imageOrientation release];
	imageOrientation = [angle retain];
}


- (NSNumber *)imageOrientation
{
	return imageOrientation;
}


- (float)imageOrientationAngle
{
	float	angle = 0.0;
	
	if (imageOrientation)
		angle = [imageOrientation floatValue];
	else
		angle = [[mosaic imageOrientations] imageOrientationAtPoint:NSMakePoint(NSMidX([[self outline] bounds]), NSMidY([[self outline] bounds])) 
													   inRectOfSize:[[mosaic targetImage] size]];
	
	return angle;
}


- (float)worstCaseMatchValue
{
	return 255.0 * 255.0 * 9.0;
}


- (void)resetBitmapRepAndMask
{
		// TODO: this should not be called from outside.  we should listen for notifications 
		// that the target image or tile shapes changed for our mosaic and reset at that
		// point.
    [bitmapRep autorelease];
    bitmapRep = nil;
    [maskRep autorelease];
    maskRep = nil;
}


- (void)createBitmapRep
{
	NSBezierPath		*rotatedOutline = [self rotatedOutline];
	NSRect				rotatedBounds = [rotatedOutline bounds];
	BOOL				widthLimited = (NSWidth(rotatedBounds) > NSHeight(rotatedBounds));
	
		// Scale the rotated outline to the bitmap size.
	NSAffineTransform	*transform = [NSAffineTransform transform];
	if (widthLimited)
		[transform scaleBy:TILE_BITMAP_SIZE / NSWidth(rotatedBounds)];
	else
		[transform scaleBy:TILE_BITMAP_SIZE / NSHeight(rotatedBounds)];
	[transform translateXBy:-NSMinX(rotatedBounds) yBy:-NSMinY(rotatedBounds)];
	NSBezierPath		*bitmapOutline = [transform transformBezierPath:rotatedOutline];
	NSRect				bitmapBounds = [bitmapOutline bounds];
	if (widthLimited)
		bitmapBounds.origin.y = (TILE_BITMAP_SIZE - NSHeight(bitmapBounds)) / 2.0;
	else
		bitmapBounds.origin.x = (TILE_BITMAP_SIZE - NSWidth(bitmapBounds)) / 2.0;
	
	// TODO: If this is done with CG instead of Cocoa then it doesn't have to be on the main thread.
	BOOL				focusLocked = NO;
	NSImage				*workingImage = [[NSImage alloc] initWithSize:NSMakeSize(TILE_BITMAP_SIZE, TILE_BITMAP_SIZE)];
	
	NS_DURING
		[workingImage lockFocus];
		focusLocked = YES;
		
			// Start with a clear image.
		[[NSColor clearColor] set];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, TILE_BITMAP_SIZE, TILE_BITMAP_SIZE)] fill];
		
			// Draw the target image so that the correct portion of the image is rendered at the correct orientation inside the working image.
		NSImageInterpolation	previousInterpolation = [[NSGraphicsContext currentContext] imageInterpolation];
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
		[[NSGraphicsContext currentContext] saveGraphicsState];
			NSAffineTransform	*transform = [NSAffineTransform transform];
			[transform translateXBy:TILE_BITMAP_SIZE / 2.0 yBy:TILE_BITMAP_SIZE / 2.0];
			[transform scaleBy:NSWidth(bitmapBounds) / NSWidth(rotatedBounds)];
			[transform rotateByDegrees:-[self imageOrientationAngle]];
			[transform translateXBy:-NSMidX(rotatedBounds) yBy:-NSMidY(rotatedBounds)];
			[transform concat];
			
			NSImage				*targetImage = [mosaic targetImage];
			NSRect				targetImageBounds = NSMakeRect(0.0, 0.0, [targetImage size].width, [targetImage size].height);
			[targetImage drawInRect:targetImageBounds 
							 fromRect:targetImageBounds 
							operation:NSCompositeCopy 
							 fraction:1.0];
		[[NSGraphicsContext currentContext] restoreGraphicsState];
		[[NSGraphicsContext currentContext] setImageInterpolation:previousInterpolation];
		
		bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:bitmapBounds];
		#ifdef DEBUG
			if (bitmapRep == nil)
				NSLog(@"Could not extract tile image from target.");
		#endif
	NS_HANDLER
		#ifdef DEBUG
			NSLog(@"Exception raised while extracting tile images: %@", [localException name]);
		#endif
	NS_ENDHANDLER
	
	if (focusLocked)
		[workingImage unlockFocus];
	
	[workingImage release];

		// Calculate a mask image using the tile's outline that is the same size as the image extracted from the target.  The mask will be white for pixels that are inside the tile and black outside.
		// (This would work better if we could just replace the previous rep's alpha channel but I haven't figured out an easy way to do that yet.)
	maskRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil 
													   pixelsWide:[bitmapRep size].width
													   pixelsHigh:[bitmapRep size].height 
													bitsPerSample:8 
												  samplesPerPixel:1 
														 hasAlpha:NO 
														 isPlanar:NO 
												   colorSpaceName:NSCalibratedWhiteColorSpace 
													  bytesPerRow:0 
													 bitsPerPixel:0];
	CGColorSpaceRef	grayscaleColorSpace = CGColorSpaceCreateDeviceGray();
	CGContextRef	bitmapContext = CGBitmapContextCreate([maskRep bitmapData], 
														  [maskRep pixelsWide], 
														  [maskRep pixelsHigh], 
														  [maskRep bitsPerSample], 
														  [maskRep bytesPerRow], 
														  grayscaleColorSpace,
														  kCGBitmapByteOrderDefault);
	
		// Start with a black background.
	CGContextSetGrayFillColor(bitmapContext, 0.0, 1.0);
	CGRect				cgDestRect = CGRectMake(0.0, 0.0, bitmapBounds.size.width, bitmapBounds.size.height);
	CGContextFillRect(bitmapContext, cgDestRect);
	
		// Fill the tile's outline with white.
	CGPathRef			cgTileOutline = [bitmapOutline quartzPath];
	CGContextSetGrayFillColor(bitmapContext, 1.0, 1.0);
	CGContextBeginPath(bitmapContext);
	CGContextAddPath(bitmapContext, cgTileOutline);
	CGContextClosePath(bitmapContext);
	CGContextFillPath(bitmapContext);
	CGPathRelease(cgTileOutline);
	
	CGContextRelease(bitmapContext);
	CGColorSpaceRelease(grayscaleColorSpace);
}


- (NSBitmapImageRep *)bitmapRep
{
	if (!bitmapRep)
	{
		[self performSelectorOnMainThread:@selector(createBitmapRep) withObject:nil waitUntilDone:YES];
		
		[mosaic tileDidExtractBitmap:self];
	}
	
    return bitmapRep;
}


- (NSBitmapImageRep *)maskRep
{
	return maskRep;
}


- (NSColor *)averageTargetColor
{
	if (!averageTargetColor)
	{
		float				redValue = 0.0, 
							greenValue = 0.0, 
							blueValue = 0.0;
		int					bytesPerPixel = [[self bitmapRep] hasAlpha] ? 4 : 3, 
							bytesPerRow = [bitmapRep bytesPerRow], 
							xSize = [bitmapRep size].width,
							ySize = [bitmapRep size].height;
		float				pixelCount = 0.0;
		unsigned char		*bitmapBytes = [bitmapRep bitmapData], 
							*maskBytes = [maskRep bitmapData];
		
			// Add up the color values of all the pixels weighted by the mask.
		int				x, y;
		for (x = 0; x < xSize; x++)
		{
			for (y = 0; y < ySize; y++)
			{
				unsigned char	*bitmap_off = bitmapBytes + x * bytesPerPixel + y * bytesPerRow;
				float			maskValue = *(maskBytes++) / 255.0;	// 0.0 <-> 1.0
				
				redValue += *bitmap_off / 255.0 * maskValue;
				greenValue += *(bitmap_off + 1) / 255.0 * maskValue;
				blueValue += *(bitmap_off + 2) / 255.0 * maskValue;
				
				pixelCount += maskValue;
			}
		}
		
		averageTargetColor = [[NSColor colorWithCalibratedRed:redValue / pixelCount 
														green:greenValue / pixelCount 
														 blue:blueValue / pixelCount 
														alpha:1.0] retain];
	}
	
	return averageTargetColor;
}


- (void)sendNotificationThatImageContentsChangedFromPreviousMatch:(MacOSaiXImageMatch *)previousMatch
{
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXTileContentsDidChangeNotification
														object:mosaic 
													  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
																	self, @"Tile", 
																	previousMatch, @"Previous Match",
																	nil]];
}


- (void)setFillStyle:(MacOSaiXTileFillStyle)style
{
	if (style != fillStyle)
	{
		MacOSaiXImageMatch	*previousMatch = nil;
		
		if (style == fillWithUniqueMatch)
			previousMatch = uniqueImageMatch;
		else if (style == fillWithHandPicked)
			previousMatch = userChosenImageMatch;
		else if (style == fillWithColor)
			[self setFillColor:[NSColor blackColor]];
		
		fillStyle = style;
		
		if (outline)
			[self sendNotificationThatImageContentsChangedFromPreviousMatch:previousMatch];
	}
}


- (MacOSaiXTileFillStyle)fillStyle
{
	return fillStyle;
}


- (void)setUniqueImageMatch:(MacOSaiXImageMatch *)match
{
	if (match != uniqueImageMatch)
	{
		MacOSaiXImageMatch	*previousMatch = uniqueImageMatch;
		
		[uniqueImageMatch autorelease];
		uniqueImageMatch = [match retain];
		
		if ([self fillStyle] == fillWithUniqueMatch)
			[self sendNotificationThatImageContentsChangedFromPreviousMatch:previousMatch];
	}
}


- (MacOSaiXImageMatch *)uniqueImageMatch
{
	return [[uniqueImageMatch retain] autorelease];
}


- (void)setBestImageMatch:(MacOSaiXImageMatch *)match
{
	if (match != bestImageMatch)
	{
		[bestImageMatch autorelease];
		bestImageMatch = [match retain];
	}
}


- (MacOSaiXImageMatch *)bestImageMatch
{
	return [[bestImageMatch retain] autorelease];
}


- (void)setUserChosenImageMatch:(MacOSaiXImageMatch *)match
{
	if (match != userChosenImageMatch)
	{
		MacOSaiXImageMatch	*previousMatch = userChosenImageMatch;
		
		[userChosenImageMatch autorelease];
		userChosenImageMatch = [match retain];
		
		if ([self fillStyle] == fillWithHandPicked)
			[self sendNotificationThatImageContentsChangedFromPreviousMatch:previousMatch];
	}
}


- (MacOSaiXImageMatch *)userChosenImageMatch;
{
	return [[userChosenImageMatch retain] autorelease];
}


- (void)setFillColor:(NSColor *)color
{
	if (![color isEqualTo:fillColor])
	{
		[fillColor release];
		fillColor = [color retain];
		
		if ([self fillStyle] == fillWithColor)
			[self sendNotificationThatImageContentsChangedFromPreviousMatch:nil];
	}
}


- (NSColor *)fillColor
{
	if ([self fillStyle] == fillWithAverageTargetColor)
		return [self averageTargetColor];
	else
		return fillColor;
}


- (void)disallowImage:(id)image
{
	[disallowedImages addObject:image];
	
	if ([self fillStyle] == fillWithUniqueMatch && [image isEqualTo:[[self uniqueImageMatch] sourceImage]])
		[self setUniqueImageMatch:nil];
}


- (NSArray *)disallowedImages
{
	return [NSArray arrayWithArray:disallowedImages];
}


- (void)dealloc
{
    [outline release];
    [bitmapRep release];
	[maskRep release];
	[averageTargetColor release];
	[uniqueImageMatch release];
    [userChosenImageMatch release];
	[bestImageMatch release];
	[fillColor release];
	[disallowedImages release];
	
    [super dealloc];
}


@end
